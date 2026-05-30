# Proton 11 on Android Termux

在 Android 手机上运行 Windows 游戏的完整方案。通过 Box64 CPU 模拟 + Proton 11 兼容层 + DXVK/wined3d 软件渲染 + PulseAudio AAudio 音频输出，实现在没有硬件 GPU 加速的 Android 设备上运行 DirectX 9/11 游戏。

## 实现原理

### 整体架构

Windows 游戏无法直接在 Android 上运行，因为存在四层鸿沟：

```
Android (ARM64/Linux/Bionic)  ←→  Windows (x86_64/Win32/NT)
```

本项目通过 6 层翻译/兼容层，逐层跨越这些鸿沟：

```
┌─────────────────────────────────────────────────────────────┐
│                    Windows 游戏 (.exe)                       │
│              DirectX 9/11 + Win32 API 调用                   │
└──────────┬──────────────────────┬───────────────────────────┘
           │                      │
     图形 API 调用          系统 API 调用
           │                      │
┌──────────▼──────────┐ ┌────────▼──────────────────────────┐
│  第1层: DXVK/wined3d │ │  第2层: Proton 11 (Wine)          │
│  DirectX → Vulkan/   │ │  Win32 API → POSIX API            │
│  DirectX → OpenGL    │ │  注册表、文件系统、进程管理等      │
└──────────┬──────────┘ └────────┬──────────────────────────┘
           │                      │
     Vulkan/OpenGL 调用     x86_64 机器码
           │                      │
┌──────────▼──────────┐ ┌────────▼──────────────────────────┐
│  第3层: Mesa 软件    │ │  第4层: Box64                      │
│  渲染器              │ │  x86_64 → ARM64 动态重编译         │
│  lavapipe (Vulkan)   │ │  系统库 wrapper 翻译              │
│  llvmpipe (OpenGL)   │ │  WoW64 支持 32位+64位             │
└──────────┬──────────┘ └────────┬──────────────────────────┘
           │                      │
     像素数据              ARM64 机器码
           │                      │
┌──────────▼──────────┐ ┌────────▼──────────────────────────┐
│  第5层: X11/VNC      │ │  第6层: Termux (Bionic libc)      │
│  TigerVNC 远程显示   │ │  Android 用户空间 Linux 环境       │
│  端口 5901           │ │  aarch64 原生运行                  │
└──────────────────────┘ └──────────────────────────────────┘
```

### 第1层：图形 API 翻译 (DXVK / wined3d)

Windows 游戏使用 DirectX 图形 API，Linux 没有 DirectX。需要将 DirectX 调用翻译为 Linux 支持的图形 API：

**DX11+ 游戏** → 使用 **DXVK**：
```
游戏调用 D3D11 API
    → DXVK 的 d3d11.dll (native, 替代 Wine 内置版本)
    → 翻译为 Vulkan API 调用
    → lavapipe 执行 Vulkan 渲染 (CPU 软件实现)
    → 像素数据写入 X11 窗口
```

**DX9 游戏** → 使用 **wined3d**：
```
游戏调用 D3D9 API
    → wined3d (Wine 内置翻译层)
    → 翻译为 OpenGL API 调用
    → llvmpipe 执行 OpenGL 渲染 (CPU 软件实现)
    → 像素数据写入 X11 窗口
```

为什么 DX11 不用 wined3d？因为 wined3d 的 D3D11 实现不完整，很多游戏无法运行。DXVK 是成熟的 D3D9/10/11 → Vulkan 翻译层，兼容性好得多。

为什么 DX9 不用 DXVK 的 D3D9 组件 (DXVK-native)？因为在 lavapipe 上 DXVK 的 D3D9 实现不如 wined3d + llvmpipe 稳定。

### 第2层：系统 API 翻译 (Proton 11 / Wine)

Windows 游戏调用 Win32 API（CreateWindow、CreateFile、RegOpenKey 等），Linux 没有这些 API。Wine 提供了完整的 Win32 → POSIX 翻译：

