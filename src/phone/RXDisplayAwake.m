#import "RXDisplayAwake.h"
#include <dlfcn.h>

typedef uint32_t RXAssertionID;
typedef int (*RXCreateFn)(CFStringRef type, uint32_t level, CFStringRef name, RXAssertionID *id);
typedef int (*RXReleaseFn)(RXAssertionID id);

@implementation RXDisplayAwake {
    RXCreateFn _create;
    RXReleaseFn _release;
    RXAssertionID _id;
    BOOL _loaded;
}

- (void)load {
    if (_loaded) return;
    _loaded = YES;
    void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    _create = (RXCreateFn)dlsym(iokit, "IOPMAssertionCreateWithName");
    _release = (RXReleaseFn)dlsym(iokit, "IOPMAssertionRelease");
}

- (BOOL)setActive:(BOOL)active {
    [self load];
    if (!_create || !_release) return NO;
    if (active == _active) return _active;
    if (active) {
        // 255 is the "on" level of an assertion. The name shows in pmset.
        int result = _create(CFSTR("PreventUserIdleDisplaySleep"), 255, CFSTR("RecTunnelX"), &_id);
        if (result != 0 || _id == 0) {
            _id = 0;
            return NO;
        }
        _active = YES;
    } else {
        _release(_id);
        _id = 0;
        _active = NO;
    }
    return _active;
}

- (void)dealloc {
    [self setActive:NO];
}

@end
