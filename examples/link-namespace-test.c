#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

struct android_namespace_t;
typedef struct android_namespace_t android_namespace_t;

// 尝试更大的 struct (兼容 Android 10/11)
typedef struct {
    uint64_t flags;
    void*   reserved_addr;
    size_t  reserved_size;
    int     relro_fd;
    void*   library_fd;
    int32_t library_fd_offset;
    void*   library_address;  // API 29+
    android_namespace_t* library_namespace;  // API 30+ (offset 56)
    int32_t ns_get_primary_handles_only;
} android_dlextinfo_v2;

#define ANDROID_DLEXT_USE_NAMESPACE 0x200

int main() {
    typedef android_namespace_t* (*get_ns_t)(const char*);
    get_ns_t get_ns = (get_ns_t)dlsym(RTLD_DEFAULT, "__loader_android_get_exported_namespace");
    
    typedef bool (*link_ns_t)(android_namespace_t*, android_namespace_t*, const char*);
    link_ns_t link_ns = (link_ns_t)dlsym(RTLD_DEFAULT, "__loader_android_link_namespaces");
    
    typedef void* (*dlopen_ext_t)(const char*, int, const void*);
    dlopen_ext_t my_dlopen_ext = (dlopen_ext_t)dlsym(RTLD_DEFAULT, "android_dlopen_ext");
    
    android_namespace_t *sphal = get_ns("sphal");
    android_namespace_t *def = get_ns("default");
    
    printf("=== 1. 先链接 namespace ===\n");
    bool linked = link_ns(def, sphal, NULL);
    printf("  link_ns(def → sphal) = %d\n", linked);
    
    printf("\n=== 2. 试试绝对路径 dlopen ===\n");
    const char *paths[] = {
        "/system/vendor/lib64/egl/libEGL_adreno.so",
        "/vendor/lib64/egl/libEGL_adreno.so",
        "/system/vendor/lib64/libEGL_adreno.so",
        "/vendor/lib64/libEGL_adreno.so",
        NULL
    };
    for (int i = 0; paths[i]; i++) {
        void *lib = dlopen(paths[i], RTLD_LAZY | RTLD_LOCAL);
        printf("  dlopen(%s) = %p\n", paths[i], lib);
        if (!lib) printf("    error: %s\n", dlerror());
        else {
            printf("    ✅ SUCCESS!\n");
            dlclose(lib);
            break;
        }
    }
    
    printf("\n=== 3. android_dlopen_ext 大 struct (128字节) ===\n");
    // 用更大的 struct 确保 namespace 字段落在正确位置
    uint8_t big_extinfo[128];
    memset(big_extinfo, 0, 128);
    
    // 设置 flags 字段 (offset 0)
    *(uint64_t*)&big_extinfo[0] = ANDROID_DLEXT_USE_NAMESPACE;
    // 设置 library_namespace 在不同偏移尝试
    for (int offset = 40; offset <= 80; offset += 8) {
        *(android_namespace_t**)&big_extinfo[offset] = sphal;
        void *lib = my_dlopen_ext("libEGL_adreno.so", RTLD_LAZY | RTLD_LOCAL, big_extinfo);
        *(android_namespace_t**)&big_extinfo[offset] = NULL;
        if (lib) {
            printf("  ✅ offset %d: SUCCESS! lib=%p\n", offset, lib);
            void *egl = dlsym(lib, "eglGetProcAddress");
            printf("     eglGetProcAddress=%p\n", egl);
            dlclose(lib);
            break;
        }
    }
    
    printf("\n=== 4. Vulkan 加载器探测 ===\n");
    // 尝试加载 vulkan 看能不能找到 Adreno 驱动
    void *vk = dlopen("libvulkan.so", RTLD_LAZY);
    printf("  libvulkan.so = %p\n", vk);
    if (vk) {
        // 枚举 Vulkan 层和驱动
        typedef void* (*vkEnumerateInstanceExtensionProps)(void*, void*);
        typedef void* (*vkCreateInstance)(void*, void*, void*);
        void *vkenum = dlsym(vk, "vkEnumerateInstanceExtensionProperties");
        printf("  vkEnumerateInstanceExtensionProperties = %p\n", vkenum);
        dlclose(vk);
    }
    
    return 0;
}
