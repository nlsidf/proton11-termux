# Proton 11 在 Android Termux 上运行 Windows 游戏指南

## 环境信息

| 项目 | 值 |
|------|-----|
| 设备 | Android (Snapdragon 835 / Adreno 540) |
| 系统 | Termux (Bionic libc, aarch64) |
| 显示 | TigerVNC :1 (端口 5901) |
| CPU 模拟 | Box64 v0.4.3 bionic (x86_64 → ARM64) |
| Wine | Proton 11.0-1 x86_64 Bionic |
| 渲染 | DXVK 2.5.3 + lavapipe (Mesa 软件 Vulkan 1.4) |
| 音频 | PulseAudio 17.0 + AAudio (Android 硬件输出) |
| 已测试游戏 | 星空列车与白的旅行 (Unity DX11)、巧可甜恋 (BGI DX9 32-bit) |

---

## 目录结构

```
$HOME/
├── xaw64-all/                          # xaw64 主脚本目录
│   └── xaw64                           # 已修改，支持 Proton 11
├── xaw64_box64/bin/
│   ├── box64                           # 已替换为 v0.4.3 bionic
│   └── box64-0.3.5-bak                 # 原版 v0.3.5 备份
├── xaw64_wine/
│   ├── .wine-version                   # 内容: proton-11
│   ├── 10.7-stable -> proton-11        # 符号链接
│   └── proton-11 -> basement/proton-11 # 符号链接
├── box64_bionic/build/box64            # Box64 v0.4.3 bionic 源码编译
├── .vnc/xstartup                       # VNC 启动脚本 (含 PulseAudio 自启)
├── .config/pulse/
│   ├── default.pa                      # PA 配置 (AAudio + TCP + Unix)
│   └── client.conf                     # autospawn = no
├── basement/
│   ├── proton-11/                      # Proton 11.0-1 x86_64 Bionic
│   │   └── lib/wine/x86_64-unix/wine   # Wine 主二进制
│   ├── p11prefix/                      # Proton 11 专用 wineprefix
│   │   ├── drive_c -> drive_d          # 符号链接 (关键!)
│   │   ├── drive_d/                    # 实际 Windows 目录
│   │   │   └── windows/
│   │   │       ├── system32/           # 808+ DLLs + DXVK
│   │   │       ├── Fonts/              # simsun.ttc, YuGothR.ttc, msyi.ttf, malgun.ttf
│   │   │       ├── mono/mono-2.0/      # Wine Mono 11.1.0
│   │   │       └── Microsoft.NET/      # .NET Framework
│   │   ├── dosdevices/
│   │   │   ├── c: -> ../drive_c
│   │   │   └── z: -> /
│   │   ├── system.reg
│   │   └── user.reg                    # DllOverrides + FontSubstitutes
│   ├── imagefs/usr/lib/                # ARM64 原生渲染库 (libGL, libvulkan)
│   ├── dxvk-2.5.3/x64/                # DXVK 2.5.3 DLLs
│   ├── wine-mono-11.1.0-x86.msi       # Wine Mono 安装包
│   ├── .cache-p11/
│   │   ├── dynacache/                  # Box64 代码缓存 (~2.5MB)
│   │   └── shaders/                    # 着色器缓存 (~2.8MB)
│   ├── run-proton11.sh                 # 星空列车与白的旅行启动脚本
│   ├── fast-launch.sh                  # 巧可甜恋启动脚本
│   ├── start-audio.sh                  # PulseAudio 管理脚本
│   ├── loveai/
│   │   ├── sky-rail-and-white-travel/
│   │   │   └── game.exe               # 星空列车与白的旅行
│   │   └── Amairo Chocolate_wm/
│   │       └── ac_chinese.exe         # 巧可甜恋
```

---

## 渲染管线