```
游戏调用 CreateFileW("C:\\game\\data.dat", ...)
    → Wine 翻译为 openat(AT_FDCWD, "/home/user/.wine/drive_c/game/data.dat", ...)
    → 返回文件描述符，游戏认为自己在 Windows 上
```

**为什么用 Proton 而不是普通 Wine？**
- Proton 是 Valve 基于 Wine 的增强版本，包含额外的兼容性补丁
- Proton 的 WoW64 (Windows on Windows 64) 支持更好，可以同时运行 32 位和 64 位程序
- 本项目使用 Proton 11.0-1 x86_64 Bionic 版本（专为 Android Bionic libc 编译）

**Wineprefix（Windows 虚拟环境）：**
- Wine 在 Linux 上模拟一个完整的 Windows 文件系统
- `p11prefix/drive_d/windows/system32/` — 包含 808+ DLL 文件
- `p11prefix/drive_d/windows/Fonts/` — 包含中文字体
- `p11prefix/drive_d/windows/mono/` — 包含 .NET 运行时
- `p11prefix/user.reg` — 注册表，包含 DLL 覆盖规则和字体替代

**关键细节 — drive_c → drive_d 符号链接：**
Proton 使用 `drive_d` 作为 Windows 系统目录，但 Wine 内部通过 `C:\` 路径操作，映射到 `drive_c`。如果没有 `drive_c → drive_d` 符号链接，Wineboot 初始化时所有 DLL 安装都会失败（error=3）。

### 第3层：软件渲染 (Mesa lavapipe / llvmpipe)

Android 设备的 GPU (Adreno) 驱动无法在 Termux 中直接使用（需要 Android HAL，不能被普通进程加载）。因此使用 CPU 软件渲染：

- **lavapipe**：Mesa 的软件 Vulkan 实现，通过 llvmpipe Gallium 驱动执行 Vulkan 管线
- **llvmpipe**：Mesa 的软件 OpenGL 实现，使用 LLVM 在运行时生成优化的 SIMD 代码

```
Vulkan 调用 (vkCmdDraw, vkCreateBuffer, ...)
    → lavapipe 接收 Vulkan 命令
    → 转换为 Gallium3D 管线操作
    → llvmpipe 使用 LLVM JIT 编译着色器
    → CPU 执行顶点处理 + 光栅化 + 片段着色
    → 像素写入帧缓冲 → X11 显示
```

性能：软件渲染当然比硬件 GPU 慢，但对于 2D/轻度 3D 视觉小说游戏来说足够流畅。

### 第4层：CPU 指令翻译 (Box64)

游戏是 x86_64 机器码，Android 设备是 ARM64 CPU，指令集完全不同。Box64 通过**动态重编译 (DynaRec)** 实时翻译：

```
x86_64 指令流
    → Box64 DynaRec 识别代码块 (Basic Block)
    → 翻译为等价的 ARM64 指令序列
    → 执行翻译后的 ARM64 代码
    → 缓存翻译结果 (DynaCache)，下次直接执行
```

**系统库 wrapper：**
Wine 程序会链接 x86_64 的 libpulse.so、libvulkan.so 等，但系统只有 aarch64 版本。Box64 内置了这些库的 wrapper，将 x86_64 的函数调用翻译为 aarch64 原生调用：

```
Wine (x86_64) 调用 pa_simple_new()
    → Box64 wrapped libpulse 拦截
    → 翻译参数 (x86_64 → ARM64 ABI)
    → 调用系统 aarch64 libpulse.so 的 pa_simple_new()
    → 翻译返回值 (ARM64 → x86_64 ABI)
```

**WoW64 (32 位支持)：**
Proton 11 的 WoW64 实现允许 64 位 Wine 进程加载和运行 32 位 DLL。巧可甜恋 (ac_chinese.exe) 是 32 位程序，通过 WoW64 在 64 位 Wine 进程中运行：

```
64 位 wine 进程
    ├── 加载 64 位 DLL (kernel32, user32, ...)
    └── WoW64 层
         └── 加载 32 位 DLL (游戏本体, BGI 引擎, d3d9, ...)
