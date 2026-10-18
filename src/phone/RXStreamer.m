#import "RXStreamer.h"
#import "RXEncoder.h"
#import "RXMuxer.h"
#import "RXScreen.h"
#import "RXSettings.h"
#import "RXStreamServer.h"
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <mach/mach_time.h>
#include <net/if.h>
#include <netinet/in.h>

static FILE *gLog;

void RXLogOpen(NSString *path) {
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    // Start a new log when the old one is larger than 256 KB.
    NSDictionary *info = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    gLog = fopen(path.fileSystemRepresentation, info.fileSize > 256 * 1024 ? "w" : "a");
}

void RXLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *stamped = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:[NSDate date]], line];
    FILE *out = gLog ?: stderr;
    @synchronized ([RXStreamer class]) {
        fputs(stamped.UTF8String, out);
        fflush(out);
    }
}

static int64_t RXNow90k(void) {
    static mach_timebase_info_data_t base;
    if (base.denom == 0) mach_timebase_info(&base);
    return (int64_t)((double)mach_absolute_time() * base.numer / base.denom / 1e9 * 90000);
}

// The IPv4 addresses of the network interfaces that are up, with no loopback.
static NSArray *RXAddresses(void) {
    NSMutableArray *addresses = [NSMutableArray array];
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0) return addresses;
    for (struct ifaddrs *a = list; a; a = a->ifa_next) {
        if (!a->ifa_addr || a->ifa_addr->sa_family != AF_INET) continue;
        if ((a->ifa_flags & IFF_LOOPBACK) || !(a->ifa_flags & IFF_UP)) continue;
        char text[INET_ADDRSTRLEN];
        struct sockaddr_in *in = (struct sockaddr_in *)a->ifa_addr;
        if (inet_ntop(AF_INET, &in->sin_addr, text, sizeof(text))) {
            [addresses addObject:@{ @"interface": @(a->ifa_name), @"address": @(text) }];
        }
    }
    freeifaddrs(list);
    return addresses;
}

@interface RXStreamer ()
@property (nonatomic, copy) NSString *settingsPath;
@property (nonatomic, strong) RXSettings *settings;
@property (nonatomic, strong) RXStreamServer *server;
@property (nonatomic, strong) dispatch_queue_t queue;  // Changes the state
@property (nonatomic, strong) RXScreen *screen;
@property (atomic, strong) RXEncoder *encoder;
@property (nonatomic, strong) RXMuxer *muxer;
@property (nonatomic, strong) NSThread *captureThread;
@property (nonatomic, copy) NSString *lastError;
@end

@implementation RXStreamer {
    volatile BOOL _stopCapture;
    volatile int64_t _framesSent;
    volatile int64_t _bytesSent;
    volatile int _width, _height;
}

