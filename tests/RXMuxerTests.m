#import "RXTest.h"
#import "RXMuxer.h"
#import "RXTS.h"

static uint16_t Pid(const uint8_t *packet) {
    return (uint16_t)(((packet[1] & 0x1f) << 8) | packet[2]);
}

static NSData *Frame(void) {
    const uint8_t bytes[] = { 0, 0, 0, 1, 0x09, 0xf0, 0, 0, 0, 1, 0x65, 0x88, 0x84 };
    return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}

// Reads the PTS of the PES packet that starts in the packet.
static int64_t PacketPts(const uint8_t *p) {
    size_t start = (p[3] & 0x20) ? 5 + p[4] : 4;
    const uint8_t *t = p + start + 9;
    return ((int64_t)((t[0] >> 1) & 7) << 30) | ((int64_t)t[1] << 22) | ((int64_t)(t[2] >> 1) << 15) |
           ((int64_t)t[3] << 7) | (t[4] >> 1);
}

RX_TEST(test_muxer_waits_for_first_key_frame) {
    RXMuxer *muxer = [[RXMuxer alloc] initWithAudio:NO];
    RX_EQUAL_INT([muxer muxVideo:Frame() pts90k:1000 isSync:NO].length, 0);
    RX_EQUAL_INT([muxer muxAudio:Frame() pts90k:1000].length, 0);
    RX_EXPECT([muxer muxVideo:Frame() pts90k:2000 isSync:YES].length > 0);
}

RX_TEST(test_muxer_key_frame_starts_with_tables) {
    RXMuxer *muxer = [[RXMuxer alloc] initWithAudio:NO];
    NSData *key = [muxer muxVideo:Frame() pts90k:5000 isSync:YES];
    RX_EQUAL_INT(key.length % RXTSPacketSize, 0);
    const uint8_t *b = key.bytes;
    RX_EQUAL_INT(Pid(b), 0);
    RX_EQUAL_INT(Pid(b + RXTSPacketSize), RXTSPidPMT);
    RX_EQUAL_INT(Pid(b + 2 * RXTSPacketSize), RXTSPidVideo);

    NSData *next = [muxer muxVideo:Frame() pts90k:8000 isSync:NO];
    RX_EQUAL_INT(Pid(next.bytes), RXTSPidVideo);
}

RX_TEST(test_muxer_times_start_at_one_second) {
    RXMuxer *muxer = [[RXMuxer alloc] initWithAudio:NO];
    NSData *key = [muxer muxVideo:Frame() pts90k:123456789 isSync:YES];
    RX_EQUAL_INT(PacketPts((const uint8_t *)key.bytes + 2 * RXTSPacketSize), 90000);
    NSData *next = [muxer muxVideo:Frame() pts90k:123456789 + 3000 isSync:NO];
    RX_EQUAL_INT(PacketPts(next.bytes), 93000);
}

RX_TEST(test_muxer_audio_has_its_pid) {
    RXMuxer *muxer = [[RXMuxer alloc] initWithAudio:YES];
    [muxer muxVideo:Frame() pts90k:0 isSync:YES];
    NSData *audio = [muxer muxAudio:Frame() pts90k:1500];
    RX_EQUAL_INT(Pid(audio.bytes), RXTSPidAudio);
    RX_EQUAL_INT(PacketPts(audio.bytes), 91500);
}
