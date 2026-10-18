// RXTest: a small test runner that operates on macOS and on iOS 6.
// Each test is a function that RX_TEST makes and registers at load time.

#import <Foundation/Foundation.h>

typedef void (*RXTestFunction)(void);

void RXTestRegister(const char *name, RXTestFunction function);
void RXTestFail(const char *file, int line, NSString *message);
void RXTestSkip(void);

#define RX_TEST(name)                                                         \
    static void name(void);                                                   \
    __attribute__((constructor)) static void name##_register(void) {          \
        RXTestRegister(#name, name);                                          \
    }                                                                         \
    static void name(void)

#define RX_EXPECT(condition)                                                  \
    do {                                                                      \
        if (!(condition)) RXTestFail(__FILE__, __LINE__, @"expected: " #condition); \
    } while (0)

#define RX_EQUAL(actual, expected)                                            \
    do {                                                                      \
        id rx_a = (actual), rx_e = (expected);                                \
        if (!(rx_a == rx_e || [rx_a isEqual:rx_e]))                           \
            RXTestFail(__FILE__, __LINE__, [NSString stringWithFormat:        \
                @"%s is <%@>, expected <%@>", #actual, rx_a, rx_e]);           \
    } while (0)

#define RX_EQUAL_INT(actual, expected)                                        \
    do {                                                                      \
        long long rx_a = (long long)(actual), rx_e = (long long)(expected);   \
        if (rx_a != rx_e)                                                     \
            RXTestFail(__FILE__, __LINE__, [NSString stringWithFormat:        \
                @"%s is %lld, expected %lld", #actual, rx_a, rx_e]);           \
    } while (0)

// A live test uses the network. It runs only when RX_LIVE=1 is set.
#define RX_LIVE_ONLY()                                                        \
    do {                                                                      \
        const char *rx_live = getenv("RX_LIVE");                              \
        if (!rx_live || !*rx_live) {                                          \
            RXTestSkip();                                                     \
            return;                                                           \
        }                                                                     \
    } while (0)

// Runs the run loop until done is YES or the time is over.
BOOL RXTestWait(BOOL *done, NSTimeInterval seconds);
