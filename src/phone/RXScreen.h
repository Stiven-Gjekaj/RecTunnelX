// Copies the screen of the phone into pixel buffers.
// The hardware accelerator does the copy. It can also scale the image and
// change the pixel format.

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

@interface RXScreen : NSObject
@property (nonatomic, readonly) size_t width;
@property (nonatomic, readonly) size_t height;
@property (nonatomic, readonly) uint32_t pixelFormat;
// The seed of the screen surface. It changes when the screen changes.
@property (nonatomic, readonly) uint32_t seed;
// Returns nil and sets error if the screen surface is not available.
+ (instancetype)screenWithError:(NSString **)error;
// Copies the screen into a pixel buffer that has an IOSurface.
- (BOOL)copyToPixelBuffer:(CVPixelBufferRef)buffer;
@end
