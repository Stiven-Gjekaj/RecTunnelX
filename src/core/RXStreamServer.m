#import "RXStreamServer.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>

// The longest request head that the server reads.
static const size_t RXMaxRequestHead = 8192;

@interface RXRequest ()
@property (nonatomic, strong) NSString *method;
@property (nonatomic, strong) NSString *path;
@property (nonatomic, strong) NSDictionary *query;
@end

@implementation RXRequest
@end

static NSString *RXDecode(NSString *text) {
    NSString *spaced = [text stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    return [spaced stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: spaced;
}

RXRequest *RXParseRequestHead(NSData *head) {
    NSString *text = [[NSString alloc] initWithData:head encoding:NSISOLatin1StringEncoding];
    NSRange end = [text rangeOfString:@"\r\n"];
    NSString *line = end.location == NSNotFound ? text : [text substringToIndex:end.location];
    NSArray *parts = [line componentsSeparatedByString:@" "];
    if (parts.count != 3 || ![parts[2] hasPrefix:@"HTTP/"] || [parts[0] length] == 0 ||
        ![parts[1] hasPrefix:@"/"]) {
        return nil;
    }
    RXRequest *request = [RXRequest new];
    request.method = parts[0];
    NSString *target = parts[1];
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    NSRange mark = [target rangeOfString:@"?"];
    if (mark.location != NSNotFound) {
        for (NSString *pair in [[target substringFromIndex:mark.location + 1] componentsSeparatedByString:@"&"]) {
            if (pair.length == 0) continue;
            NSRange equals = [pair rangeOfString:@"="];
            NSString *key = equals.location == NSNotFound ? pair : [pair substringToIndex:equals.location];
            NSString *value = equals.location == NSNotFound ? @"" : [pair substringFromIndex:equals.location + 1];
            query[RXDecode(key)] = RXDecode(value);
        }
        target = [target substringToIndex:mark.location];
    }
    request.path = target;
    request.query = query;
    return request;
}

// Writes all bytes. Returns NO if the connection fails.
static BOOL RXWriteAll(int fd, const void *bytes, size_t length) {
    const uint8_t *p = bytes;
    while (length > 0) {
        ssize_t n = write(fd, p, length);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return NO;
        p += n;
        length -= (size_t)n;
    }
    return YES;
}

@interface RXStreamClient : NSObject
@property (nonatomic) int fd;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic) NSUInteger pending;  // Guarded by the clients array of the server
@property (nonatomic) BOOL waitingForSync;  // Guarded by the clients array of the server
@property (nonatomic) BOOL closed;  // Guarded by the clients array of the server
@property (nonatomic, strong) dispatch_source_t watch;
@end

@implementation RXStreamClient
@end

@interface RXStreamServer ()
@property (nonatomic) uint16_t port;
@property (nonatomic) BOOL loopbackOnly;
@property (nonatomic) int listenSocket;
@property (nonatomic, strong) dispatch_source_t acceptSource;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) dispatch_queue_t eventQueue;
@property (nonatomic, strong) NSMutableArray *clients;
@end

@implementation RXStreamServer

