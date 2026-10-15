#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <sys/select.h>

int main() {
    setbuf(stdout, NULL);
    signal(SIGPIPE, SIG_IGN);

    // Create master
    int master = posix_openpt(O_RDWR | O_NOCTTY);
    if (master < 0) { perror("posix_openpt"); return 1; }
    if (grantpt(master) < 0) { perror("grantpt"); return 1; }
    if (unlockpt(master) < 0) { perror("unlockpt"); return 1; }

    const char *slave_name = ptsname(master);
    printf("Slave PTY: %s\n", slave_name);

    // Open slave with O_NOCTTY — keeps the PTY alive for writes
    // but does NOT make it our controlling terminal, so screen can claim it
    int slave = open(slave_name, O_RDWR | O_NOCTTY);
    if (slave < 0) { perror("open slave"); return 1; }
    printf("Slave fd: %d (held open with O_NOCTTY)\n", slave);

    printf("Connect with: screen %s\n", slave_name);
    printf("Sending a dot every second. Type to echo.\n");

    // Raw mode on master
    struct termios tty;
    if (tcgetattr(master, &tty) == 0) {
        cfmakeraw(&tty);
        tcsetattr(master, TCSANOW, &tty);
    }

    // Non-blocking master
    fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK);

    for (int i = 0; i < 60; i++) {
        // Try to write a dot
        char dot = '.';
        ssize_t w = write(master, &dot, 1);
        if (w == 1) {
            printf("[sent dot]\n");
        } else {
            printf("[write: %s]\n", strerror(errno));
        }

        // Check for input
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(master, &fds);
        struct timeval tv = {1, 0};
        int r = select(master + 1, &fds, NULL, NULL, &tv);
        if (r > 0) {
            char buf[64];
            ssize_t n = read(master, buf, sizeof(buf));
            if (n > 0) {
                printf("[received %zd bytes: ", n);
                for (int j = 0; j < n; j++) printf("0x%02x ", (unsigned char)buf[j]);
                printf("]\n");
                // Echo back
                write(master, buf, n);
            } else if (n == 0) {
                printf("[EOF on master]\n");
            } else {
                printf("[read: %s]\n", strerror(errno));
            }
        }
    }

    close(slave);
    close(master);
    return 0;
}
