#import "RXAVC.h"

@interface RXAVCConfig ()
@property (nonatomic, strong) NSArray *sps;
@property (nonatomic, strong) NSArray *pps;
@property (nonatomic) int nalLengthSize;
@end

// Reads a count of units, then each unit with a 16-bit length.
// Returns nil if the record ends too soon.
static NSArray *RXReadUnits(const uint8_t *bytes, size_t length, size_t *position, int count) {
    NSMutableArray *units = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        if (*position + 2 > length) return nil;
        size_t unitLength = ((size_t)bytes[*position] << 8) | bytes[*position + 1];
        *position += 2;
        if (unitLength == 0 || unitLength > length - *position) return nil;
        [units addObject:[NSData dataWithBytes:bytes + *position length:unitLength]];
        *position += unitLength;
    }
    return units;
}

@implementation RXAVCConfig

+ (instancetype)configWithRecord:(NSData *)record {
    const uint8_t *b = record.bytes;
    size_t length = record.length;
    if (length < 7 || b[0] != 1) return nil;
    int nalLengthSize = (b[4] & 3) + 1;
    if (nalLengthSize == 3) return nil;
    size_t position = 6;
    NSArray *sps = RXReadUnits(b, length, &position, b[5] & 0x1f);
    if (!sps || position >= length) return nil;
    int ppsCount = b[position++];
    NSArray *pps = RXReadUnits(b, length, &position, ppsCount);
    if (!pps || sps.count == 0 || pps.count == 0) return nil;
    RXAVCConfig *config = [RXAVCConfig new];
    config.sps = sps;
    config.pps = pps;
    config.nalLengthSize = nalLengthSize;
    return config;
}

@end
