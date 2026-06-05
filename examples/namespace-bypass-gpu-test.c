#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <stdint.h>

struct android_namespace_t;
typedef struct android_namespace_t android_namespace_t;
#define ANDROID_DLEXT_USE_NAMESPACE 0x200

int main() {
    typedef android_namespace_t* (*get_ns_t)(const char*);
    get_ns_t get_ns = (get_ns_t)dlsym(RTLD_DEFAULT, "__loader_android_get_exported_namespace");
    typedef void* (*dlopen_ext_t)(const char*, int, const void*);
    dlopen_ext_t dlopen_ext = (dlopen_ext_t)dlsym(RTLD_DEFAULT, "android_dlopen_ext");
    android_namespace_t *sphal = get_ns("sphal");
    
    uint8_t extinfo[128];
    memset(extinfo, 0, 128);
    *(uint64_t*)&extinfo[0] = ANDROID_DLEXT_USE_NAMESPACE;
    *(android_namespace_t**)&extinfo[40] = sphal;
    
    void *egl = dlopen_ext("libEGL_adreno.so", RTLD_LAZY | RTLD_LOCAL, extinfo);
    printf("EGL=%p\n", egl);
    if (!egl) return 1;
    
    // Try loading GLES from EGL handle
    void (*glClearColor)(float,float,float,float) = dlsym(egl, "glClearColor");
    void (*glClear)(unsigned int) = dlsym(egl, "glClear");
    const unsigned char* (*glGetStr)(unsigned int) = dlsym(egl, "glGetString");
    void* (*glGetIntegerv)(unsigned int,int*) = dlsym(egl, "glGetIntegerv");
    printf("glClearColor=%p glClear=%p glGetString=%p\n", glClearColor, glClear, glGetStr);
    
    // Get EGL functions  
    void* (*eglGetDisp)(void*) = dlsym(egl, "eglGetDisplay");
    int (*eglInit)(void*,void*,void*) = dlsym(egl, "eglInitialize");
    int (*eglChooseCfg)(void*,const int*,void*,int,int*) = dlsym(egl, "eglChooseConfig");
    void* (*eglCreateCtx)(void*,void*,void*,const int*) = dlsym(egl, "eglCreateContext");
    void* (*eglCreatePbuf)(void*,void*,const int*) = dlsym(egl, "eglCreatePbufferSurface");
    int (*eglMakeCur)(void*,void*,void*,void*) = dlsym(egl, "eglMakeCurrent");
    const char* (*eglQueryStr)(void*,int) = dlsym(egl, "eglQueryString");
    
    // Init
    void *dpy = eglGetDisp(0);
    int major=0, minor=0;
    eglInit(dpy, &major, &minor);
    printf("EGL %d.%d Vendor: %s\n", major, minor, eglQueryStr(dpy, 0x3053));
    
    int attrs[] = {0x3024,8,0x3023,8,0x3022,8,0x3021,8,0x3040,4,0x3038,0};
    void *config; int n=0;
    eglChooseCfg(dpy, attrs, &config, 1, &n);
    int ctx_attrs[] = {0x3098,2,0x3038,0};
    void *ctx = eglCreateCtx(dpy, config, 0, ctx_attrs);
    int pb_attrs[] = {0x3057,256,0x3056,256,0x3038,0};
    void *surf = eglCreatePbuf(dpy, config, pb_attrs);
    eglMakeCur(dpy, surf, surf, ctx);
    printf("Context OK. GPU: %s\n", glGetStr ? glGetStr(0x1F01) : "(null)");
    
    // GL functions might be in EGL lib
    if (!glClear) {
        // Use eglGetProcAddress
        void* (*eglGetProc)(const char*) = dlsym(egl, "eglGetProcAddress");
        if (eglGetProc) {
            glClear = (void (*)(unsigned int))eglGetProc("glClear");
            glClearColor = (void (*)(float,float,float,float))eglGetProc("glClearColor");
            printf("via eglGetProcAddress: glClear=%p glClearColor=%p\n", glClear, glClearColor);
        }
    }
    
    if (glClear && glClearColor) {
        glClearColor(0.2f, 0.4f, 0.8f, 1.0f);
        glClear(0x4000);
        printf("GPU rendering: OK\n");
    }
    
    return 0;
}