```

**Box64 性能优化：**
```bash
BOX64_DYNAREC_BIGBLOCK=3       # 最大化翻译代码块，减少跳转开销
BOX64_DYNAREC_STRONGMEM=2      # x86 内存序保证 (Wine 需要)
BOX64_DYNAREC_CALLRET=1        # 优化 CALL/RET 指令对
BOX64_DYNAREC_FORWARD=1024     # 更大的前向跳转间隙
BOX64_DYNACACHE=1              # 缓存翻译结果到磁盘，下次跳过重编译
```

### 第5层：显示输出 (X11 + TigerVNC)

Android 没有原生 X11 显示服务器。TigerVNC 在 Termux 中运行一个 X11 服务器，VNC 客户端（手机上的 VNC Viewer App）连接后显示画面：

```
Wine 渲染像素 → X11 窗口 → TigerVNC Xserver → VNC 协议 → 手机 VNC App 显示
```

### 第6层：音频输出 (PulseAudio + AAudio)

```
游戏音频 (DirectSound/XAudio2)
    → winepulse.drv (Wine 内置 PulseAudio 驱动)
    → Box64 wrapped libpulse (x86_64 → aarch64 翻译)
    → 通过 TCP 连接 PulseAudio (127.0.0.1:4713)
    → PulseAudio module-aaudio-sink
    → Android AAudio API
    → 手机扬声器/耳机输出
