#import "RXMuxer.h"
#import "RXTS.h"

@implementation RXMuxer {
    RXTSWriter *_writer;
    int64_t _origin;
    BOOL _hasOrigin;
}

- (instancetype)init {
    if ((self = [super init])) {
        _writer = [RXTSWriter new];
    }
    return self;
}

// Moves a time of the device clock to the time of the stream.
- (int64_t)streamTime:(int64_t)pts {
    if (!_hasOrigin) {
        _origin = pts - 90000;
        _hasOrigin = YES;
    }
    int64_t t = pts - _origin;
    return t < 0 ? 0 : t;
}

- (NSData *)take {
    NSData *bytes = [_writer.output copy];
    [_writer.output setLength:0];
    return bytes;
}

- (NSData *)muxVideo:(NSData *)annexB pts90k:(int64_t)pts isSync:(BOOL)isSync {
    @synchronized (self) {
        // The stream starts at the first key frame.
        if (!_hasOrigin && !isSync) return [NSData data];
        int64_t t = [self streamTime:pts];
        if (isSync) [_writer writeTables];
        [_writer writeVideo:annexB pts:t dts:t isSync:isSync];
        return [self take];
    }
}

@end
