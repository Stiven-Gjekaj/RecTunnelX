// The private functions of iOS 6 that RecTunnelX uses.
// RXPrivateLoad finds each function with dlsym. The SDK has no headers for
// them, and some of them are private on iOS 6 and public on later versions.

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

typedef void *RXFramebufferRef;
typedef void *RXSurfaceRef;
typedef void *RXAcceleratorRef;
typedef void *RXCompressionSessionRef;

typedef void (*RXCompressionOutputCallback)(void *outputRefCon, void *sourceFrameRefCon, OSStatus status,
                                            uint32_t infoFlags, CMSampleBufferRef sampleBuffer);

typedef struct {
    // IOMobileFramebuffer
    int (*FramebufferGetMainDisplay)(RXFramebufferRef *);
    int (*FramebufferGetLayerDefaultSurface)(RXFramebufferRef, int, RXSurfaceRef *);
    // IOSurface
    size_t (*SurfaceGetWidth)(RXSurfaceRef);
    size_t (*SurfaceGetHeight)(RXSurfaceRef);
    uint32_t (*SurfaceGetPixelFormat)(RXSurfaceRef);
    uint32_t (*SurfaceGetSeed)(RXSurfaceRef);
    int (*AcceleratorCreate)(CFAllocatorRef, uint32_t, RXAcceleratorRef *);
    int (*AcceleratorTransferSurface)(RXAcceleratorRef, RXSurfaceRef, RXSurfaceRef, CFDictionaryRef, void *);
    // CoreVideo
    RXSurfaceRef (*PixelBufferGetIOSurface)(CVPixelBufferRef);
    // VideoToolbox
    OSStatus (*CompressionSessionCreate)(CFAllocatorRef, int32_t, int32_t, CMVideoCodecType, CFDictionaryRef,
                                         CFDictionaryRef, CFAllocatorRef, RXCompressionOutputCallback, void *,
                                         RXCompressionSessionRef *);
    OSStatus (*CompressionSessionEncodeFrame)(RXCompressionSessionRef, CVImageBufferRef, CMTime, CMTime,
                                              CFDictionaryRef, void *, uint32_t *);
    OSStatus (*CompressionSessionCompleteFrames)(RXCompressionSessionRef, CMTime);
    void (*CompressionSessionInvalidate)(RXCompressionSessionRef);
    OSStatus (*SessionSetProperty)(void *, CFStringRef, CFTypeRef);
} RXPrivateFunctions;

extern RXPrivateFunctions RXPrivate;

// Finds all functions. Returns nil on success, or the name of the first
// function that is missing.
NSString *RXPrivateLoad(void);
