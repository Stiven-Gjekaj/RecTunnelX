// Turns encoded frames into the MPEG-TS bytes of one live stream.
// A video key frame starts with the PAT and the PMT, so that a client can
// start to decode at each key frame. The times start at 1 second, so that
// they are never negative.

#import <Foundation/Foundation.h>

@interface RXMuxer : NSObject
- (instancetype)initWithAudio:(BOOL)hasAudio;
@property (nonatomic, readonly) BOOL hasAudio;
// Returns the TS bytes of one H.264 frame in Annex B form. The time is in
// units of 90 kHz, on the clock of the device.
- (NSData *)muxVideo:(NSData *)annexB pts90k:(int64_t)pts isSync:(BOOL)isSync;
// Returns the TS bytes of one or more AAC frames in ADTS form.
- (NSData *)muxAudio:(NSData *)adts pts90k:(int64_t)pts;
@end