```
Unity 游戏 (DirectX 11)            BGI 游戏 (DirectX 9)
    ↓                                    ↓
DXVK 2.5.3 (d3d11/dxgi, native)    wined3d (builtin)
    ↓ 将 D3D11 转换为 Vulkan            ↓ 将 D3D9 转换为 OpenGL
lavapipe (Mesa 软件 Vulkan)         llvmpipe (Mesa 软件 OpenGL)
    ↓                                    ↓
Xlib (X11 显示)                     Xlib (X11 显示)
    ↓                                    ↓
TigerVNC (:1 / 端口 5901)           TigerVNC (:1 / 端口 5901)
```

**DX11 游戏**（星空列车）使用 DXVK + lavapipe；**DX9 游戏**（巧可甜恋）使用 wined3d + llvmpipe。

---

## 音频管线

```
Wine 游戏音频 (DirectSound / XAudio2)
    ↓
winepulse.drv (builtin, WINEDLLOVERRIDES=winepulse.drv=b)
    ↓ Wine PulseAudio 驱动
Box64 wrapped libpulse (x86_64 → aarch64 翻译)
    ↓ 通过 TCP 连接 (127.0.0.1:4713)
PulseAudio 17.0 (module-aaudio-sink)
    ↓ AAudio Android 硬件音频 API
Android 音频输出 (扬声器/耳机)
```

**关键配置：**
- Wine 通过 `PULSE_SERVER=tcp:127.0.0.1:4713` 连接 PulseAudio（TCP 避免 Unix socket 死锁）
- 禁用 winealsa：`WINEDLLOVERRIDES="winepulse.drv=b;winealsa.drv="`
- PulseAudio 不加载 `module-suspend-on-idle`（AAudio sink 挂起后无法恢复，导致 PA 卡死）
- PulseAudio 同时提供 Unix socket 和 TCP 两种连接方式

---

## 启动方式

### 一键启动

```bash
# 星空列车与白的旅行 (Unity DX11)
~/basement/run-proton11.sh

# 巧可甜恋 (BGI DX9 32-bit)
~/basement/fast-launch.sh

# 通过 xaw64 框架
cd ~/xaw64-all && ./xaw64 r ~/basement/loveai/sky-rail-and-white-travel/game.exe
```

### 音频管理

```bash
~/basement/start-audio.sh          # 启动 PulseAudio (VNC 启动时自动运行)
~/basement/start-audio.sh status   # 查看音频状态
~/basement/start-audio.sh stop     # 停止 PulseAudio
~/basement/start-audio.sh restart  # 重启 PulseAudio
```

### VNC 启动

VNC 启动时自动在 `~/.vnc/xstartup` 中运行 `start-audio.sh`，无需手动启动音频。

---

## 关键修改说明

### 1. Box64 升级 (v0.3.5 → v0.4.3)

xaw64 自带的 box64 v0.3.5 无法正常完成 Proton 11 的 wineboot 初始化。v0.4.3 bionic 版本在 ~77 秒内完成。

```bash
mv ~/xaw64_box64/bin/box64 ~/xaw64_box64/bin/box64-0.3.5-bak
cp ~/box64_bionic/build/box64 ~/xaw64_box64/bin/box64
```

### 2. xaw64 脚本 Proton 11 兼容补丁

在 `init_envirs` 之后（约第74行）添加：

```bash
if [ -f $HOME/xaw64_wine/.wine-version ]; then
    _WV=$(cat $HOME/xaw64_wine/.wine-version)
    if [[ "$_WV" == "proton-11" ]]; then
        WINE_VERSION=$_WV
        export WINEPREFIX=$HOME/basement/p11prefix
        export BOX64_LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib:\
$HOME/xaw64_box64/lib:\
$HOME/xaw64_wine/${WINE_VERSION}/lib/wine/x86_64-unix:\
$HOME/xaw64_wine/${WINE_VERSION}/lib/wine/i386-windows:\
$HOME/xaw64_wine/x86_64-windows:\
$HOME/basement/proton-11/lib:\
$HOME/basement/imagefs/usr/lib
        export VK_ICD_FILENAMES=/data/data/com.termux/files/usr/share/vulkan/icd.d/lvp_icd.aarch64.json
    fi
fi
```

