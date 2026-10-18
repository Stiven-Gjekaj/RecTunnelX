#import "RXTest.h"
#import "RXStreamServer.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

static RXStreamServer *StartServer(void) {
    RXStreamServer *server = [[RXStreamServer alloc] initWithPort:0 loopbackOnly:YES];
    server.requestTimeout = 0.2;
    NSError *error = nil;
    RX_EXPECT([server start:&error]);
    RX_EXPECT(server.port != 0);
    return server;
}

static int Connect(uint16_t port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(port);
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(fd);
        return -1;
    }
    struct timeval timeout = { 2, 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    return fd;
}

static void Send(int fd, NSString *text) {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    write(fd, data.bytes, data.length);
}

// Reads until the connection closes or until length bytes arrive.
static NSData *Read(int fd, NSUInteger length) {
    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[4096];
    while (data.length < length) {
        ssize_t n = read(fd, buffer, MIN(sizeof(buffer), length - data.length));
        if (n <= 0) break;
        [data appendBytes:buffer length:(size_t)n];
    }
    return data;
}

static NSString *Text(NSData *data) {
    return [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
}

// Waits until the server has count stream clients.
static BOOL WaitForClients(RXStreamServer *server, NSUInteger count) {
    for (int i = 0; i < 200 && server.clientCount != count; i++) usleep(10000);
    return server.clientCount == count;
}

static NSData *Bytes(uint8_t value, NSUInteger length) {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    memset(data.mutableBytes, value, length);
    return data;
}

RX_TEST(test_request_parses_path_and_query) {
    RXRequest *request = RXParseRequestHead([@"GET /control?enabled=1&name=a%20b+c HTTP/1.1\r\nHost: x\r\n\r\n"
        dataUsingEncoding:NSUTF8StringEncoding]);
    RX_EQUAL(request.method, @"GET");
    RX_EQUAL(request.path, @"/control");
    RX_EQUAL(request.query[@"enabled"], @"1");
    RX_EQUAL(request.query[@"name"], @"a b c");
}

RX_TEST(test_request_refuses_bad_line) {
    RX_EXPECT(RXParseRequestHead([@"GET /x\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]) == nil);
    RX_EXPECT(RXParseRequestHead([@"GET x HTTP/1.0\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]) == nil);
    RX_EXPECT(RXParseRequestHead([@"\x16\x03\x01 junk" dataUsingEncoding:NSISOLatin1StringEncoding]) == nil);
}

RX_TEST(test_server_http_stream_starts_at_key_frame) {
    RXStreamServer *server = StartServer();
    __block int keyFrameRequests = 0;
    server.needKeyFrame = ^{ keyFrameRequests++; };
    int fd = Connect(server.port);
    RX_EXPECT(fd >= 0);
    Send(fd, @"GET /stream.ts HTTP/1.1\r\nHost: x\r\n\r\n");
    RX_EXPECT(WaitForClients(server, 1));
    [server sendFrame:Bytes(1, 188) isSync:NO];
    [server sendFrame:Bytes(2, 376) isSync:YES];
    [server sendFrame:Bytes(3, 188) isSync:NO];
    NSString *expectedHeader = @"HTTP/1.0 200 OK\r\nContent-Type: video/mp2t\r\nCache-Control: no-cache\r\n"
                               @"Connection: close\r\n\r\n";
    NSData *received = Read(fd, expectedHeader.length + 376 + 188);
    RX_EQUAL_INT(received.length, expectedHeader.length + 376 + 188);
    RX_EQUAL(Text([received subdataWithRange:NSMakeRange(0, expectedHeader.length)]), expectedHeader);
    RX_EQUAL([received subdataWithRange:NSMakeRange(expectedHeader.length, 376)], Bytes(2, 376));
    RX_EQUAL([received subdataWithRange:NSMakeRange(expectedHeader.length + 376, 188)], Bytes(3, 188));
    usleep(50000);
    RX_EXPECT(keyFrameRequests >= 1);
    close(fd);
    RX_EXPECT(WaitForClients(server, 0));
    [server stop];
}

RX_TEST(test_server_raw_stream_when_client_is_silent) {
    RXStreamServer *server = StartServer();
    int fd = Connect(server.port);
    RX_EXPECT(fd >= 0);
    RX_EXPECT(WaitForClients(server, 1));
    [server sendFrame:Bytes(7, 188) isSync:YES];
    RX_EQUAL(Read(fd, 188), Bytes(7, 188));
    close(fd);
    [server stop];
}

RX_TEST(test_server_reports_client_count) {
    RXStreamServer *server = StartServer();
    NSMutableArray *counts = [NSMutableArray array];
    server.clientsChanged = ^(NSUInteger count) {
        @synchronized (counts) {
            [counts addObject:@(count)];
        }
    };
    int a = Connect(server.port);
    int b = Connect(server.port);
    RX_EXPECT(WaitForClients(server, 2));
    close(a);
    RX_EXPECT(WaitForClients(server, 1));
    close(b);
    RX_EXPECT(WaitForClients(server, 0));
    usleep(50000);
    @synchronized (counts) {
        RX_EQUAL(counts, (@[ @1, @2, @1, @0 ]));
    }
    [server stop];
}

RX_TEST(test_server_status_is_json) {
    RXStreamServer *server = StartServer();
    server.status = ^NSDictionary *{ return @{ @"streaming": @YES, @"clients": @0 }; };
    int fd = Connect(server.port);
    Send(fd, @"GET /status HTTP/1.1\r\n\r\n");
    NSString *response = Text(Read(fd, 4096));
    RX_EXPECT([response hasPrefix:@"HTTP/1.0 200 OK\r\n"]);
    RX_EXPECT([response rangeOfString:@"Content-Type: application/json"].location != NSNotFound);
    NSString *body = [response substringFromIndex:[response rangeOfString:@"\r\n\r\n"].location + 4];
    NSDictionary *object = [NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                           options:0 error:NULL];
    RX_EQUAL(object[@"streaming"], @YES);
    close(fd);
    [server stop];
}

RX_TEST(test_server_control_gets_query) {
    RXStreamServer *server = StartServer();
    __block NSDictionary *seen = nil;
    server.control = ^NSDictionary *(NSDictionary *query) {
        seen = query;
        return @{ @"enabled": query[@"enabled"] };
    };
    int fd = Connect(server.port);
    Send(fd, @"GET /control?enabled=0 HTTP/1.1\r\n\r\n");
    NSString *response = Text(Read(fd, 4096));
    RX_EXPECT([response hasPrefix:@"HTTP/1.0 200 OK\r\n"]);
    RX_EQUAL(seen[@"enabled"], @"0");
    close(fd);
    [server stop];
}

RX_TEST(test_server_unknown_path_is_404) {
    RXStreamServer *server = StartServer();
    int fd = Connect(server.port);
    Send(fd, @"GET /nothing HTTP/1.1\r\n\r\n");
    RX_EXPECT([Text(Read(fd, 4096)) hasPrefix:@"HTTP/1.0 404 Not Found\r\n"]);
    close(fd);
    RX_EQUAL_INT(server.clientCount, 0);
    [server stop];
}

RX_TEST(test_server_slow_client_waits_for_next_key_frame) {
    RXStreamServer *server = StartServer();
    server.maxPendingBytes = 1000;
    int fd = Connect(server.port);
    RX_EXPECT(WaitForClients(server, 1));
    // The first frame is larger than the limit, so the client does not get
    // it. It waits for the next key frame.
    [server sendFrame:Bytes(1, 2000) isSync:YES];
    [server sendFrame:Bytes(2, 188) isSync:NO];
    [server sendFrame:Bytes(3, 188) isSync:YES];
    RX_EQUAL(Read(fd, 188), Bytes(3, 188));
    close(fd);
    [server stop];
}
