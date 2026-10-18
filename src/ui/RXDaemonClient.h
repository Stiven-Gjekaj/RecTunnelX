// Talks to the daemon over HTTP on 127.0.0.1.

#import <Foundation/Foundation.h>

@interface RXDaemonClient : NSObject
// The block gets nil if the daemon does not answer. It runs on the main
// thread.
- (void)fetchStatus:(void (^)(NSDictionary *status))completion;
- (void)control:(NSDictionary *)query completion:(void (^)(NSDictionary *result))completion;
@end
