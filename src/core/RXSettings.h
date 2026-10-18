// The settings of the stream. The daemon keeps them in a property list.
// Each value has limits. A value out of its limits becomes the nearest limit.

#import <Foundation/Foundation.h>

enum {
    RXDefaultPort = 7272,
};

@interface RXSettings : NSObject <NSCopying>
@property (nonatomic) BOOL enabled;  // NO stops the stream. The default is YES.
@property (nonatomic) BOOL audio;  // YES sends the system audio. The default is YES.
@property (nonatomic) int framesPerSecond;  // 5 to 60. The default is 30.
@property (nonatomic) int bitsPerSecond;  // 250000 to 10000000. The default is 3000000.
@property (nonatomic) int scale;  // 1 for 640x960, 2 for 320x480. The default is 1.

// Reads the settings from a property list. A missing file or value gives
// the default.
+ (instancetype)settingsWithContentsOfFile:(NSString *)path;
- (NSDictionary *)dictionary;
- (BOOL)writeToFile:(NSString *)path;
// Changes the settings with the text values of a query, for example
// "fps" = "25". Returns NO and changes nothing if a key is not known or a
// value is not a number.
- (BOOL)applyQuery:(NSDictionary *)query error:(NSString **)error;
@end
