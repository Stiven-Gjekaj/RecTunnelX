// Runs the whole stream on the phone: the server, the screen capture, the
// encoder, and the muxer. The capture runs only while the stream is enabled
// and at least one client is connected.

#import <Foundation/Foundation.h>

@interface RXStreamer : NSObject
- (instancetype)initWithSettingsPath:(NSString *)path port:(uint16_t)port;
// Returns nil if the server started, or the reason that it did not start.
- (NSString *)start;
- (NSDictionary *)status;
@end

// Writes one line to the log of the daemon.
void RXLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
void RXLogOpen(NSString *path);