```

**为什么用 TCP 而不是 Unix Socket？**
Wine/Box64 通过 Unix socket 连接 PulseAudio 时会产生死锁（PA 在处理连接时阻塞，Wine 等待 PA 响应也阻塞）。改用 TCP 连接后问题消失。

**为什么禁用 module-suspend-on-idle？**
PulseAudio 默认在空闲时挂起音频设备以省电。但 AAudio sink 挂起后无法恢复（Android AAudio 的限制），导致 PA 卡死。

**为什么禁用 winealsa？**
winealsa.drv 尝试加载 ALSA 配置文件，但路径指向 winlator 的 imagefs（`/data/data/com.winlator/files/...`），Termux 中不存在。通过 `WINEDLLOVERRIDES="winealsa.drv="` 禁用。

---

## 项目结构

```
~/proton11/
├── proton-11/                    # Proton 11.0-1 x86_64 Bionic
│   └── lib/wine/
│       ├── x86_64-unix/wine      # Wine 主二进制 (x86_64 ELF)
│       ├── x86_64-unix/winepulse.so  # PulseAudio 驱动 (x86_64)
│       ├── x86_64-unix/winealsa.so   # ALSA 驱动 (x86_64, 已禁用)
│       ├── x86_64-windows/winepulse.drv
│       ├── i386-windows/winepulse.drv # 32 位音频驱动 (WoW64)
│       └── i386-windows/wined3d.dll   # 32 位 D3D9 翻译
├── p11prefix/                    # Proton 11 wineprefix
│   ├── drive_c → drive_d         # 符号链接 (关键!)
│   └── drive_d/windows/
│       ├── system32/             # 808+ DLLs + DXVK (d3d11.dll, dxgi.dll)
│       ├── Fonts/                # simsun.ttc, YuGothR.ttc, msyi.ttf, malgun.ttf
│       └── mono/mono-2.0/        # Wine Mono 11.1.0 (.NET 运行时)
├── box64/                        # Box64 v0.4.3 bionic (源码+编译)
│   └── build/box64               # Box64 可执行文件
├── xaw64/                        # xaw64 框架 (已修改支持 Proton 11)
│   └── xaw64                     # 主脚本 (含 Proton 11 兼容补丁)
├── xaw64_box64/                  # Box64 配置
│   ├── bin/box64                 # v0.4.3 (v0.3.5 备份为 box64-0.3.5-bak)
│   └── etc/box64.box64rc         # Box64 运行时配置
├── xaw64_wine/                   # Wine 版本管理
│   ├── .wine-version             # 内容: proton-11
│   ├── 10.7-stable → proton-11   # 兼容 xaw64 硬编码版本号
│   └── proton-11 → ~/proton11/proton-11  # 符号链接
├── xaw64_drivers/                # xaw64 驱动
├── dxvk-2.5.3/                   # DXVK 2.5.3
│   └── x64/d3d11.dll, dxgi.dll  # DX11 → Vulkan 翻译 DLL
├── wine-mono-11.1.0-x86.msi      # Wine Mono 安装包
├── .cache/                       # 缓存目录
│   ├── dynacache/                # Box64 代码翻译缓存 (~2.5MB)
│   └── shaders/                  # 着色器缓存 (~2.8MB)
├── proton11-run                  # 通用启动器 (自动检测架构/DX版本)
├── run-proton11.sh               # 星空列车与白的旅行专用脚本
├── fast-launch.sh                # 巧可甜恋专用脚本
├── start-audio.sh                # PulseAudio 管理脚本
└── README.md                      # 本文档
```

---

## 依赖项目

| 项目 | 版本 | 作用 | 地址 |
|------|------|------|------|
| **Termux** | latest | Android 终端模拟器 + Linux 环境 | https://github.com/termux/termux-app |
| **Box64** | v0.4.3 bionic | x86_64 → ARM64 动态重编译器 | https://github.com/ptitSeb/box64 |
| **Proton** | 11.0-1 | Windows 兼容层 (Valve Wine 增强版) | https://github.com/ValveSoftware/Proton |
| **xaw64-wine** | - | Termux Wine 一键部署框架 | https://github.com/ar37-rs/xaw64-wine |
| **DXVK** | 2.5.3 | DirectX 9/10/11 → Vulkan 翻译层 | https://github.com/doitsujin/dxvk |
| **Mesa** | Termux pkg | lavapipe (软件Vulkan) + llvmpipe (软件OpenGL) | https://gitlab.freedesktop.org/mesa/mesa |
| **PulseAudio** | 17.0 | 音频服务器 | https://www.freedesktop.org/wiki/Software/PulseAudio/ |
| **TigerVNC** | Termux pkg | X11 VNC 服务器 | https://github.com/TigerVNC/tigervnc |
| **Wine Mono** | 11.1.0 | .NET 兼容实现 | https://wiki.winehq.org/Mono |

---

## 快速开始

### 1. 安装 Termux 环境

```bash
pkg install x11-repo
pkg install tigervnc mesa vulkan-loader-android pulseaudio xfce4
```

### 2. 下载 Release 资源

从 [GitHub Release v1.0](https://github.com/nlsidf/proton11-termux/releases/tag/v1.0) 下载所有 `.tar.gz` 文件，解压到 `~/proton11/`：

```bash
mkdir -p ~/proton11
cd ~/proton11
tar xzf proton-11.tar.gz
tar xzf p11prefix.tar.gz
tar xzf box64.tar.gz
tar xzf xaw64.tar.gz
tar xzf xaw64_box64.tar.gz
tar xzf dxvk-2.5.3.tar.gz
gunzip wine-mono-11.1.0-x86.msi.gz
```

### 3. 修复符号链接

**关键！** 打包时符号链接会丢失，必须手动重建。缺少任何一个都会导致运行失败：

```bash
# ① xaw64_wine: Proton 目录符号链接
cd ~/proton11/xaw64_wine
rm -f proton-11
ln -s ~/proton11/proton-11 proton-11

# ② xaw64_wine: 版本兼容符号链接
# xaw64 框架硬编码了 "10.7-stable" 版本号，必须创建此链接才能找到 Proton 11
rm -f 10.7-stable
ln -s proton-11 10.7-stable