**原因：** `WINE_VERSION=10.7-stable` 硬编码，`BOX64_LD_LIBRARY_PATH` 在 `.wine-version` 读取前设置，缺少 Proton 11 和渲染库路径。

### 3. Wineprefix 初始化

Proton 11 与 Wine 10.7 的前缀不兼容，必须用 Proton 11 从零创建：

```bash
export WINEPREFIX=$HOME/basement/p11prefix
box64 wine wineboot --init &
# drive_d 出现后立即创建符号链接!
ln -s drive_d $WINEPREFIX/drive_c
wait
```

**drive_c → drive_d 符号链接是核心关键：**
- Proton 使用 `drive_d` 作为 Windows 目录
- Wine 内部仍通过 `C:\` 路径写入，映射到 `drive_c`
- 没有符号链接 → `drive_c` 不存在 → DLL 全部安装失败 (error=3)

### 4. DXVK 安装

```bash
cp ~/basement/dxvk-2.5.3/x64/d3d11.dll $WINEPREFIX/drive_d/windows/system32/
cp ~/basement/dxvk-2.5.3/x64/dxgi.dll $WINEPREFIX/drive_d/windows/system32/
```

`user.reg` 添加 DllOverrides：

```
[Software\\Wine\\DllOverrides]
"d3d11"="native,builtin"
"dxgi"="native,builtin"
```

### 5. Wine Mono 预安装

```bash
box64 wine msiexec /i "Z:\\data\\data\\com.termux\\files\\home\\basement\\wine-mono-11.1.0-x86.msi" /quiet
```

不预装 Mono 则每次启动弹安装对话框，阻塞游戏。

### 6. 中文字体修复

游戏显示 □ 方框是因为缺少中文字体：

```bash
# 从 imagefs 复制字体
cp ~/basement/imagefs/usr/share/fonts/truetype/ms/simsun.ttc $WINEPREFIX/drive_d/windows/Fonts/
cp ~/basement/imagefs/usr/share/fonts/truetype/ms/YuGothR.ttc $WINEPREFIX/drive_d/windows/Fonts/
cp ~/basement/imagefs/usr/share/fonts/truetype/ms/msyi.ttf $WINEPREFIX/drive_d/windows/Fonts/
cp ~/basement/imagefs/usr/share/fonts/truetype/ms/malgun.ttf $WINEPREFIX/drive_d/windows/Fonts/
```

同时通过 regedit 添加 FontSubstitutes 注册表项（SimSun 替代 MS Gothic 等）。

### 7. 音频配置

**问题：** PulseAudio 在 Termux 上默认无法正常工作，原因有三：
1. `module-suspend-on-idle` 导致 AAudio sink 挂起后无法恢复，PA 卡死
2. `module-native-protocol-unix` 未指定 socket 路径，与 `PULSE_SERVER` 环境变量不匹配
3. Wine 通过 Unix socket 连接 PA 时产生死锁，PA 卡死

**解决方案：**

1. `~/.config/pulse/default.pa`：
   - 加载 `module-aaudio-sink`（Android 硬件音频输出）
   - 加载 `module-native-protocol-tcp`（TCP 端口 4713）
   - 加载 `module-native-protocol-unix`（指定 socket 路径）
   - **不加载** `module-suspend-on-idle`（避免 AAudio 卡死）

2. `~/.config/pulse/client.conf`：`autospawn = no`（防止自动重启干扰手动管理）

3. Wine 环境变量：
   - `PULSE_SERVER=tcp:127.0.0.1:4713`（TCP 连接避免死锁）
   - `WINEDLLOVERRIDES="winepulse.drv=b;winealsa.drv="`（强制 PulseAudio，禁用 ALSA）

4. `~/.vnc/xstartup` 中调用 `start-audio.sh`，VNC 启动时自动运行 PulseAudio

### 8. Box64 性能优化与 DynaCache

```bash
# DynaCache - 缓存翻译代码到磁盘
BOX64_DYNACACHE=1
BOX64_DYNACACHE_FOLDER=~/basement/.cache-p11/dynacache

