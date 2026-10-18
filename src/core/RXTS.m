#import "RXTS.h"

uint32_t RXTSCRC32(const uint8_t *bytes, size_t length) {
    uint32_t crc = 0xffffffff;
    for (size_t i = 0; i < length; i++) {
        crc ^= (uint32_t)bytes[i] << 24;
        for (int bit = 0; bit < 8; bit++) crc = (crc & 0x80000000) ? (crc << 1) ^ 0x04c11db7 : crc << 1;
    }
    return crc;
}

static const uint8_t RXStartCode[4] = { 0, 0, 0, 1 };

NSData *RXTSAnnexB(const uint8_t *sample, size_t length, int nalLengthSize, NSArray *sps, NSArray *pps, BOOL isSync) {
    NSMutableData *out = [NSMutableData dataWithCapacity:length + 64];
    const uint8_t aud[2] = { 0x09, 0xf0 };
    [out appendBytes:RXStartCode length:4];
    [out appendBytes:aud length:2];
    if (isSync) {
        for (NSData *unit in [sps arrayByAddingObjectsFromArray:pps]) {
            [out appendBytes:RXStartCode length:4];
            [out appendData:unit];
        }
    }
    size_t position = 0;
    while (position < length) {
        if (position + nalLengthSize > length) return nil;
        size_t unitLength = 0;
        for (int i = 0; i < nalLengthSize; i++) unitLength = (unitLength << 8) | sample[position + i];
        position += nalLengthSize;
        if (unitLength == 0 || unitLength > length - position) return nil;
        int type = sample[position] & 0x1f;
        if (type != 7 && type != 8 && type != 9) {
            [out appendBytes:RXStartCode length:4];
            [out appendBytes:sample + position length:unitLength];
        }
        position += unitLength;
    }
    return out;
}

@interface RXTSWriter ()
@property (nonatomic, strong) NSMutableData *output;
@end

@implementation RXTSWriter {
    uint8_t _continuity[2];  // PMT, video
}

- (instancetype)init {
    if ((self = [super init])) {
        _output = [NSMutableData data];
    }
    return self;
}

- (uint8_t)nextContinuityForPid:(uint16_t)pid {
    int slot = pid == RXTSPidVideo ? 1 : 0;
    uint8_t value = _continuity[slot];
    _continuity[slot] = (value + 1) & 0x0f;
    return value;
}

// Writes one PSI section in one packet. The PAT has PID 0. Its continuity
// counter is kept in the slot of the PMT, because both are written once
// for each segment.
- (void)writeSection:(const uint8_t *)section length:(size_t)length pid:(uint16_t)pid {
    uint8_t packet[RXTSPacketSize];
    memset(packet, 0xff, sizeof(packet));
    packet[0] = 0x47;
    packet[1] = 0x40 | (pid >> 8);
    packet[2] = pid & 0xff;
    packet[3] = 0x10 | (pid == 0 ? 0 : [self nextContinuityForPid:pid]);
    packet[4] = 0;  // pointer field
    memcpy(packet + 5, section, length);
    uint32_t crc = RXTSCRC32(section, length);
    packet[5 + length] = crc >> 24;
    packet[6 + length] = (crc >> 16) & 0xff;
    packet[7 + length] = (crc >> 8) & 0xff;
    packet[8 + length] = crc & 0xff;
    [self.output appendBytes:packet length:sizeof(packet)];
}

- (void)writeTables {
    const uint8_t pat[] = {
        0x00, 0xb0, 0x0d, 0x00, 0x01, 0xc1, 0x00, 0x00,
        0x00, 0x01, 0xe0 | (RXTSPidPMT >> 8), RXTSPidPMT & 0xff,
    };
    [self writeSection:pat length:sizeof(pat) pid:0];

    uint8_t pmt[32];
    size_t n = 0;
    pmt[n++] = 0x02;
    n += 2;  // the section length, set below
    pmt[n++] = 0x00;
    pmt[n++] = 0x01;
    pmt[n++] = 0xc1;
    pmt[n++] = 0x00;
    pmt[n++] = 0x00;
    pmt[n++] = 0xe0 | (RXTSPidVideo >> 8);  // the PCR PID
    pmt[n++] = RXTSPidVideo & 0xff;
    pmt[n++] = 0xf0;
    pmt[n++] = 0x00;
    pmt[n++] = 0x1b;  // H.264
    pmt[n++] = 0xe0 | (RXTSPidVideo >> 8);
    pmt[n++] = RXTSPidVideo & 0xff;
    pmt[n++] = 0xf0;
    pmt[n++] = 0x00;
    size_t sectionLength = n - 3 + 4;  // after the length field, with the CRC
    pmt[1] = 0xb0 | ((sectionLength >> 8) & 0x0f);
    pmt[2] = sectionLength & 0xff;
    [self writeSection:pmt length:n pid:RXTSPidPMT];
}