# ③ xaw64_wine: 版本标识文件
# xaw64 通过此文件判断当前 Wine 版本
echo "proton-11" > .wine-version

# ④ p11prefix: drive_c → drive_d 符号链接 (最关键!)
# Proton 使用 drive_d 作为 Windows 系统目录，但 Wine 内部通过 C:\ 路径操作映射到 drive_c
# 没有此链接，wineboot 初始化时所有 DLL 安装都会失败 (error=3)
cd ~/proton11/p11prefix
rm -f drive_c
ln -s drive_d drive_c
```

**验证：**
```bash
ls -la ~/proton11/xaw64_wine/    # 应看到 proton-11 → 和 10.7-stable → proton-11
cat ~/proton11/xaw64_wine/.wine-version  # 应输出 proton-11
ls -la ~/proton11/p11prefix/drive_c      # 应显示 drive_c → drive_d
```

### 4. 配置环境变量

将以下内容添加到 `~/.bashrc`，确保 PulseAudio 客户端工具（pactl 等）能正确连接：

```bash
# PulseAudio 环境变量
export PULSE_SERVER=tcp:127.0.0.1:4713
export PULSE_RUNTIME_PATH=/data/data/com.termux/files/usr/tmp
export PULSE_STATE_PATH=/data/data/com.termux/files/home/.config/pulse
export PULSE_CONFIG_PATH=/data/data/com.termux/files/home/.config/pulse
```

### 5. 配置音频

```bash
mkdir -p ~/.config/pulse
```

创建 `~/.config/pulse/default.pa`：
```
#!/usr/bin/pulseaudio -nF
.ifexists module-aaudio-sink.so
load-module module-aaudio-sink sink_name=android_output
.else
load-module module-null-sink sink_name=dummy_output
.nofail
.endif
load-module module-device-restore
load-module module-stream-restore
load-module module-card-restore
load-module module-augment-properties
load-module module-native-protocol-unix auth-anonymous=1 socket=/data/data/com.termux/files/home/.config/pulse/pulseaudio.sock
load-module module-native-protocol-tcp auth-anonymous=1 listen=127.0.0.1 port=4713
load-module module-always-sink
```

创建 `~/.config/pulse/client.conf`：
```
autospawn = no
```

### 6. 配置 VNC + 桌面环境

安装桌面环境（如步骤 1 未安装）：
```bash
pkg install xfce4
```

首次启动 VNC 会提示设置查看密码：
```bash
vncserver :1
```

写入 `~/.vnc/xstartup`（完整内容）：
```bash
#!/data/data/com.termux/files/usr/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11
$HOME/proton11/start-audio.sh
startxfce4 &
```

```bash
chmod +x ~/.vnc/xstartup
```

### 7. 首次初始化 Wineprefix

**首次运行游戏前，必须先初始化 Wineprefix。** 启动器 `proton11-run` 会自动完成此步骤，也可以手动执行：

```bash
# 手动初始化（如需要）
export WINEPREFIX=$HOME/proton11/p11prefix
export DISPLAY=:1
~/proton11/box64/build/box64 ~/proton11/xaw64_wine/proton-11/bin/wine wineboot --init
```

初始化过程约 1-3 分钟，会完成以下操作：
- 创建 Windows 虚拟文件系统（system32、Fonts 等目录）
- 安装 DXVK (d3d11.dll, dxgi.dll) 到 system32
- 写入 DllOverrides 注册表（d3d11/dxgi = native,builtin）
- 安装 Wine Mono (.NET 运行时)

**注意：** 首次启动游戏时 `proton11-run` 会自动检测并执行初始化，无需手动操作。

### 8. 启动游戏

```bash
# 启动 VNC（如未启动）
vncserver :1

# 通用启动器 (自动检测架构 + 首次自动初始化)
~/proton11/proton11-run /path/to/game.exe

# 查看环境状态
~/proton11/proton11-run --status