- (instancetype)initWithSettingsPath:(NSString *)path port:(uint16_t)port {
    if ((self = [super init])) {
        _settingsPath = [path copy];
        _settings = [RXSettings settingsWithContentsOfFile:path];
        _server = [[RXStreamServer alloc] initWithPort:port loopbackOnly:NO];
        _queue = dispatch_queue_create("RXStreamer", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSString *)start {
    __weak RXStreamer *weakSelf = self;
    self.server.clientsChanged = ^(NSUInteger count) {
        RXLog(@"clients: %lu", (unsigned long)count);
        [weakSelf update];
    };
    self.server.needKeyFrame = ^{
        [weakSelf.encoder requestKeyFrame];
    };
    self.server.status = ^NSDictionary *{
        return [weakSelf status];
    };
    self.server.control = ^NSDictionary *(NSDictionary *query) {
        return [weakSelf control:query];
    };
    NSError *error = nil;
    if (![self.server start:&error]) return [NSString stringWithFormat:@"cannot listen on the port: %@", error];
    RXLog(@"listening on port %u, settings %@", self.server.port, self.settings.dictionary);
    return nil;
}

- (NSDictionary *)control:(NSDictionary *)query {
    __block NSDictionary *result = nil;
    dispatch_sync(self.queue, ^{
        NSString *error = nil;
        RXSettings *before = [self.settings copy];
        if (![self.settings applyQuery:query error:&error]) {
            result = @{ @"error": error };
            return;
        }
        [self.settings writeToFile:self.settingsPath];
        RXLog(@"settings: %@", self.settings.dictionary);
        // A new size, rate, or bitrate needs a new encoder.
        BOOL restart = before.framesPerSecond != self.settings.framesPerSecond ||
                       before.bitsPerSecond != self.settings.bitsPerSecond ||
                       before.scale != self.settings.scale || before.audio != self.settings.audio;
        if (restart) [self stopCaptureLocked];
        [self updateLocked];
        result = self.settings.dictionary;
    });
    return result;
}

- (NSDictionary *)status {
    __block NSDictionary *settings;
    __block BOOL capturing;
    __block NSString *lastError;
    dispatch_sync(self.queue, ^{
        settings = self.settings.dictionary;
        capturing = self.captureThread != nil;
        lastError = self.lastError;
    });
    NSMutableDictionary *status = [NSMutableDictionary dictionary];
    status[@"settings"] = settings;
    status[@"streaming"] = @(capturing);
    status[@"clients"] = @(self.server.clientCount);
    status[@"port"] = @(self.server.port);
    status[@"width"] = @(_width);
    status[@"height"] = @(_height);
    status[@"frames"] = @(_framesSent);
    status[@"bytes"] = @(_bytesSent);
    status[@"addresses"] = RXAddresses();
    if (lastError) status[@"error"] = lastError;
    return status;
}

- (void)update {
    dispatch_async(self.queue, ^{ [self updateLocked]; });
}

- (void)updateLocked {
    BOOL want = self.settings.enabled && self.server.clientCount > 0;
    if (want && !self.captureThread) [self startCaptureLocked];
    else if (!want && self.captureThread) [self stopCaptureLocked];
}

- (void)startCaptureLocked {
    NSString *error = nil;
    if (!self.screen) self.screen = [RXScreen screenWithError:&error];
    if (!self.screen) {
        self.lastError = error;
        RXLog(@"capture: %@", error);
        return;
    }
    int scale = self.settings.scale;
    int width = (int)self.screen.width / scale, height = (int)self.screen.height / scale;
    int fps = self.settings.framesPerSecond;
    RXMuxer *muxer = [[RXMuxer alloc] initWithAudio:NO];
    RXStreamServer *server = self.server;
    __block int64_t frames = 0, bytes = 0;
    RXStreamer *streamer = self;
    RXEncoder *encoder = [[RXEncoder alloc] initWithWidth:width height:height framesPerSecond:fps
        bitsPerSecond:self.settings.bitsPerSecond output:^(NSData *annexB, int64_t pts, BOOL isSync) {
            NSData *ts = [muxer muxVideo:annexB pts90k:pts isSync:isSync];
            if (ts.length == 0) return;
            [server sendFrame:ts isSync:isSync];
            frames++;
            bytes += ts.length;
            streamer->_framesSent = frames;
            streamer->_bytesSent = bytes;
        }];
    error = [encoder start];
    for (NSString *line in encoder.propertyLog) RXLog(@"encoder %@", line);
    if (error) {
        self.lastError = error;
        RXLog(@"encoder: %@", error);
        return;
    }
    self.lastError = nil;
    self.encoder = encoder;
    self.muxer = muxer;
    _width = width;
    _height = height;
    _stopCapture = NO;
    NSThread *thread = [[NSThread alloc] initWithTarget:self selector:@selector(captureLoop:)
                                                 object:@[ encoder, @(width), @(height), @(fps) ]];
    thread.name = @"RXStreamer.capture";
    self.captureThread = thread;
    [thread start];
    RXLog(@"capture: start %dx%d at %d fps, %d bit/s", width, height, fps, self.settings.bitsPerSecond);
}

- (void)stopCaptureLocked {
    if (!self.captureThread) return;
    _stopCapture = YES;
    while (!self.captureThread.isFinished) usleep(5000);
    self.captureThread = nil;
    [self.encoder stop];
    self.encoder = nil;
    self.muxer = nil;
    RXLog(@"capture: stop after %lld frames", (long long)_framesSent);
}

- (void)captureLoop:(NSArray *)arguments {
    [NSThread setThreadPriority:0.9];
    RXEncoder *encoder = arguments[0];
    int width = [arguments[1] intValue], height = [arguments[2] intValue], fps = [arguments[3] intValue];
    NSDictionary *attributes = @{
        (id)kCVPixelBufferWidthKey: @(width),
        (id)kCVPixelBufferHeightKey: @(height),
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
    };
    CVPixelBufferPoolRef pool = NULL;
    CVPixelBufferPoolCreate(NULL, NULL, (__bridge CFDictionaryRef)attributes, &pool);
    int64_t start = RXNow90k();
    int64_t frame = 0;
    int failures = 0;
    while (!_stopCapture) {
        @autoreleasepool {
            int64_t due = start + frame * 90000 / fps;
            int64_t now = RXNow90k();
            if (now < due) {
                usleep((useconds_t)((due - now) * 1000000 / 90000));
                continue;
            }
            // Skip the frames that are already late.
            int64_t late = (now - due) * fps / 90000;
            frame += late + 1;
            CVPixelBufferRef buffer = NULL;
            if (CVPixelBufferPoolCreatePixelBuffer(NULL, pool, &buffer) != 0) {
                failures++;
                continue;
            }
            if ([self.screen copyToPixelBuffer:buffer]) {
                if (![encoder encode:buffer pts90k:now]) failures++;
            } else {
                failures++;
            }
            CVPixelBufferRelease(buffer);
            if (failures == 100) RXLog(@"capture: 100 frames failed");
        }
    }
    CVPixelBufferPoolRelease(pool);
}

@end
