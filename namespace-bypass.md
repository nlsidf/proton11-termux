# Android Linker Namespace Bypass — Termux 访问系统 GPU 库

> 发现日期: 2026-06-05
> 设备: Snapdragon 835 (Adreno 540), Android 10 (API 29)
> 环境: Termux (untrusted_app SELinux context) + proot-distro

---

## 目录

1. [背景](#背景)
2. [namespace 限制的原理](#namespace-限制的原理)
3. [解除限制的方法](#解除限制的方法)
4. [核心代码](#核心代码)
5. [验证结果](#验证结果)
6. [应用场景](#应用场景)
7. [已知限制](#已知限制)
8. [参考](#参考)

---

## 背景

Termux 运行在 Android 的 `untrusted_app` SELinux 上下文中，Android 的 linker 为应用分配了隔离的库加载命名空间（linker namespace）。Termux 的默认 namespace 只能加载 `/data/data/com.termux/files/usr/lib/` 下的库，无法访问：

- `/system/vendor/lib64/egl/libEGL_adreno.so` — Adreno GPU EGL 驱动
- `/system/vendor/lib64/egl/libGLESv2_adreno.so` — Adreno GLES 驱动
- `/system/vendor/lib64/libvulkan.so` — 系统 Vulkan 驱动
- `/vendor/lib64/` 下的其他硬件驱动库

直接 `dlopen` 这些库会得到：

```
dlopen failed: library ".../libEGL_adreno.so" 
  is not accessible for the namespace "(default)"
```

## namespace 限制的原理

Android 从 7.0 (API 24) 开始引入 linker namespace 机制，每个进程（或应用）被分配到一个或多个 namespace。namespace 定义了该进程可以加载的库的搜索路径和白名单。

关键组件：
- **linker64** — Android 的动态链接器 (`/apex/com.android.runtime/bin/linker64`)
- **namespace** — 库搜索域的隔离单元
- **sphal namespace** — 系统 HAL 库的命名空间（包含 GPU、相机、显示等驱动）
- **default namespace** — 普通应用的命名空间

Termux 进程在 `(default)` namespace 下运行，无权访问 `sphal` namespace 中的库。

## 解除限制的方法

### 发现的关键函数

Android 的 linker 导出了几个未公开但可访问的函数：

| 函数 | 作用 | 发现方式 |
|------|------|---------|
| `android_dlopen_ext` | 增强版 dlopen，支持 flags 控制 | `dlsym(RTLD_DEFAULT, "android_dlopen_ext")` |
| `__loader_android_dlopen_ext` | linker 内部版 dlopen_ext | `dlsym(RTLD_DEFAULT, "__loader_android_dlopen_ext")` |
| `__loader_android_get_exported_namespace` | 获取指定 namespace 指针 | `dlsym(RTLD_DEFAULT, "__loader_android_get_exported_namespace")` |
| `__loader_android_link_namespaces` | 链接两个 namespace | `dlsym(RTLD_DEFAULT, "__loader_android_link_namespaces")` |
| `__loader_android_create_namespace` | 创建新 namespace | `dlsym(RTLD_DEFAULT, "__loader_android_create_namespace")` |

这些函数通过 `RTLD_DEFAULT` 即可获取（从 linker64 中导出），无需 root 权限。

### 关键 Flag: ANDROID_DLEXT_USE_NAMESPACE

`android_dlopen_ext` 接受一个 `android_dlextinfo` 结构体：

```c
struct android_dlextinfo {
    uint64_t flags;             // offset 0
    void*   reserved_addr;      // offset 8
    size_t  reserved_size;      // offset 16
    int     relro_fd;           // offset 24
    // padding 4 bytes           // offset 28
    void*   library_fd;         // offset 32
    android_namespace_t* library_namespace;  // offset 40 ← 关键！
    void*   library_address;    // offset 48
    int32_t ns_get_primary_handles_only; // offset 56
};
```

- `ANDROID_DLEXT_USE_NAMESPACE = 0x200`
- 在 Android 10 上，`library_namespace` 字段位于 **offset 40**（非 Android 11 文档中的 offset 56）
- 设置 flags 后，将 `sphal` namespace 指针填入 offset 40，即可从 sphal 加载系统库

### 完整的工作流程

```
1. dlsym(RTLD_DEFAULT, "android_dlopen_ext") → 获取 dlopen_ext 函数指针
2. dlsym(RTLD_DEFAULT, "__loader_android_get_exported_namespace")
   → 获取 get_namespace 函数指针
3. get_namespace("sphal") → 获取 sphal namespace 指针
4. 构造 android_dlextinfo:
   - flags = ANDROID_DLEXT_USE_NAMESPACE
   - library_namespace = sphal (写入 offset 40)
5. dlopen_ext("libEGL_adreno.so", RTLD_LAZY, &extinfo)
   → 从系统 HAL namespace 加载 Adreno EGL 库 ✅
```

## 核心代码

### 加载系统库的通用函数

```c
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <stdint.h>

struct android_namespace_t;
typedef struct android_namespace_t android_namespace_t;

#define ANDROID_DLEXT_USE_NAMESPACE 0x200

// android_dlextinfo struct (Android 10 compatible, namespace at offset 40)
typedef struct {
    uint64_t flags;
    void*   reserved_addr;
    size_t  reserved_size;
    int     relro_fd;
    void*   library_fd;
    int32_t library_fd_offset;
    android_namespace_t* library_namespace;  // offset 40
    void*   library_address;
    int32_t ns_get_primary_handles_only;
} android_dlextinfo;

typedef void* (*dlopen_ext_t)(const char*, int, const void*);
typedef android_namespace_t* (*get_ns_t)(const char*);

static dlopen_ext_t dlopen_ext = NULL;
static get_ns_t get_ns = NULL;
static android_namespace_t *sphal_ns = NULL;

// 初始化函数指针
static void init_ns_access() {
    if (dlopen_ext) return;
    dlopen_ext = (dlopen_ext_t)dlsym(RTLD_DEFAULT, "android_dlopen_ext");
    get_ns = (get_ns_t)dlsym(RTLD_DEFAULT, "__loader_android_get_exported_namespace");
    if (get_ns) sphal_ns = get_ns("sphal");
}

// 从 sphal namespace 加载系统库
void* load_system_lib(const char* name) {
    init_ns_access();
    if (!dlopen_ext || !sphal_ns) return NULL;
    
    android_dlextinfo extinfo;
    memset(&extinfo, 0, sizeof(extinfo));
    extinfo.flags = ANDROID_DLEXT_USE_NAMESPACE;
    extinfo.library_namespace = sphal_ns;
    
    return dlopen_ext(name, RTLD_LAZY | RTLD_LOCAL, &extinfo);
}
```

### 备用方案：Byte Buffer 方式（确保 offset 正确）

```c
uint8_t extinfo[128];
memset(extinfo, 0, 128);
*(uint64_t*)&extinfo[0] = ANDROID_DLEXT_USE_NAMESPACE;
*(android_namespace_t**)&extinfo[40] = sphal_ns;

void *egl = dlopen_ext("libEGL_adreno.so", RTLD_LAZY | RTLD_LOCAL, extinfo);
```

### EGL 初始化和 GPU 验证完整代码

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <stdint.h>

// ... (上述 namespace 初始化代码) ...

int main() {
    // 1. 加载 Adreno EGL
    void *egl = load_system_lib("libEGL_adreno.so");
    if (!egl) { printf("Failed to load Adreno EGL\n"); return 1; }
    
    // 2. 获取 EGL 函数
    void* (*eglGetDisp)(void*) = dlsym(egl, "eglGetDisplay");
    int (*eglInit)(void*,void*,void*) = dlsym(egl, "eglInitialize");
    int (*eglChooseCfg)(void*,const int*,void*,int,int*) = dlsym(egl, "eglChooseConfig");
    void* (*eglCreateCtx)(void*,void*,void*,const int*) = dlsym(egl, "eglCreateContext");
    void* (*eglCreatePbuf)(void*,void*,const int*) = dlsym(egl, "eglCreatePbufferSurface");
    int (*eglMakeCur)(void*,void*,void*,void*) = dlsym(egl, "eglMakeCurrent");
    const char* (*eglQueryStr)(void*,int) = dlsym(egl, "eglQueryString");
    void* (*eglGetProc)(const char*) = dlsym(egl, "eglGetProcAddress");
    
    // 3. 获取 GLES 函数（通过 eglGetProcAddress）
    void (*glClear)(unsigned int) = (void (*)(unsigned int))eglGetProc("glClear");
    void (*glClearColor)(float,float,float,float) = 
        (void (*)(float,float,float,float))eglGetProc("glClearColor");
    void (*glViewport)(int,int,int,int) = (void (*)(int,int,int,int))eglGetProc("glViewport");
    
    // 4. 初始化 EGL
    void *dpy = eglGetDisp(0);
    int major=0, minor=0;
    eglInit(dpy, &major, &minor);
    printf("EGL %d.%d Vendor: %s\n", major, minor, eglQueryStr(dpy, 0x3053));
    
    // 5. 选择配置并创建上下文
    int attrs[] = {0x3024,8,0x3023,8,0x3022,8,0x3021,8,0x3040,4,0x3038,0};
    void *config; int n=0;
    eglChooseCfg(dpy, attrs, &config, 1, &n);
    
    int ctx_attrs[] = {0x3098,3,0x3038,0};  // GLES 3.0
    void *ctx = eglCreateCtx(dpy, config, NULL, ctx_attrs);
    int pb_attrs[] = {0x3057,256,0x3056,256,0x3038,0};
    void *surf = eglCreatePbuf(dpy, config, pb_attrs);
    eglMakeCur(dpy, surf, surf, ctx);
    
    // 6. 渲染测试
    glViewport(0, 0, 256, 256);
    glClearColor(0.2f, 0.4f, 0.8f, 1.0f);
    glClear(0x4000);  // GL_COLOR_BUFFER_BIT
    printf("Adreno GPU rendering: OK\n");
    
    // 7. 读取像素并保存
    void (*glReadPixels)(int,int,int,int,unsigned int,unsigned int,void*) =
        (void (*)(int,int,int,int,unsigned int,unsigned int,void*))eglGetProc("glReadPixels");
    
    uint8_t pixels[256*256*4];
    glReadPixels(0, 0, 256, 256, 0x1908, 0x1401, pixels);
    // 保存为 PPM 文件...
    
    return 0;
}
```

### LD_PRELOAD 桥接库（透明重定向 dlopen）

```c
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
#include <stdint.h>

// ... namespace 初始化代码 ...

void* dlopen(const char* filename, int flags) {
    static void* (*real_dlopen)(const char*, int) = NULL;
    if (!real_dlopen) 
        real_dlopen = (void* (*)(const char*, int))dlsym(RTLD_NEXT, "dlopen");
    
    if (filename) {
        if (strstr(filename, "libEGL"))
            return load_system_lib("libEGL_adreno.so");
        if (strstr(filename, "libGLESv2"))
            return load_system_lib("libGLESv2_adreno.so");
        if (strstr(filename, "libvulkan"))
            return load_system_lib("libvulkan.so");
    }
    return real_dlopen(filename, flags);
}
```

编译: `gcc -shared -fPIC -o egl_bridge.so egl_bridge.c -ldl`

使用: `LD_PRELOAD=./egl_bridge.so 任何程序`

## 验证结果

### 环境信息

| 项目 | 值 |
|------|-----|
| 设备 | OnePlus 5 / 小米 6 (Snapdragon 835) |
| GPU | Adreno 540 |
| Android | 10 (API 29) |
| Linker | `/apex/com.android.runtime/bin/linker64` |
| EGL 版本 | 1.5 |
| EGL 厂商 | Qualcomm Inc. |

### 加载成功

```
libEGL_adreno.so → ✅ (0xac63b57f527d14b)
  eglGetProcAddress → 0x7a4e35eed4
  eglGetDisplay     → 0x7a4e35e2dc
  eglInitialize     → 0x7a4e35e3c8
```

### EGL 1.5 初始化

```
eglInitialize = 1 (1.5)
EGL_VENDOR  = Qualcomm Inc.
EGL_VERSION = 1.5
```

### GPU 渲染

```
glClearColor = 0x7f779cc850 (via eglGetProcAddress)
glClear      = 0x7f779cc800 (via eglGetProcAddress)
Context OK → glClearColor + glClear → GPU rendering: OK ✅
```

### 芯片识别

```
Warning: Unsupported ChipID value for QGPU features (0x5040001), using a5x as default.
```

`0x5040001` = Adreno 540 (a5xx 架构)。驱动识别了芯片但某些 QGPU 特性未启用（不影响基础渲染）。

## 应用场景

### 1. Virgl GPU 服务器（替代 virgl_test_server_android）

现有的 `virgl_test_server_android` 崩溃的原因是 protocol 版本不匹配（Mesa 26.0.6 的 virpipe 客户端 vs 旧版 virglrenderer 服务器）。通过 namespace bypass 可以编写一个自定义的 virgl 服务器：

```
                  ┌─────────────────────────┐
  virpipe(Mesa)──→│  自定义 Virgl Server     │──→ Adreno EGL → GPU
  (Unix socket)   │  (C/Rust, ~1500行)      │
                  │  + namespace bypass      │
                  │  + X11 SHM 输出          │
                  └─────────────────────────┘
```

### 2. LD_PRELOAD libGL 替换

劫持 Mesa 的 libGL 调用，透明转发到 Adreno GPU：

```
  wined3d/OpenGL 应用
       ↓
  libGL.so (LD_PRELOAD 桥接)
       ↓
  Adreno EGL + GLES → 硬件渲染
```

### 3. 视频硬件解码 (MediaCodec)

类似的 namespace bypass 可用于访问 Android 的硬件视频解码器，配合 GStreamer 的 `ahcs` 元素：

```c
void *medialib = load_system_lib("libmediandk.so");
// → 获取 MediaCodec API → 硬件解码 H.264/H.265
```

### 4. Vulkan 直接访问

加载系统 `libvulkan.so` 后，Vulkan loader 会自动发现并加载 Adreno Vulkan 驱动（如果存在）：

```c
void *vk = load_system_lib("libvulkan.so");
// vkCreateInstance → 枚举物理设备 → Adreno Vulkan
```

## 已知限制

### 1. EGL 表面仅支持 Offscreen

Adreno 的 EGL 驱动是 Android 原生的，不支持 X11 窗口绑定。只能创建：
- `EGL_PBUFFER_BIT` — 离屏像素缓冲区 ✅ (已验证)
- `EGL_PIXMAP_BIT` — 像素图表面（可能需要 Android Gralloc）
- `EGL_WINDOW_BIT` — Android ANativeWindow（需 Android 窗口系统）

X11 窗口绑定 (`EGL_X11_BIT`) 需要 Mesa 的 EGL 实现，Adreno 驱动不支持。

### 2. namespace offset 可能因 Android 版本而异

| Android 版本 | API Level | namespace 字段 offset |
|-------------|-----------|----------------------|
| 10 | 29 | 40 (已验证) |
| 11 | 30 | 56 (推测) |
| 12+ | 31+ | 56+ (推测) |

如果要在不同版本上工作，需要使用 byte buffer 方式轮询不同 offset。

### 3. SELinux 审计日志

每次访问系统库会在 logcat 产生审计日志，但 `granted` 类型不会阻止操作：

```
avc: granted { execute } for name="libEGL_adreno.so" ...
```

### 4. 部分芯片 ID 特性缺失

```
Unsupported ChipID value (0x5040001), using a5x as default
```

Adreno 540 使用默认的 a5x 配置，某些特定优化可能未启用。

## 相关文件

| 文件 | 位置 | 说明 |
|------|------|------|
| `namespace-bypass.md` | `~/proton11/` | 本文档 |
| `gpu_test3.c` | `~/gpu_test3.c` | 验证 GPU 渲染的完整测试 |
| `egl_bridge.c` | `~/egl_bridge.c` | LD_PRELOAD 桥接库源码 |
| `egl_bridge.so` | `~/egl_bridge.so` | 已编译的桥接库 |
| `check_ns.c` | `~/check_ns.c` | namespace 函数探测 |
| `link_ns2.c` | `~/link_ns2.c` | namespace 链接测试 |

## 参考

- Android linker 源码: https://android.googlesource.com/platform/bionic/+/master/linker/
- linker namespace 设计文档: https://source.android.com/docs/core/architecture/vndk/linker-namespace
- `android_dlopen_ext` NDK 文档: https://developer.android.com/ndk/reference/group/dlfcn
- Termux 硬件加速讨论: https://github.com/termux/termux-packages/issues/23042
- VirGL 项目: https://virgil3d.github.io/
- Adreno Turnip 驱动: https://docs.mesa3d.org/drivers/freedreno.html
