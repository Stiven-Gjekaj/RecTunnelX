#import "RXDaemonClient.h"
#import "RXSettings.h"

@implementation RXDaemonClient

- (void)get:(NSString *)path completion:(void (^)(NSDictionary *))completion {
    NSString *text = [NSString stringWithFormat:@"http://127.0.0.1:%d%@", RXDefaultPort, path];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:text]
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:3];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        NSDictionary *object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        completion([object isKindOfClass:[NSDictionary class]] ? object : nil);
    }];
}

- (void)fetchStatus:(void (^)(NSDictionary *))completion {
    [self get:@"/status" completion:completion];
}

- (void)control:(NSDictionary *)query completion:(void (^)(NSDictionary *))completion {
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *key in query) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, query[key]]];
    }
    [self get:[@"/control?" stringByAppendingString:[pairs componentsJoinedByString:@"&"]] completion:completion];
}

@end
