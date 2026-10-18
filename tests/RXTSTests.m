#import "RXTest.h"
#import "RXTS.h"

// Returns the payload of each packet of the PID, joined. Fails the test if
// a packet does not start with the sync byte.
static NSData *PayloadOfPid(NSData *stream, uint16_t pid, int *packets) {
    NSMutableData *payload = [NSMutableData data];
    const uint8_t *b = stream.bytes;
    *packets = 0;
    for (NSUInteger i = 0; i + RXTSPacketSize <= stream.length; i += RXTSPacketSize) {
        const uint8_t *p = b + i;
        RX_EQUAL_INT(p[0], 0x47);
        if ((((p[1] & 0x1f) << 8) | p[2]) != pid) continue;
        (*packets)++;
        NSUInteger start = 4;
        if (p[3] & 0x20) start = 5 + p[4];
        if (p[3] & 0x10) [payload appendBytes:p + start length:RXTSPacketSize - start];
    }
    return payload;
}

static int64_t ReadTimestamp(const uint8_t *p) {
    return ((int64_t)((p[0] >> 1) & 7) << 30) | ((int64_t)p[1] << 22) | ((int64_t)(p[2] >> 1) << 15) |
           ((int64_t)p[3] << 7) | (p[4] >> 1);
}

RX_TEST(test_ts_crc_of_standard_pat) {
    // The PAT of one program with the PMT on PID 0x1000. ffmpeg writes the
    // same section, with the CRC 0x2AB104B2.
    const uint8_t pat[] = { 0x00, 0xb0, 0x0d, 0x00, 0x01, 0xc1, 0x00, 0x00, 0x00, 0x01, 0xf0, 0x00 };
    RX_EQUAL_INT(RXTSCRC32(pat, sizeof(pat)), 0x2ab104b2);
}

RX_TEST(test_ts_tables_have_valid_crc) {
    RXTSWriter *writer = [RXTSWriter new];
    [writer writeTables];
    RX_EQUAL_INT(writer.output.length, 2 * RXTSPacketSize);
    for (int i = 0; i < 2; i++) {
        const uint8_t *section = (const uint8_t *)writer.output.bytes + i * RXTSPacketSize + 5;
        size_t length = 3 + (((section[1] & 0x0f) << 8) | section[2]);
        // The CRC of a section with its own CRC at the end is 0.
        RX_EQUAL_INT(RXTSCRC32(section, length), 0);
    }
}

RX_TEST(test_ts_pmt_lists_the_video_stream) {
    RXTSWriter *writer = [RXTSWriter new];
    [writer writeTables];
    const uint8_t *pmt = (const uint8_t *)writer.output.bytes + RXTSPacketSize + 5;
    RX_EQUAL_INT(pmt[0], 0x02);
    RX_EQUAL_INT(((pmt[1] & 0x0f) << 8) | pmt[2], 18);  // the section length
    RX_EQUAL_INT(pmt[12], 0x1b);  // H.264
    RX_EQUAL_INT(((pmt[13] & 0x1f) << 8) | pmt[14], RXTSPidVideo);
}

RX_TEST(test_ts_annexb_adds_delimiter_and_parameter_sets) {
    const uint8_t sample[] = { 0, 0, 0, 2, 0x65, 0x88,   // IDR slice
                               0, 0, 0, 1, 0x09 };       // a delimiter, dropped
    NSArray *sps = @[ [NSData dataWithBytes:"\x67\x4d" length:2] ];
    NSArray *pps = @[ [NSData dataWithBytes:"\x68" length:1] ];
    NSData *out = RXTSAnnexB(sample, sizeof(sample), 4, sps, pps, YES);
    const uint8_t expected[] = { 0, 0, 0, 1, 0x09, 0xf0, 0, 0, 0, 1, 0x67, 0x4d, 0, 0, 0, 1, 0x68,
                                 0, 0, 0, 1, 0x65, 0x88 };
    RX_EQUAL(out, [NSData dataWithBytes:expected length:sizeof(expected)]);
}

RX_TEST(test_ts_annexb_of_other_sample_has_no_parameter_sets) {
    const uint8_t sample[] = { 0, 2, 0x41, 0x9a };  // a 2-byte length
    NSData *out = RXTSAnnexB(sample, sizeof(sample), 2, @[ [NSData dataWithBytes:"\x67" length:1] ], @[], NO);
    const uint8_t expected[] = { 0, 0, 0, 1, 0x09, 0xf0, 0, 0, 0, 1, 0x41, 0x9a };
    RX_EQUAL(out, [NSData dataWithBytes:expected length:sizeof(expected)]);
}

RX_TEST(test_ts_annexb_refuses_wrong_length) {
    const uint8_t sample[] = { 0, 0, 0, 9, 0x41 };
    RX_EXPECT(RXTSAnnexB(sample, sizeof(sample), 4, @[], @[], NO) == nil);
    const uint8_t zero[] = { 0, 0, 0, 0 };
    RX_EXPECT(RXTSAnnexB(zero, sizeof(zero), 4, @[], @[], NO) == nil);
}

RX_TEST(test_ts_video_pes_round_trips) {
    for (NSUInteger size = 1; size < 1200; size += 37) {
        NSMutableData *frame = [NSMutableData dataWithLength:size];
        for (NSUInteger i = 0; i < size; i++) ((uint8_t *)frame.mutableBytes)[i] = (uint8_t)(i * 7 + size);
        RXTSWriter *writer = [RXTSWriter new];
        [writer writeVideo:frame pts:93003 dts:90000 isSync:YES];
        RX_EQUAL_INT(writer.output.length % RXTSPacketSize, 0);
        int packets = 0;
        NSData *payload = PayloadOfPid(writer.output, RXTSPidVideo, &packets);
        const uint8_t *p = payload.bytes;
        RX_EQUAL_INT(p[0] << 16 | p[1] << 8 | p[2], 1);
        RX_EQUAL_INT(p[3], 0xe0);
        RX_EQUAL_INT(p[7], 0xc0);
        RX_EQUAL_INT(ReadTimestamp(p + 9), 93003);
        RX_EQUAL_INT(ReadTimestamp(p + 14), 90000);
        RX_EQUAL([payload subdataWithRange:NSMakeRange(19, payload.length - 19)], frame);
        // The first packet holds the PCR and the random access flag.
        const uint8_t *first = writer.output.bytes;
        RX_EXPECT(first[1] & 0x40);
        RX_EXPECT(first[3] & 0x20);
        RX_EQUAL_INT(first[5] & 0x50, 0x50);
    }
}

RX_TEST(test_ts_continuity_counts_up_for_the_video_pid) {
    RXTSWriter *writer = [RXTSWriter new];
    // Each 100-byte frame fits in one transport packet.
    for (int i = 0; i < 20; i++) [writer writeVideo:[NSMutableData dataWithLength:100] pts:i dts:i isSync:NO];
    const uint8_t *b = writer.output.bytes;
    RX_EQUAL_INT(writer.output.length, 20 * RXTSPacketSize);
    for (int i = 0; i < 20; i++) RX_EQUAL_INT(b[i * RXTSPacketSize + 3] & 0x0f, i % 16);
}
