// awake: hold a power assertion that stops the display from idle sleep, then
// wait. Use it to see if the phone stays awake while the assertion is held.
// Usage: awake SECONDS
// The functions come from dlsym, so the probe shows if iOS 6 has them.

#import <Foundation/Foundation.h>
#include <dlfcn.h>

typedef uint32_t RXAssertionID;
typedef int (*RXCreate)(CFStringRef type, uint32_t level, CFStringRef name, RXAssertionID *id);
typedef int (*RXRelease)(RXAssertionID id);

int main(int argc, char **argv) {
    @autoreleasepool {
        int seconds = argc > 1 ? atoi(argv[1]) : 60;
        void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        if (!iokit) {
            fprintf(stderr, "awake: no IOKit: %s\n", dlerror());
            return 1;
        }
        RXCreate create = (RXCreate)dlsym(iokit, "IOPMAssertionCreateWithName");
        RXRelease release = (RXRelease)dlsym(iokit, "IOPMAssertionRelease");
        printf("IOPMAssertionCreateWithName %s\n", create ? "yes" : "NO");
        printf("IOPMAssertionRelease %s\n", release ? "yes" : "NO");
        if (!create || !release) return 1;

        // Try both assertion types that stop display sleep.
        const char *types[] = { "PreventUserIdleDisplaySleep", "NoDisplaySleep" };
        RXAssertionID held = 0;
        const char *heldType = NULL;
        for (int i = 0; i < 2; i++) {
            RXAssertionID id = 0;
            CFStringRef type = CFStringCreateWithCString(NULL, types[i], kCFStringEncodingUTF8);
            int result = create(type, 255, CFSTR("RecTunnelX"), &id);
            CFRelease(type);
            printf("%s: result=%d id=%u\n", types[i], result, id);
            if (result == 0 && id != 0 && !held) {
                held = id;
                heldType = types[i];
            } else if (result == 0 && id != 0) {
                release(id);
            }
        }
        if (!held) {
            fprintf(stderr, "awake: no assertion was made\n");
            return 1;
        }
        printf("held %s for %d seconds\n", heldType, seconds);
        fflush(stdout);
        sleep(seconds);
        release(held);
        printf("released\n");
    }
    return 0;
}
