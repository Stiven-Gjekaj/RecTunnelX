#import "RXTest.h"
#import "RXAVC.h"

// A record with one SPS of 4 bytes, one PPS of 2 bytes, and 4-byte lengths.
static NSData *Record(void) {
    const uint8_t bytes[] = {
        0x01, 0x42, 0xc0, 0x1f, 0xff,  // version, profile, compatibility, level, length size 4
        0xe1, 0x00, 0x04, 0x67, 0x42, 0xc0, 0x1f,  // one SPS
        0x01, 0x00, 0x02, 0x68, 0xce,  // one PPS
    };
    return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}

RX_TEST(test_avc_reads_units_and_length_size) {
    RXAVCConfig *config = [RXAVCConfig configWithRecord:Record()];
    RX_EXPECT(config != nil);
    RX_EQUAL_INT(config.nalLengthSize, 4);
    RX_EQUAL_INT(config.sps.count, 1);
    RX_EQUAL_INT(config.pps.count, 1);
    const uint8_t sps[] = { 0x67, 0x42, 0xc0, 0x1f };
    const uint8_t pps[] = { 0x68, 0xce };
    RX_EQUAL(config.sps[0], [NSData dataWithBytes:sps length:sizeof(sps)]);
    RX_EQUAL(config.pps[0], [NSData dataWithBytes:pps length:sizeof(pps)]);
}

RX_TEST(test_avc_reads_two_byte_lengths) {
    NSMutableData *record = [Record() mutableCopy];
    ((uint8_t *)record.mutableBytes)[4] = 0xfd;
    RX_EQUAL_INT([RXAVCConfig configWithRecord:record].nalLengthSize, 2);
}

RX_TEST(test_avc_refuses_short_record) {
    NSData *record = Record();
    for (NSUInteger cut = 0; cut < record.length; cut++) {
        RX_EXPECT([RXAVCConfig configWithRecord:[record subdataWithRange:NSMakeRange(0, cut)]] == nil);
    }
}

RX_TEST(test_avc_refuses_other_version) {
    NSMutableData *record = [Record() mutableCopy];
    ((uint8_t *)record.mutableBytes)[0] = 2;
    RX_EXPECT([RXAVCConfig configWithRecord:record] == nil);
}

RX_TEST(test_avc_refuses_no_pps) {
    NSMutableData *record = [[Record() subdataWithRange:NSMakeRange(0, 12)] mutableCopy];
    const uint8_t none = 0;
    [record appendBytes:&none length:1];
    RX_EXPECT([RXAVCConfig configWithRecord:record] == nil);
}