- (instancetype)initWithPort:(uint16_t)port loopbackOnly:(BOOL)loopbackOnly {
    if ((self = [super init])) {
        _port = port;
        _loopbackOnly = loopbackOnly;
        _listenSocket = -1;
        _maxPendingBytes = 4 << 20;
        _requestTimeout = 0.7;
        _clients = [NSMutableArray array];
        _queue = dispatch_queue_create("RXStreamServer.accept", DISPATCH_QUEUE_SERIAL);
        _eventQueue = dispatch_queue_create("RXStreamServer.events", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSUInteger)clientCount {
    @synchronized (self.clients) {
        return self.clients.count;
    }
}

- (BOOL)start:(NSError **)error {
    if (self.listenSocket >= 0) return YES;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return NO;
    }
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(self.loopbackOnly ? INADDR_LOOPBACK : INADDR_ANY);
    address.sin_port = htons(self.port);
    socklen_t length = sizeof(address);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(fd, 16) != 0 ||
        getsockname(fd, (struct sockaddr *)&address, &length) != 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        close(fd);
        return NO;
    }
    self.listenSocket = fd;
    self.port = ntohs(address.sin_port);
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, self.queue);
    __weak RXStreamServer *weakSelf = self;
    dispatch_source_set_event_handler(source, ^{
        struct sockaddr_in peer;
        socklen_t peerLength = sizeof(peer);
        int client = accept(fd, (struct sockaddr *)&peer, &peerLength);
        if (client < 0) return;
        int on = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
        setsockopt(client, IPPROTO_TCP, TCP_NODELAY, &on, sizeof(on));
        BOOL local = peer.sin_family == AF_INET && ntohl(peer.sin_addr.s_addr) == INADDR_LOOPBACK;
        // The request can wait for the network, so it has its own thread.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            RXStreamServer *server = weakSelf;
            if (server) [server serve:client local:local];
            else close(client);
        });
    });
    dispatch_source_set_cancel_handler(source, ^{ close(fd); });
    self.acceptSource = source;
    dispatch_resume(source);
    return YES;
}

- (void)stop {
    if (self.acceptSource) dispatch_source_cancel(self.acceptSource);
    self.acceptSource = nil;
    self.listenSocket = -1;
    NSArray *clients;
    @synchronized (self.clients) {
        clients = [self.clients copy];
    }
    for (RXStreamClient *client in clients) [self dropClient:client];
}

// Reads the request head. Returns an empty object if the client sends
// nothing before the timeout, and nil if the connection fails.
- (NSData *)readHead:(int)fd {
    struct timeval timeout;
    timeout.tv_sec = (long)self.requestTimeout;
    timeout.tv_usec = (int)((self.requestTimeout - timeout.tv_sec) * 1e6);
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    NSMutableData *head = [NSMutableData data];
    uint8_t buffer[1024];
    while (head.length < RXMaxRequestHead) {
        ssize_t n = read(fd, buffer, sizeof(buffer));
        if (n < 0 && errno == EINTR) continue;
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return head.length == 0 ? head : nil;
        if (n <= 0) return nil;
        [head appendBytes:buffer length:(size_t)n];
        if ([head rangeOfData:[NSData dataWithBytes:"\r\n\r\n" length:4] options:0
                        range:NSMakeRange(0, head.length)].location != NSNotFound) {
            break;
        }
    }
    return head;
}

- (void)respond:(int)fd status:(NSString *)status type:(NSString *)type body:(NSData *)body {
    NSString *header = [NSString stringWithFormat:@"HTTP/1.0 %@\r\nContent-Type: %@\r\nContent-Length: %lu\r\n"
                                                  @"Access-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n",
                                                  status, type, (unsigned long)body.length];
    NSData *headerData = [header dataUsingEncoding:NSUTF8StringEncoding];
    if (RXWriteAll(fd, headerData.bytes, headerData.length)) RXWriteAll(fd, body.bytes, body.length);
    close(fd);
}

