// net: try a TCP connection from the phone, to test the network.
// Usage: net HOST PORT

#import <Foundation/Foundation.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: net HOST PORT\n");
        return 2;
    }
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons((uint16_t)atoi(argv[2]));
    inet_pton(AF_INET, argv[1], &address.sin_addr);
    fcntl(fd, F_SETFL, O_NONBLOCK);
    connect(fd, (struct sockaddr *)&address, sizeof(address));
    fd_set set;
    FD_ZERO(&set);
    FD_SET(fd, &set);
    struct timeval timeout = { 4, 0 };
    int ready = select(fd + 1, NULL, &set, NULL, &timeout);
    int error = 0;
    socklen_t length = sizeof(error);
    getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length);
    if (ready <= 0) printf("%s:%s: timeout\n", argv[1], argv[2]);
    else if (error) printf("%s:%s: %s\n", argv[1], argv[2], strerror(error));
    else printf("%s:%s: connected\n", argv[1], argv[2]);
    close(fd);
    return 0;
}
