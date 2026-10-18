// cap: find the screen surface of the phone, time two copy methods, and save
// one frame to a PNG file.
// Usage: cap OUTPUT.png [FRAMES]
// Run it as root. The private functions come from dlsym, so the probe shows
// which functions iOS 6 has.

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#include <dlfcn.h>
#include <mach/mach_time.h>

typedef void *IOMobileFramebufferRef;
typedef void *IOSurfaceRef;
typedef void *IOSurfaceAcceleratorRef;

static int (*FBGetMainDisplay)(IOMobileFramebufferRef *);
static int (*FBGetLayerDefaultSurface)(IOMobileFramebufferRef, int, IOSurfaceRef *);
static size_t (*SurfGetWidth)(IOSurfaceRef);
static size_t (*SurfGetHeight)(IOSurfaceRef);
static size_t (*SurfGetBytesPerRow)(IOSurfaceRef);
static uint32_t (*SurfGetPixelFormat)(IOSurfaceRef);
static size_t (*SurfGetAllocSize)(IOSurfaceRef);
static void *(*SurfGetBaseAddress)(IOSurfaceRef);
static uint32_t (*SurfGetSeed)(IOSurfaceRef);
static int (*SurfLock)(IOSurfaceRef, uint32_t, uint32_t *);
static int (*SurfUnlock)(IOSurfaceRef, uint32_t, uint32_t *);
static IOSurfaceRef (*SurfCreate)(CFDictionaryRef);
static int (*AccelCreate)(CFAllocatorRef, uint32_t, IOSurfaceAcceleratorRef *);
static int (*AccelTransfer)(IOSurfaceAcceleratorRef, IOSurfaceRef, IOSurfaceRef, CFDictionaryRef, void *);

static void *find(void *lib, const char *name) {
    void *sym = dlsym(lib, name);
    printf("  %-40s %s\n", name, sym ? "yes" : "NO");
    return sym;
}

static double seconds(uint64_t ticks) {
    static mach_timebase_info_data_t base;
    if (base.denom == 0) mach_timebase_info(&base);
    return (double)ticks * base.numer / base.denom / 1e9;
}

static void fourcc(uint32_t value, char out[5]) {
    for (int i = 0; i < 4; i++) {
        char c = (char)((value >> (24 - 8 * i)) & 0xff);
        out[i] = (c >= 32 && c < 127) ? c : '?';
    }
    out[4] = 0;
}

