#import "RXSettings.h"

static int RXClamp(long long value, int low, int high) {
    return value < low ? low : value > high ? high : (int)value;
}

// Reads a whole number from text. Returns NO if the text is not one.
static BOOL RXReadInteger(NSString *text, long long *value) {
    NSScanner *scanner = [NSScanner scannerWithString:text];
    return [scanner scanLongLong:value] && scanner.isAtEnd;
}

// Reads "1", "0", "yes", "no", "true", or "false".
static BOOL RXReadBool(NSString *text, BOOL *value) {
    NSString *lower = text.lowercaseString;
    if ([@[ @"1", @"yes", @"true", @"on" ] containsObject:lower]) {
        *value = YES;
        return YES;
    }
    if ([@[ @"0", @"no", @"false", @"off" ] containsObject:lower]) {
        *value = NO;
        return YES;
    }
    return NO;
}

@implementation RXSettings

- (instancetype)init {
    if ((self = [super init])) {
        _enabled = YES;
        _framesPerSecond = 30;
        _bitsPerSecond = 3000000;
        _scale = 1;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    RXSettings *copy = [RXSettings new];
    copy.enabled = self.enabled;
    copy.framesPerSecond = self.framesPerSecond;
    copy.bitsPerSecond = self.bitsPerSecond;
    copy.scale = self.scale;
    return copy;
}

- (void)setFramesPerSecond:(int)value {
    _framesPerSecond = RXClamp(value, 5, 60);
}

- (void)setBitsPerSecond:(int)value {
    _bitsPerSecond = RXClamp(value, 250000, 10000000);
}

- (void)setScale:(int)value {
    _scale = RXClamp(value, 1, 2);
}

+ (instancetype)settingsWithContentsOfFile:(NSString *)path {
    RXSettings *settings = [RXSettings new];
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
    id value;
    if ([(value = plist[@"enabled"]) isKindOfClass:[NSNumber class]]) settings.enabled = [value boolValue];
    if ([(value = plist[@"fps"]) isKindOfClass:[NSNumber class]]) settings.framesPerSecond = [value intValue];
    if ([(value = plist[@"bitrate"]) isKindOfClass:[NSNumber class]]) settings.bitsPerSecond = [value intValue];
    if ([(value = plist[@"scale"]) isKindOfClass:[NSNumber class]]) settings.scale = [value intValue];
    return settings;
}

- (NSDictionary *)dictionary {
    return @{
        @"enabled": @(self.enabled),
        @"fps": @(self.framesPerSecond),
        @"bitrate": @(self.bitsPerSecond),
        @"scale": @(self.scale),
    };
}

- (BOOL)writeToFile:(NSString *)path {
    return [self.dictionary writeToFile:path atomically:YES];
}

- (BOOL)applyQuery:(NSDictionary *)query error:(NSString **)error {
    RXSettings *next = [self copy];
    for (NSString *key in query) {
        NSString *text = query[key];
        long long number = 0;
        BOOL flag = NO;
        if ([key isEqualToString:@"enabled"]) {
            if (!RXReadBool(text, &flag)) {
                if (error) *error = [NSString stringWithFormat:@"%@ is not yes or no", key];
                return NO;
            }
            next.enabled = flag;
        } else if ([key isEqualToString:@"fps"] || [key isEqualToString:@"bitrate"] ||
                   [key isEqualToString:@"scale"]) {
            if (!RXReadInteger(text, &number)) {
                if (error) *error = [NSString stringWithFormat:@"%@ is not a number", key];
                return NO;
            }
            if ([key isEqualToString:@"fps"]) next.framesPerSecond = RXClamp(number, 5, 60);
            else if ([key isEqualToString:@"bitrate"]) next.bitsPerSecond = RXClamp(number, 250000, 10000000);
            else next.scale = RXClamp(number, 1, 2);
        } else {
            if (error) *error = [NSString stringWithFormat:@"%@ is not a setting", key];
            return NO;
        }
    }
    self.enabled = next.enabled;
    self.framesPerSecond = next.framesPerSecond;
    self.bitsPerSecond = next.bitsPerSecond;
    self.scale = next.scale;
    return YES;
}

@end
