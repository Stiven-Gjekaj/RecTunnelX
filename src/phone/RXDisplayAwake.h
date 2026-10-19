// Holds a power assertion that stops the display from idle sleep.
// The daemon holds it while it captures the screen, so that the phone does
// not auto-lock in the middle of a stream.
//
// The assertion stops the idle timer only. It does not stop a lock from the
// power button.

#import <Foundation/Foundation.h>

@interface RXDisplayAwake : NSObject
// YES creates the assertion. NO releases it. A second call with the same
// value does nothing. Returns NO if the assertion is not available.
- (BOOL)setActive:(BOOL)active;
@property (nonatomic, readonly) BOOL active;
@end
