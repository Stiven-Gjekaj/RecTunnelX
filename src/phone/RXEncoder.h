// Encodes pixel buffers to H.264 with the hardware encoder of the phone.
// Each output frame is in Annex B form, with an access unit delimiter.
// A key frame also has the SPS and the PPS.

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

typedef void (^RXEncoderOutput)(NSData *annexB, int64_t pts90k, BOOL isSync);

@interface RXEncoder : NSObject
// The output block runs on a thread of the encoder.
- (instancetype)initWithWidth:(int)width height:(int)height framesPerSecond:(int)fps
                  bitsPerSecond:(int)bitrate output:(RXEncoderOutput)output;
// Returns nil if the encoder started, or the reason that it did not start.
- (NSString *)start;
// The time is in units of 90 kHz.
- (BOOL)encode:(CVPixelBufferRef)buffer pts90k:(int64_t)pts;
// Asks the encoder for a key frame at the next frame.
- (void)requestKeyFrame;
- (void)stop;
@property (nonatomic, readonly) NSArray *propertyLog;  // One line for each property that was set
@end
