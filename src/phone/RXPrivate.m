#import "RXPrivate.h"
#include <dlfcn.h>

RXPrivateFunctions RXPrivate;

static NSString *RXFind(void *library, const char *name, void **slot) {
    *slot = library ? dlsym(library, name) : NULL;
    return *slot ? nil : @(name);
}

NSString *RXPrivateLoad(void) {
    static NSString *missing;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *fb = dlopen("/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/IOMobileFramebuffer", RTLD_NOW);
        void *surface = dlopen("/System/Library/PrivateFrameworks/IOSurface.framework/IOSurface", RTLD_NOW);
        void *video = dlopen("/System/Library/Frameworks/CoreVideo.framework/CoreVideo", RTLD_NOW);
        void *vt = dlopen("/System/Library/Frameworks/VideoToolbox.framework/VideoToolbox", RTLD_NOW);
        struct { void *library; const char *name; void **slot; } table[] = {
            { fb, "IOMobileFramebufferGetMainDisplay", (void **)&RXPrivate.FramebufferGetMainDisplay },
            { fb, "IOMobileFramebufferGetLayerDefaultSurface", (void **)&RXPrivate.FramebufferGetLayerDefaultSurface },
            { surface, "IOSurfaceGetWidth", (void **)&RXPrivate.SurfaceGetWidth },
            { surface, "IOSurfaceGetHeight", (void **)&RXPrivate.SurfaceGetHeight },
            { surface, "IOSurfaceGetPixelFormat", (void **)&RXPrivate.SurfaceGetPixelFormat },
            { surface, "IOSurfaceGetSeed", (void **)&RXPrivate.SurfaceGetSeed },
            { surface, "IOSurfaceAcceleratorCreate", (void **)&RXPrivate.AcceleratorCreate },
            { surface, "IOSurfaceAcceleratorTransferSurface", (void **)&RXPrivate.AcceleratorTransferSurface },
            { video, "CVPixelBufferGetIOSurface", (void **)&RXPrivate.PixelBufferGetIOSurface },
            { vt, "VTCompressionSessionCreate", (void **)&RXPrivate.CompressionSessionCreate },
            { vt, "VTCompressionSessionEncodeFrame", (void **)&RXPrivate.CompressionSessionEncodeFrame },
            { vt, "VTCompressionSessionCompleteFrames", (void **)&RXPrivate.CompressionSessionCompleteFrames },
            { vt, "VTCompressionSessionInvalidate", (void **)&RXPrivate.CompressionSessionInvalidate },
            { vt, "VTSessionSetProperty", (void **)&RXPrivate.SessionSetProperty },
        };
        for (size_t i = 0; i < sizeof(table) / sizeof(table[0]); i++) {
            NSString *name = RXFind(table[i].library, table[i].name, table[i].slot);
            if (name && !missing) missing = name;
        }
    });
    return missing;
}
