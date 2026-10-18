// A TCP server that sends one live MPEG-TS stream to each client.
//
// A client can ask with HTTP:
//   GET /stream.ts  the live stream
//   GET /status     a JSON object from the status block
//   GET /control?KEY=VALUE  calls the control block (only from 127.0.0.1)
// A client that sends nothing for a short time gets the live stream with no
// HTTP header. OBS reads this form with the input "tcp://HOST:PORT".
//
// A new client starts at the next key frame. A client that cannot read fast
// enough loses frames until the next key frame.

#import <Foundation/Foundation.h>

// The result of RXParseRequestHead.
@interface RXRequest : NSObject
@property (nonatomic, readonly) NSString *method;
@property (nonatomic, readonly) NSString *path;  // With no query
@property (nonatomic, readonly) NSDictionary *query;  // NSString keys and values
@end

// Parses the first line of an HTTP request head. Returns nil if the line is
// not "METHOD TARGET HTTP/x.y".
RXRequest *RXParseRequestHead(NSData *head);

@interface RXStreamServer : NSObject

// The port that the server listens on. Port 0 at init makes the system
// pick a free port. After start, this property holds the real port.
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) NSUInteger clientCount;
// A client loses frames when more than this number of bytes wait for it.
// The default is 4 MB.
@property (nonatomic) NSUInteger maxPendingBytes;
// The time that the server waits for an HTTP request before it sends the
// raw stream. The default is 0.7 seconds.
@property (nonatomic) NSTimeInterval requestTimeout;

// These blocks run on a queue of the server.
// Runs when the number of stream clients changes.
@property (nonatomic, copy) void (^clientsChanged)(NSUInteger count);
// Runs when a client waits for a key frame.
@property (nonatomic, copy) void (^needKeyFrame)(void);
// Gives the object for GET /status.
@property (nonatomic, copy) NSDictionary *(^status)(void);
// Handles GET /control. Returns the object for the response, or nil for an
// error.
@property (nonatomic, copy) NSDictionary *(^control)(NSDictionary *query);

// loopbackOnly YES accepts only connections from this device.
- (instancetype)initWithPort:(uint16_t)port loopbackOnly:(BOOL)loopbackOnly;
- (BOOL)start:(NSError **)error;
- (void)stop;

// Sends the MPEG-TS bytes of one frame to each stream client. A key frame
// must start with the PAT and the PMT.
- (void)sendFrame:(NSData *)bytes isSync:(BOOL)isSync;

@end