// Write a BGRA buffer to a PNG file.
static BOOL writePNG(const char *path, void *pixels, size_t width, size_t height, size_t rowBytes) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, rowBytes, space,
        kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    if (!context) return NO;
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    NSURL *url = [NSURL fileURLWithPath:@(path)];
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("public.png"), 1, NULL);
    if (!dest) {
        CGImageRelease(image);
        return NO;
    }
    CGImageDestinationAddImage(dest, image, NULL);
    BOOL ok = CGImageDestinationFinalize(dest);
    CFRelease(dest);
    CGImageRelease(image);
    return ok;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: cap OUTPUT.png [FRAMES]\n");
            return 2;
        }
        int frames = argc > 2 ? atoi(argv[2]) : 60;

        void *fbLib = dlopen("/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/IOMobileFramebuffer", RTLD_NOW);
        void *surfLib = dlopen("/System/Library/PrivateFrameworks/IOSurface.framework/IOSurface", RTLD_NOW);
        if (!fbLib || !surfLib) {
            fprintf(stderr, "cap: dlopen failed: %s\n", dlerror());
            return 1;
        }
        printf("functions:\n");
        FBGetMainDisplay = find(fbLib, "IOMobileFramebufferGetMainDisplay");
        FBGetLayerDefaultSurface = find(fbLib, "IOMobileFramebufferGetLayerDefaultSurface");
        SurfGetWidth = find(surfLib, "IOSurfaceGetWidth");
        SurfGetHeight = find(surfLib, "IOSurfaceGetHeight");
        SurfGetBytesPerRow = find(surfLib, "IOSurfaceGetBytesPerRow");
        SurfGetPixelFormat = find(surfLib, "IOSurfaceGetPixelFormat");
        SurfGetAllocSize = find(surfLib, "IOSurfaceGetAllocSize");
        SurfGetBaseAddress = find(surfLib, "IOSurfaceGetBaseAddress");
        SurfGetSeed = find(surfLib, "IOSurfaceGetSeed");
        SurfLock = find(surfLib, "IOSurfaceLock");
        SurfUnlock = find(surfLib, "IOSurfaceUnlock");
        SurfCreate = find(surfLib, "IOSurfaceCreate");
        AccelCreate = find(surfLib, "IOSurfaceAcceleratorCreate");
        AccelTransfer = find(surfLib, "IOSurfaceAcceleratorTransferSurface");
        if (!FBGetMainDisplay || !FBGetLayerDefaultSurface || !SurfGetBaseAddress || !SurfLock) {
            fprintf(stderr, "cap: a required function is missing\n");
            return 1;
        }

        IOMobileFramebufferRef fb = NULL;
        int kr = FBGetMainDisplay(&fb);
        printf("main display: kr=%d fb=%p\n", kr, fb);
        if (!fb) return 1;

        IOSurfaceRef screen = NULL;
        for (int layer = 0; layer < 3; layer++) {
            IOSurfaceRef surface = NULL;
            kr = FBGetLayerDefaultSurface(fb, layer, &surface);
            if (!surface) {
                printf("layer %d: kr=%d no surface\n", layer, kr);
                continue;
            }
            char fmt[5];
            fourcc(SurfGetPixelFormat(surface), fmt);
            printf("layer %d: %zux%zu rowbytes=%zu format=%s alloc=%zu seed=%u\n", layer,
                SurfGetWidth(surface), SurfGetHeight(surface), SurfGetBytesPerRow(surface), fmt,
                SurfGetAllocSize(surface), SurfGetSeed(surface));
            if (!screen) screen = surface;
        }
        if (!screen) {
            fprintf(stderr, "cap: no screen surface\n");
            return 1;
        }

        size_t width = SurfGetWidth(screen);
        size_t height = SurfGetHeight(screen);
        size_t rowBytes = SurfGetBytesPerRow(screen);
        size_t size = rowBytes * height;
        void *copy = malloc(size);

        // Method A: lock the screen surface and copy it with the CPU.
        uint64_t start = mach_absolute_time();
        uint32_t seedFirst = SurfGetSeed(screen);
        for (int i = 0; i < frames; i++) {
            SurfLock(screen, 1, NULL);
            memcpy(copy, SurfGetBaseAddress(screen), size);
            SurfUnlock(screen, 1, NULL);
        }
        double cpu = seconds(mach_absolute_time() - start);
        printf("cpu copy: %d frames in %.3f s = %.1f fps (seed %u -> %u)\n", frames, cpu,
            frames / cpu, seedFirst, SurfGetSeed(screen));

        // Method B: let the accelerator copy the screen into a surface of our own.
        IOSurfaceRef own = NULL;
        IOSurfaceAcceleratorRef accel = NULL;
        if (SurfCreate && AccelCreate && AccelTransfer) {
            NSDictionary *props = @{
                @"IOSurfaceIsGlobal": @YES,
                @"IOSurfaceWidth": @(width),
                @"IOSurfaceHeight": @(height),
                @"IOSurfaceBytesPerElement": @4,
                @"IOSurfaceBytesPerRow": @(rowBytes),
                @"IOSurfaceAllocSize": @(size),
                @"IOSurfacePixelFormat": @(SurfGetPixelFormat(screen)),
            };
            own = SurfCreate((__bridge CFDictionaryRef)props);
            kr = AccelCreate(kCFAllocatorDefault, 0, &accel);
            printf("accelerator: kr=%d accel=%p own=%p\n", kr, accel, own);
        }
        if (own && accel) {
            start = mach_absolute_time();
            int failed = 0;
            for (int i = 0; i < frames; i++) {
                if (AccelTransfer(accel, screen, own, NULL, NULL) != 0) failed++;
            }
            double gpu = seconds(mach_absolute_time() - start);
            printf("accelerator copy: %d frames in %.3f s = %.1f fps, %d failed\n", frames, gpu,
                frames / gpu, failed);
            SurfLock(own, 1, NULL);
            memcpy(copy, SurfGetBaseAddress(own), size);
            SurfUnlock(own, 1, NULL);
        } else {
            SurfLock(screen, 1, NULL);
            memcpy(copy, SurfGetBaseAddress(screen), size);
            SurfUnlock(screen, 1, NULL);
        }

        if (!writePNG(argv[1], copy, width, height, rowBytes)) {
            fprintf(stderr, "cap: cannot write %s\n", argv[1]);
            return 1;
        }
        printf("wrote %s\n", argv[1]);
        free(copy);
    }
    return 0;
}