# DynaRec 优化 (Wine 推荐)
BOX64_DYNAREC_BIGBLOCK=3       # 最大化代码块
BOX64_DYNAREC_STRONGMEM=2      # x86 内存序 + SIMD 屏障
BOX64_DYNAREC_WEAKBARRIER=1    # 减少屏障开销
BOX64_DYNAREC_CALLRET=1        # 优化 CALL/RET 跳转
BOX64_DYNAREC_FORWARD=1024     # 更大前向间隙
BOX64_DYNAREC_FASTNAN=1        # 快速 NaN
BOX64_DYNAREC_FASTROUND=1      # 快速舍入
```

DynaCache 首次运行生成缓存 (~2.5MB)，后续启动可跳过代码重编译，游戏启动时间从 ~60s 降至 ~30s。

### 9. Shader 缓存

```bash
DXVK_STATE_CACHE_PATH=~/basement/.cache-p11/shaders/dxvk/state-cache
MESA_SHADER_CACHE_DIR=~/basement/.cache-p11/shaders/mesa
MESA_SHADER_CACHE_MAX_SIZE=512M
```

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

- 预装 Wine Mono: `msiexec /i wine-mono-11.1.0-x86.msi /quiet`
- 或禁用: `export WINEDLLOVERRIDES=mscoree=d` (可能影响游戏运行)

### BOX64_LD_LIBRARY_PATH 缺少渲染库

症状：Wine 启动后找不到 libGL.so 或 libvulkan.so

确保路径包含：
- `$HOME/basement/proton-11/lib` — Proton 原生库
- `$HOME/basement/imagefs/usr/lib` — ARM64 渲染库 (libGL, libvulkan)

---

## 从零搭建完整流程

```bash
# 1. 确保 TigerVNC 运行在 :1
export DISPLAY=:1

# 2. 确认 Proton 11 和 box64 v0.4.3 就位
ls ~/basement/proton-11/lib/wine/x86_64-unix/wine
ls ~/box64_bionic/build/box64

# 3. 设置 xaw64 符号链接
echo "proton-11" > ~/xaw64_wine/.wine-version
ln -sf proton-11 ~/xaw64_wine/10.7-stable
ln -sf ~/basement/proton-11 ~/xaw64_wine/proton-11

# 4. 替换 box64
mv ~/xaw64_box64/bin/box64 ~/xaw64_box64/bin/box64-0.3.5-bak
cp ~/box64_bionic/build/box64 ~/xaw64_box64/bin/box64

# 5. 启动音频
~/basement/start-audio.sh

# 6. 运行启动脚本 (自动完成初始化)
~/basement/run-proton11.sh
```

---

## 文件清单

| 文件 | 用途 |
|------|------|
| `~/basement/run-proton11.sh` | 星空列车与白的旅行启动脚本（自动初始化） |
| `~/basement/fast-launch.sh` | 巧可甜恋启动脚本 |
| `~/basement/start-audio.sh` | PulseAudio 管理脚本（启动/停止/状态/重启） |
| `~/.vnc/xstartup` | VNC 启动脚本（自动启动 PulseAudio） |
| `~/.config/pulse/default.pa` | PulseAudio 配置（AAudio + TCP） |
| `~/.config/pulse/client.conf` | PulseAudio 客户端配置（autospawn=no） |
| `~/.bashrc` | 环境变量（PULSE_SERVER 等） |
| `~/xaw64-all/xaw64` | xaw64 主脚本（已添加 Proton 11 兼容补丁） |
| `~/basement/p11prefix/` | Proton 11 专用 wineprefix |
| `~/basement/proton-11/` | Proton 11.0-1 x86_64 Bionic |
| `~/box64_bionic/build/box64` | Box64 v0.4.3 bionic |
| `~/basement/dxvk-2.5.3/` | DXVK 2.5.3 |
| `~/basement/wine-mono-11.1.0-x86.msi` | Wine Mono 安装包 |
| `~/basement/imagefs/usr/lib/` | ARM64 原生渲染库 |
