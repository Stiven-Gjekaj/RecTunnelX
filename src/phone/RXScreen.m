#import "RXScreen.h"
#import "RXPrivate.h"

@implementation RXScreen {
    RXSurfaceRef _surface;
    RXAcceleratorRef _accelerator;
}

+ (instancetype)screenWithError:(NSString **)error {
    NSString *missing = RXPrivateLoad();
    if (missing) {
        if (error) *error = [@"missing function " stringByAppendingString:missing];
        return nil;
    }
    RXFramebufferRef fb = NULL;
    if (RXPrivate.FramebufferGetMainDisplay(&fb) != 0 || !fb) {
        if (error) *error = @"no main display";
        return nil;
    }
    RXSurfaceRef surface = NULL;
    if (RXPrivate.FramebufferGetLayerDefaultSurface(fb, 0, &surface) != 0 || !surface) {
        if (error) *error = @"no screen surface";
        return nil;
    }
    RXAcceleratorRef accelerator = NULL;
    if (RXPrivate.AcceleratorCreate(kCFAllocatorDefault, 0, &accelerator) != 0 || !accelerator) {
        if (error) *error = @"no surface accelerator";
        return nil;
    }
    RXScreen *screen = [RXScreen new];
    screen->_surface = surface;
    screen->_accelerator = accelerator;
    return screen;
}

- (size_t)width {
    return RXPrivate.SurfaceGetWidth(_surface);
}

- (size_t)height {
    return RXPrivate.SurfaceGetHeight(_surface);
}

- (uint32_t)pixelFormat {
    return RXPrivate.SurfaceGetPixelFormat(_surface);
}

- (uint32_t)seed {
    return RXPrivate.SurfaceGetSeed(_surface);
}

- (BOOL)copyToPixelBuffer:(CVPixelBufferRef)buffer {
    RXSurfaceRef target = RXPrivate.PixelBufferGetIOSurface(buffer);
    if (!target) return NO;
    return RXPrivate.AcceleratorTransferSurface(_accelerator, _surface, target, NULL, NULL) == 0;
}

@end