# 音频管理
~/proton11/start-audio.sh          # 启动
~/proton11/start-audio.sh status   # 状态
~/proton11/start-audio.sh stop     # 停止
~/proton11/start-audio.sh restart  # 重启
```

**环境变量说明：** 启动脚本会自动设置以下关键变量，无需手动配置：
- `DISPLAY=:1` — VNC 显示号
- `WINEPREFIX` — Wineprefix 路径
- `VK_ICD_FILENAMES` — lavapipe ICD 路径（DXVK + Vulkan 软件渲染必需）
- `PULSE_SERVER=tcp:127.0.0.1:4713` — PulseAudio TCP 连接（避免 Unix socket 死锁）
- `WINEDLLOVERRIDES="winepulse.drv=b;winealsa.drv="` — 强制 winepulse，禁用 winealsa
- `BOX64_DYNACACHE=1` — 缓存翻译代码，加速后续启动

---

## 已测试游戏

| 游戏 | 引擎 | 架构 | DirectX | 渲染路径 | 状态 |
|------|------|------|---------|---------|------|
| 星空列车与白的旅行 | Unity 2020.3 | x86_64 | DX11 | DXVK → lavapipe | 正常 (画面+音频) |
| 巧可甜恋 | BGI | x86 (32-bit) | DX9 | wined3d → llvmpipe | 正常 (画面+音频) |

---

## 排错指南

### wineboot 反复运行 / 卡住

| 原因 | 症状 | 解决 |
|------|------|------|
| 缺少 drive_c 符号链接 | `create_dest_file failed error=3` | 创建 `drive_c → drive_d` 符号链接 |
| 使用了 Wine 10.7 创建的前缀 | wineboot 每次都触发 | 用 Proton 11 创建独立前缀 |
| 时间戳过期 | wineboot 反复运行 | `date +%s > .update-timestamp` |
| box64 版本过低 | wineboot 长时间卡住 | 升级到 v0.4.3 bionic |

### 游戏黑屏 / 无渲染

| 原因 | 症状 | 解决 |
|------|------|------|
| 未设置 VK_ICD_FILENAMES | 无 DXVK/Vulkan 输出 | 设置 lavapipe ICD 路径 |
| DllOverrides 为 builtin | DXVK 不加载 | 改为 `native,builtin` |
| 使用 virgl + vulkan-null | 黑屏 | 改用 DXVK + lavapipe |

### 中文字体显示方框 □

| 原因 | 解决 |
|------|------|
| 缺少中文字体 | 复制 simsun.ttc、YuGothR.ttc 等到 Fonts 目录 |
| FontSubstitutes 未设置 | regedit 添加字体替代注册表项 |

### PulseAudio 无声音 / 卡死

| 原因 | 症状 | 解决 |
|------|------|------|
| module-suspend-on-idle | PA 运行后不久卡死 | 从 default.pa 移除该模块 |
| Unix socket 死锁 | 游戏启动后 PA 卡死 | 改用 TCP 连接 (PULSE_SERVER=tcp:127.0.0.1:4713) |
| winealsa 代替 winepulse | ALSA conf 找不到 | WINEDLLOVERRIDES="winealsa.drv=" 禁用 |
| socket 路径不匹配 | pactl 连接被拒 | 指定 socket= 路径参数 |
| autospawn 干扰 | kill 后自动重启 | client.conf 设 autospawn=no |

### Mono 安装对话框反复弹出

预装 Wine Mono: `msiexec /i wine-mono-11.1.0-x86.msi /quiet`

---

## 性能说明

- **启动时间**：首次 ~60s（DynaCache + 着色器编译），后续 ~30s（使用缓存）
- **帧率**：2D 游戏流畅；3D 游戏受限于 CPU 软件渲染，复杂场景可能掉帧
- **硬件加速**：不可用。Turnip (Adreno Vulkan 驱动) 需要 Android 15+ Bionic 的 `call_once@LIBC_R` 符号，与当前设备不兼容
- **内存**：建议 4GB+ RAM 设备，Proton 11 + 游戏运行时约占用 1-2GB
