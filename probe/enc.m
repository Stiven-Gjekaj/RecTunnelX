// enc: capture the screen, encode it to H.264 with the hardware encoder, and
// write an MPEG-TS file.
// Usage: enc OUTPUT.ts [SECONDS] [FPS] [BITRATE] [bgra|420v]

#import <Foundation/Foundation.h>
#import "RXScreen.h"
#import "RXEncoder.h"
#import "RXTS.h"
#include <mach/mach_time.h>

static int64_t now90k(void) {
    static mach_timebase_info_data_t base;
    if (base.denom == 0) mach_timebase_info(&base);
    return (int64_t)((double)mach_absolute_time() * base.numer / base.denom / 1e9 * 90000);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: enc OUTPUT.ts [SECONDS] [FPS] [BITRATE] [bgra|420v]\n");
            return 2;
        }
        int seconds = argc > 2 ? atoi(argv[2]) : 10;
        int fps = argc > 3 ? atoi(argv[3]) : 30;
        int bitrate = argc > 4 ? atoi(argv[4]) : 3000000;
        BOOL yuv = argc > 5 && strcmp(argv[5], "420v") == 0;

        NSString *error = nil;
        RXScreen *screen = [RXScreen screenWithError:&error];
        if (!screen) {
            fprintf(stderr, "enc: %s\n", error.UTF8String);
            return 1;
        }
        int width = (int)screen.width, height = (int)screen.height;

        RXTSWriter *writer = [RXTSWriter new];
        __block int frames = 0, keyFrames = 0;
        __block int64_t firstPts = -1;
        __block size_t bytes = 0;
        __block int64_t encodeDelay = 0;
        NSObject *lock = [NSObject new];
        RXEncoder *encoder = [[RXEncoder alloc] initWithWidth:width height:height framesPerSecond:fps
            bitsPerSecond:bitrate output:^(NSData *annexB, int64_t pts, BOOL isSync) {
                @synchronized (lock) {
                    if (firstPts < 0) firstPts = pts;
                    int64_t t = pts - firstPts + 90000;
                    if (frames % (fps * 2) == 0) [writer writeTables];
                    [writer writeVideo:annexB pts:t dts:t isSync:isSync];
                    frames++;
                    if (isSync) keyFrames++;
                    bytes += annexB.length;
                    encodeDelay += now90k() - pts;
                }
            }];
        error = [encoder start];
        for (NSString *line in encoder.propertyLog) printf("property %s\n", line.UTF8String);
        if (error) {
            fprintf(stderr, "enc: %s\n", error.UTF8String);
            return 1;
        }

        NSDictionary *attributes = @{
            (id)kCVPixelBufferWidthKey: @(width),
            (id)kCVPixelBufferHeightKey: @(height),
            (id)kCVPixelBufferPixelFormatTypeKey: @(yuv ? kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                                                        : kCVPixelFormatType_32BGRA),
            (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        };
        CVPixelBufferPoolRef pool = NULL;
        CVPixelBufferPoolCreate(NULL, NULL, (__bridge CFDictionaryRef)attributes, &pool);

        int submitted = 0, copyFailed = 0, encodeFailed = 0;
        uint64_t start = mach_absolute_time();
        int64_t startPts = now90k();
        for (int i = 0; i < seconds * fps; i++) {
            // Wait for the time of this frame.
            int64_t due = startPts + (int64_t)i * 90000 / fps;
            while (now90k() < due) usleep(1000);
            @autoreleasepool {
                CVPixelBufferRef buffer = NULL;
                if (CVPixelBufferPoolCreatePixelBuffer(NULL, pool, &buffer) != 0) {
                    copyFailed++;
                    continue;
                }
                BOOL copied = [screen copyToPixelBuffer:buffer];
                if (copied && i == 0) {
                    // Print the mean of the first plane, to see if the copy is black.
                    CVPixelBufferLockBaseAddress(buffer, 0);
                    BOOL planar = CVPixelBufferIsPlanar(buffer);
                    const uint8_t *base = planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, 0)
                                                 : CVPixelBufferGetBaseAddress(buffer);
                    size_t rowBytes = planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
                                             : CVPixelBufferGetBytesPerRow(buffer);
                    unsigned long long sum = 0;
                    for (int y = 0; y < height; y += 8) {
                        for (size_t x = 0; x < rowBytes; x += 4) sum += base[y * rowBytes + x];
                    }
                    printf("first frame: mean %.1f\n", (double)sum / ((height / 8) * (rowBytes / 4)));
                    CVPixelBufferUnlockBaseAddress(buffer, 0);
                }
                if (!copied) copyFailed++;
                else if (![encoder encode:buffer pts90k:now90k()]) encodeFailed++;
                else submitted++;
                CVPixelBufferRelease(buffer);
            }
        }
        [encoder stop];
        double elapsed = (double)(mach_absolute_time() - start);
        mach_timebase_info_data_t base;
        mach_timebase_info(&base);
        elapsed = elapsed * base.numer / base.denom / 1e9;

        @synchronized (lock) {
            printf("%dx%d %s: submitted %d, copy failed %d, encode failed %d\n", width, height,
                yuv ? "420v" : "bgra", submitted, copyFailed, encodeFailed);
            printf("encoded %d frames (%d key) in %.2f s = %.1f fps, %.0f kbit/s\n", frames, keyFrames,
                elapsed, frames / elapsed, bytes * 8 / elapsed / 1000);
            if (![writer.output writeToFile:@(argv[1]) atomically:YES]) {
                fprintf(stderr, "enc: cannot write %s\n", argv[1]);
                return 1;
            }
            if (frames > 0) printf("encoder delay: mean %.1f ms\n", encodeDelay / 90.0 / frames);
            printf("wrote %s: %lu bytes\n", argv[1], (unsigned long)writer.output.length);
        }
        CVPixelBufferPoolRelease(pool);
    }
    return 0;
}
