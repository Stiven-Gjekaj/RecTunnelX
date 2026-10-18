#import "RXMuxer.h"
#import "RXTS.h"

@implementation RXMuxer {
    RXTSWriter *_writer;
    int64_t _origin;
    BOOL _hasOrigin;
}

- (instancetype)initWithAudio:(BOOL)hasAudio {
    if ((self = [super init])) {
        _hasAudio = hasAudio;
        _writer = [RXTSWriter new];
        _writer.hasAudio = hasAudio;
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

- (NSData *)muxAudio:(NSData *)adts pts90k:(int64_t)pts {
    @synchronized (self) {
        if (!_hasAudio || !_hasOrigin) return [NSData data];
        [_writer writeAudio:adts pts:[self streamTime:pts]];
        return [self take];
    }
}

@end
