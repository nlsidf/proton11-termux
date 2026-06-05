#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdbool.h>

struct android_namespace_t;
typedef struct android_namespace_t android_namespace_t;

#define ANDROID_DLEXT_USE_NAMESPACE 0x200

typedef void* (*dlopen_ext_t)(const char*, int, const void*);
typedef android_namespace_t* (*get_ns_t)(const char*);

static dlopen_ext_t real_dlopen_ext = NULL;
static get_ns_t real_get_ns = NULL;
static android_namespace_t *sphal_ns = NULL;
static int initialized = 0;

static void init() {
    if (initialized) return;
    initialized = 1;
    real_dlopen_ext = (dlopen_ext_t)dlsym(RTLD_DEFAULT, "android_dlopen_ext");
    real_get_ns = (get_ns_t)dlsym(RTLD_DEFAULT, "__loader_android_get_exported_namespace");
    if (real_get_ns) sphal_ns = real_get_ns("sphal");
}

// 通过 namespace 加载系统库
static void* load_system_lib(const char* name) {
    init();
    if (!real_dlopen_ext || !sphal_ns) return NULL;
    
    uint8_t extinfo[128];
    memset(extinfo, 0, 128);
    *(uint64_t*)&extinfo[0] = ANDROID_DLEXT_USE_NAMESPACE;
    *(android_namespace_t**)&extinfo[40] = sphal_ns;
    
    return real_dlopen_ext(name, RTLD_LAZY | RTLD_LOCAL, extinfo);
}

// 缓存已加载的系统库
#define MAX_LIBS 16
static struct { const char* name; void* handle; int tried; } sys_libs[MAX_LIBS];
static int num_sys_libs = 0;

static void* get_system_lib(const char* name) {
    for (int i = 0; i < num_sys_libs; i++) {
        if (strcmp(sys_libs[i].name, name) == 0) return sys_libs[i].handle;
    }
    if (num_sys_libs < MAX_LIBS) {
        sys_libs[num_sys_libs].name = strdup(name);
        sys_libs[num_sys_libs].handle = load_system_lib(name);
        sys_libs[num_sys_libs].tried = 1;
        return sys_libs[num_sys_libs++].handle;
    }
    return NULL;
}

// 拦截 dlopen: 把 libEGL/libGLES/libvulkan 重定向到系统库
void* dlopen(const char* filename, int flags) {
    static void* (*real_dlopen)(const char*, int) = NULL;
    if (!real_dlopen) real_dlopen = (void* (*)(const char*, int))dlsym(RTLD_NEXT, "dlopen");
    
    if (filename) {
        // 检查是不是 EGL/GLES/Vulkan 系统库
        if (strstr(filename, "libEGL")) {
            void *h = get_system_lib("libEGL_adreno.so");
            if (h) return h;
        }
        if (strstr(filename, "libGLESv2")) {
            void *h = get_system_lib("libGLESv2_adreno.so");
            if (h) return h;
        }
        if (strstr(filename, "libGLESv1")) {
            void *h = get_system_lib("libGLESv2_adreno.so");
            if (h) return h;
        }
    }
    return real_dlopen(filename, flags);
}
