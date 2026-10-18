#import "RXEncoder.h"
#import "RXPrivate.h"
#import "RXAVC.h"
#import "RXTS.h"
#include <libkern/OSAtomic.h>

@interface RXEncoder ()
@property (nonatomic, copy) RXEncoderOutput output;
@property (nonatomic, strong) NSMutableArray *log;
@property (nonatomic, strong) RXAVCConfig *config;
@property (nonatomic, strong) NSData *configRecord;
@end

@implementation RXEncoder {
    int _width, _height, _fps, _bitrate;
    RXCompressionSessionRef _session;
    volatile int32_t _wantKeyFrame;
}

- (instancetype)initWithWidth:(int)width height:(int)height framesPerSecond:(int)fps
                  bitsPerSecond:(int)bitrate output:(RXEncoderOutput)output {
    if ((self = [super init])) {
        _width = width;
        _height = height;
        _fps = fps;
        _bitrate = bitrate;
        _output = [output copy];
        _log = [NSMutableArray array];
    }
    return self;
}

- (NSArray *)propertyLog {
    return [self.log copy];
}

static void RXEncoderCallback(void *refCon, void *frameRefCon, OSStatus status, uint32_t flags,
                              CMSampleBufferRef sample) {
    RXEncoder *encoder = (__bridge RXEncoder *)refCon;
    if (status != 0 || !sample) return;
    @autoreleasepool {
        [encoder handleSample:sample];
    }
}

- (void)handleSample:(CMSampleBufferRef)sample {
    CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sample);
    CFDictionaryRef atoms = format ? CMFormatDescriptionGetExtension(format,
        kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) : NULL;
    NSData *record = atoms ? ((__bridge NSDictionary *)atoms)[@"avcC"] : nil;
    if (record && ![record isEqualToData:self.configRecord]) {
        RXAVCConfig *config = [RXAVCConfig configWithRecord:record];
        if (config) {
            self.config = config;
            self.configRecord = record;
        }
    }
    if (!self.config) return;

    BOOL isSync = YES;
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sample, false);
    if (attachments && CFArrayGetCount(attachments) > 0) {
        CFDictionaryRef first = CFArrayGetValueAtIndex(attachments, 0);
        CFBooleanRef notSync = CFDictionaryGetValue(first, kCMSampleAttachmentKey_NotSync);
        isSync = !(notSync && CFBooleanGetValue(notSync));
    }

    CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
    if (!block) return;
    size_t length = CMBlockBufferGetDataLength(block);
    NSMutableData *bytes = [NSMutableData dataWithLength:length];
    if (CMBlockBufferCopyDataBytes(block, 0, length, bytes.mutableBytes) != 0) return;
    NSData *annexB = RXTSAnnexB(bytes.bytes, length, self.config.nalLengthSize, self.config.sps,
                                self.config.pps, isSync);
    if (!annexB) return;
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sample);
    int64_t pts90k = CMTimeConvertScale(pts, 90000, kCMTimeRoundingMethod_RoundHalfAwayFromZero).value;
    self.output(annexB, pts90k, isSync);
}

- (void)setProperty:(NSString *)key value:(id)value {
    OSStatus status = RXPrivate.SessionSetProperty(_session, (__bridge CFStringRef)key, (__bridge CFTypeRef)value);
    [self.log addObject:[NSString stringWithFormat:@"%@=%@ status=%d", key, value, (int)status]];
}

- (NSString *)start {
    NSString *missing = RXPrivateLoad();
    if (missing) return [@"missing function " stringByAppendingString:missing];
    OSStatus status = RXPrivate.CompressionSessionCreate(kCFAllocatorDefault, _width, _height,
        kCMVideoCodecType_H264, NULL, NULL, NULL, RXEncoderCallback, (__bridge void *)self, &_session);
    if (status != 0 || !_session) return [NSString stringWithFormat:@"VTCompressionSessionCreate status %d", (int)status];
    [self setProperty:@"RealTime" value:@YES];
    [self setProperty:@"ProfileLevel" value:@"H264_Baseline_AutoLevel"];
    [self setProperty:@"AllowFrameReordering" value:@NO];
    [self setProperty:@"AverageBitRate" value:@(_bitrate)];
    [self setProperty:@"ExpectedFrameRate" value:@(_fps)];
    [self setProperty:@"MaxKeyFrameInterval" value:@(_fps * 2)];
    return nil;
}

- (void)requestKeyFrame {
    OSAtomicCompareAndSwap32Barrier(0, 1, &_wantKeyFrame);
}

- (BOOL)encode:(CVPixelBufferRef)buffer pts90k:(int64_t)pts {
    if (!_session) return NO;
    NSDictionary *properties = nil;
    if (OSAtomicCompareAndSwap32Barrier(1, 0, &_wantKeyFrame)) {
        properties = @{ @"ForceKeyFrame": @YES };
    }
    OSStatus status = RXPrivate.CompressionSessionEncodeFrame(_session, buffer, CMTimeMake(pts, 90000),
        CMTimeMake(90000 / _fps, 90000), (__bridge CFDictionaryRef)properties, NULL, NULL);
    return status == 0;
}

- (void)stop {
    if (!_session) return;
    RXPrivate.CompressionSessionCompleteFrames(_session, kCMTimeInvalid);
    RXPrivate.CompressionSessionInvalidate(_session);
    CFRelease(_session);
    _session = NULL;
}

- (void)dealloc {
    [self stop];
}

@end