static void RXWriteTimestamp(uint8_t *p, uint8_t marker, int64_t time) {
    uint64_t t = (uint64_t)time & 0x1ffffffffULL;
    p[0] = (uint8_t)((marker << 4) | (((t >> 30) & 7) << 1) | 1);
    p[1] = (uint8_t)((t >> 22) & 0xff);
    p[2] = (uint8_t)((((t >> 15) & 0x7f) << 1) | 1);
    p[3] = (uint8_t)((t >> 7) & 0xff);
    p[4] = (uint8_t)(((t & 0x7f) << 1) | 1);
}

// Splits one PES packet into transport packets.
- (void)writePES:(NSData *)payload pid:(uint16_t)pid streamId:(uint8_t)streamId
             pts:(int64_t)pts dts:(int64_t)dts isSync:(BOOL)isSync {
    BOOL writeDts = dts != pts;
    uint8_t header[19];
    size_t headerLength = writeDts ? 19 : 14;
    header[0] = 0;
    header[1] = 0;
    header[2] = 1;
    header[3] = streamId;
    size_t pesLength = payload.length + headerLength - 6;
    // A video PES can be longer than 65535 bytes. A length of 0 means "not given".
    if (pesLength > 0xffff || pid == RXTSPidVideo) pesLength = 0;
    header[4] = (uint8_t)(pesLength >> 8);
    header[5] = (uint8_t)(pesLength & 0xff);
    header[6] = 0x80;
    header[7] = writeDts ? 0xc0 : 0x80;
    header[8] = writeDts ? 10 : 5;
    RXWriteTimestamp(header + 9, writeDts ? 3 : 2, pts);
    if (writeDts) RXWriteTimestamp(header + 14, 1, dts);

    const uint8_t *data = payload.bytes;
    size_t total = headerLength + payload.length;
    size_t written = 0;
    BOOL first = YES;
    while (written < total) {
        uint8_t packet[RXTSPacketSize];
        packet[0] = 0x47;
        packet[1] = (first ? 0x40 : 0) | (pid >> 8);
        packet[2] = pid & 0xff;
        size_t position = 4;

        // The adaptation field: the PCR and the random access flag on the
        // first packet of a video PES, and stuffing on the last packet.
        uint8_t adaptation[RXTSPacketSize];
        size_t adaptationLength = 0;
        BOOL writePCR = first && pid == RXTSPidVideo;
        if (writePCR) {
            uint64_t pcr = (uint64_t)(dts < 0 ? 0 : dts);
            adaptation[0] = 0x10 | (isSync ? 0x40 : 0);
            adaptation[1] = (uint8_t)(pcr >> 25);
            adaptation[2] = (uint8_t)((pcr >> 17) & 0xff);
            adaptation[3] = (uint8_t)((pcr >> 9) & 0xff);
            adaptation[4] = (uint8_t)((pcr >> 1) & 0xff);
            adaptation[5] = (uint8_t)(((pcr & 1) << 7) | 0x7e);
            adaptation[6] = 0;
            adaptationLength = 7;
        }
        size_t room = RXTSPacketSize - position - (adaptationLength ? adaptationLength + 1 : 0);
        size_t left = total - written;
        if (left < room) {
            // Stuff the packet, so that the payload fills it to the end.
            size_t stuffing = room - left;
            if (!adaptationLength) {
                // An adaptation field needs its length byte. One byte of
                // room gives an empty field. More bytes give a flags byte and
                // 0xff bytes.
                if (stuffing == 1) {
                    adaptationLength = 0;
                    packet[3] = 0x30 | [self nextContinuityForPid:pid];
                    packet[4] = 0;
                    position = 5;
                    room = 0;
                    stuffing = 0;
                } else {
                    adaptation[0] = 0x00;
                    adaptationLength = 1;
                    stuffing -= 2;
                }
            }
            if (adaptationLength) {
                memset(adaptation + adaptationLength, 0xff, stuffing);
                adaptationLength += stuffing;
            }
        }
        if (position == 4) {
            if (adaptationLength) {
                packet[3] = 0x30 | [self nextContinuityForPid:pid];
                packet[4] = (uint8_t)adaptationLength;
                memcpy(packet + 5, adaptation, adaptationLength);
                position = 5 + adaptationLength;
            } else {
                packet[3] = 0x10 | [self nextContinuityForPid:pid];
            }
        }
        while (position < RXTSPacketSize && written < total) {
            size_t count;
            if (written < headerLength) {
                count = MIN(headerLength - written, RXTSPacketSize - position);
                memcpy(packet + position, header + written, count);
            } else {
                count = MIN(total - written, RXTSPacketSize - position);
                memcpy(packet + position, data + (written - headerLength), count);
            }
            position += count;
            written += count;
        }
        [self.output appendBytes:packet length:RXTSPacketSize];
        first = NO;
    }
}

- (void)writeVideo:(NSData *)annexB pts:(int64_t)pts dts:(int64_t)dts isSync:(BOOL)isSync {
    [self writePES:annexB pid:RXTSPidVideo streamId:0xe0 pts:pts dts:dts isSync:isSync];
}

@end