- (void)respondJSON:(int)fd object:(NSDictionary *)object {
    NSData *body = object ? [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL] : nil;
    if (!body) {
        [self respond:fd status:@"400 Bad Request" type:@"text/plain" body:[@"bad request\n" dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }
    [self respond:fd status:@"200 OK" type:@"application/json" body:body];
}

- (void)serve:(int)fd local:(BOOL)local {
    NSData *head = [self readHead:fd];
    if (!head) {
        close(fd);
        return;
    }
    if (head.length == 0) {
        [self addStreamClient:fd header:nil];
        return;
    }
    RXRequest *request = RXParseRequestHead(head);
    if (!request || ![request.method isEqualToString:@"GET"]) {
        [self respond:fd status:@"400 Bad Request" type:@"text/plain" body:[@"bad request\n" dataUsingEncoding:NSUTF8StringEncoding]];
        return;
    }
    if ([request.path isEqualToString:@"/stream.ts"]) {
        NSString *header = @"HTTP/1.0 200 OK\r\nContent-Type: video/mp2t\r\nCache-Control: no-cache\r\n"
                           @"Connection: close\r\n\r\n";
        [self addStreamClient:fd header:[header dataUsingEncoding:NSUTF8StringEncoding]];
    } else if ([request.path isEqualToString:@"/status"]) {
        NSDictionary *(^status)(void) = self.status;
        [self respondJSON:fd object:status ? status() : @{}];
    } else if ([request.path isEqualToString:@"/control"]) {
        NSDictionary *(^control)(NSDictionary *) = self.control;
        if (!local) {
            [self respond:fd status:@"403 Forbidden" type:@"text/plain" body:[@"only from this device\n" dataUsingEncoding:NSUTF8StringEncoding]];
        } else {
            [self respondJSON:fd object:control ? control(request.query) : nil];
        }
    } else {
        [self respond:fd status:@"404 Not Found" type:@"text/plain" body:[@"not found\n" dataUsingEncoding:NSUTF8StringEncoding]];
    }
}

// Call it while the clients array is locked, so that the events keep their order.
- (void)notifyClients:(NSUInteger)count {
    void (^changed)(NSUInteger) = self.clientsChanged;
    if (changed) dispatch_async(self.eventQueue, ^{ changed(count); });
}

- (void)notifyKeyFrame {
    void (^need)(void) = self.needKeyFrame;
    if (need) dispatch_async(self.eventQueue, ^{ need(); });
}

- (void)addStreamClient:(int)fd header:(NSData *)header {
    if (header && !RXWriteAll(fd, header.bytes, header.length)) {
        close(fd);
        return;
    }
    // A send that waits for more than 3 seconds ends the connection.
    struct timeval timeout = { 3, 0 };
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    RXStreamClient *client = [RXStreamClient new];
    client.fd = fd;
    client.queue = dispatch_queue_create("RXStreamServer.client", DISPATCH_QUEUE_SERIAL);
    client.waitingForSync = YES;
    // Watch the socket for the end of the connection. A stream client sends
    // nothing more, so a read of 0 bytes means that it closed.
    dispatch_source_t watch = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, client.queue);
    __weak RXStreamServer *weakSelf = self;
    __weak dispatch_source_t weakWatch = watch;
    dispatch_source_set_event_handler(watch, ^{
        uint8_t buffer[512];
        ssize_t n = recv(fd, buffer, sizeof(buffer), MSG_DONTWAIT);
        if (n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR)) {
            dispatch_source_cancel(weakWatch);
            [weakSelf dropClient:client];
        }
    });
    client.watch = watch;
    @synchronized (self.clients) {
        [self.clients addObject:client];
        [self notifyClients:self.clients.count];
    }
    dispatch_resume(watch);
    [self notifyKeyFrame];
}

- (void)dropClient:(RXStreamClient *)client {
    @synchronized (self.clients) {
        if (client.closed) return;
        client.closed = YES;
        [self.clients removeObject:client];
        [self notifyClients:self.clients.count];
    }
    if (client.watch) dispatch_source_cancel(client.watch);
    dispatch_async(client.queue, ^{ close(client.fd); });
}

- (void)sendFrame:(NSData *)bytes isSync:(BOOL)isSync {
    NSArray *clients;
    @synchronized (self.clients) {
        clients = [self.clients copy];
    }
    BOOL wantKeyFrame = NO;
    for (RXStreamClient *client in clients) {
        @synchronized (self.clients) {
            if (client.closed) continue;
            if (client.waitingForSync && !isSync) continue;
            if (client.pending + bytes.length > self.maxPendingBytes) {
                client.waitingForSync = YES;
                wantKeyFrame = YES;
                continue;
            }
            client.waitingForSync = NO;
            client.pending += bytes.length;
        }
        dispatch_async(client.queue, ^{
            BOOL ok = RXWriteAll(client.fd, bytes.bytes, bytes.length);
            @synchronized (self.clients) {
                client.pending -= bytes.length;
            }
            if (!ok) [self dropClient:client];
        });
    }
    if (wantKeyFrame) [self notifyKeyFrame];
}

@end
