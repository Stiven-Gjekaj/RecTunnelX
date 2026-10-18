// rectunnelxd: the daemon of RecTunnelX. launchd starts it as root.
// Usage: rectunnelxd [PORT]

#import <Foundation/Foundation.h>
#import "RXSettings.h"
#import "RXStreamer.h"

static NSString *const RXSettingsPath = @"/var/mobile/Library/Preferences/io.github.stivengjekaj.rectunnelx.plist";
static NSString *const RXLogPath = @"/var/mobile/Library/Caches/RecTunnelX/daemon.log";

int main(int argc, char **argv) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        uint16_t port = argc > 1 ? (uint16_t)atoi(argv[1]) : RXDefaultPort;
        RXLogOpen(RXLogPath);
        RXStreamer *streamer = [[RXStreamer alloc] initWithSettingsPath:RXSettingsPath port:port];
        NSString *error = [streamer start];
        if (error) {
            RXLog(@"start: %@", error);
            fprintf(stderr, "rectunnelxd: %s\n", error.UTF8String);
            // Wait before the exit, so that launchd does not start the daemon
            // again at once.
            sleep(10);
            return 1;
        }
        dispatch_main();
    }
    return 0;
}
