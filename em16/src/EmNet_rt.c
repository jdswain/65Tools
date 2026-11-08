/* EmNet_rt.c - the network under em16's ENC424J600 (EmEth.Mod): the
   Ethernet frames it sends and receives, on the host. Its functions
   override the weak stubs of EmHost.Mod, as EmHost_rt.c's do.

   -net vmnet          macOS's vmnet.framework, shared mode: the guest on a
                       private network (192.168.64.0/24, the host its
                       gateway), with DHCP, DNS and NAT to the host's own.
                       Needs root (sudo), or the com.apple.vm.networking
                       entitlement.
   -net vmnet-host     host-only mode: the host and other guests, no NAT.
   -net vmnet-bridged:en0
                       bridged onto the host interface en0: the guest on the
                       host's own network, as a machine of its own.
   -net udp:LPORT:RPORT[:HOST]
                       frames as UDP datagrams, one frame a datagram,
                       received on port LPORT and sent to HOST (127.0.0.1)
                       port RPORT: no privileges, for tests (a peer in
                       Python) and two em16s joined (each one's RPORT the
                       other's LPORT). QEMU's -netdev dgram does the same.

   Frames come in on vmnet's dispatch queue or a nonblocking socket and wait
   in a ring until the emulator takes them (NetRecv), without their CRC. */

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include <dispatch/dispatch.h>
#include <vmnet/vmnet.h>

#define MAXFRAME 1536
#define RING 64

enum { NONE, VMNET, UDP };
static int kind = NONE;

/* the frames received, waiting */
static uint8_t ring[RING][MAXFRAME];
static int ringLen[RING];
static int head, tail;            /* taken from head, put at tail */
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static long dropped;

static void put(const uint8_t *f, int n) {
    pthread_mutex_lock(&lock);
    if ((tail + 1) % RING == head || n > MAXFRAME) dropped++;
    else { memcpy(ring[tail], f, (size_t)n); ringLen[tail] = n; tail = (tail + 1) % RING; }
    pthread_mutex_unlock(&lock);
}

/* --- UDP --- */

static int sock = -1;
static struct sockaddr_in peer;

static int udpOpen(const char *arg) {
    int lport = 0, rport = 0;
    char host[256] = "127.0.0.1";
    struct sockaddr_in me;
    if (sscanf(arg, "%d:%d:%255s", &lport, &rport, host) < 2) return 0;
    sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) return 0;
    memset(&me, 0, sizeof me);
    me.sin_family = AF_INET; me.sin_port = htons((uint16_t)lport);
    me.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (strcmp(host, "127.0.0.1") != 0) me.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(sock, (struct sockaddr *)&me, sizeof me) < 0) { perror("em16: -net udp"); close(sock); sock = -1; return 0; }
    memset(&peer, 0, sizeof peer);
    peer.sin_family = AF_INET; peer.sin_port = htons((uint16_t)rport);
    if (inet_pton(AF_INET, host, &peer.sin_addr) != 1) { close(sock); sock = -1; return 0; }
    fcntl(sock, F_SETFL, fcntl(sock, F_GETFL) | O_NONBLOCK);
    return 1;
}

static void udpPoll(void) {
    uint8_t f[MAXFRAME];
    ssize_t n;
    while ((n = recv(sock, f, sizeof f, 0)) > 0) put(f, (int)n);
}

/* --- vmnet --- */

static interface_ref iface;
static dispatch_queue_t queue;
static size_t maxPacket = MAXFRAME;

static void vmnetRead(void) {
    uint8_t buf[MAXFRAME * 8];
    struct vmpktdesc pkts[8];
    struct iovec iov[8];
    int i, count;
    for (;;) {
        count = 8;
        for (i = 0; i < count; i++) {
            iov[i].iov_base = buf + i * MAXFRAME; iov[i].iov_len = MAXFRAME;
            pkts[i].vm_pkt_size = MAXFRAME; pkts[i].vm_pkt_iov = &iov[i];
            pkts[i].vm_pkt_iovcnt = 1; pkts[i].vm_flags = 0;
        }
        if (vmnet_read(iface, pkts, &count) != VMNET_SUCCESS || count == 0) return;
        for (i = 0; i < count; i++) put(buf + i * MAXFRAME, (int)pkts[i].vm_pkt_size);
    }
}

static int vmnetOpen(const char *arg) {
    xpc_object_t desc = xpc_dictionary_create(NULL, NULL, 0);
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block vmnet_return_t status = VMNET_FAILURE;
    uint64_t mode = VMNET_SHARED_MODE;
    if (strcmp(arg, "vmnet-host") == 0) mode = VMNET_HOST_MODE;
    else if (strncmp(arg, "vmnet-bridged:", 14) == 0) {
        mode = VMNET_BRIDGED_MODE;
        xpc_dictionary_set_string(desc, vmnet_shared_interface_name_key, arg + 14);
    } else if (strcmp(arg, "vmnet") != 0) return 0;
    xpc_dictionary_set_uint64(desc, vmnet_operation_mode_key, mode);
    xpc_dictionary_set_bool(desc, vmnet_allocate_mac_address_key, false);
    queue = dispatch_queue_create("em16.vmnet", DISPATCH_QUEUE_SERIAL);
    iface = vmnet_start_interface(desc, queue, ^(vmnet_return_t s, xpc_object_t param) {
        status = s;
        if (s == VMNET_SUCCESS && param)
            maxPacket = (size_t)xpc_dictionary_get_uint64(param, vmnet_max_packet_size_key);
        dispatch_semaphore_signal(done);
    });
    if (!iface) { fprintf(stderr, "em16: -net %s: vmnet would not start (run em16 with sudo)\n", arg); return 0; }
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    if (status != VMNET_SUCCESS) {
        fprintf(stderr, "em16: -net %s: vmnet failed (%d)%s\n", arg, (int)status,
                status == VMNET_FAILURE ? "; it needs root: run em16 with sudo" : "");
        return 0;
    }
    vmnet_interface_set_event_callback(iface, VMNET_INTERFACE_PACKETS_AVAILABLE, queue,
        ^(interface_event_t e, xpc_object_t ev) { (void)e; (void)ev; vmnetRead(); });
    return 1;
}

/* --- EmHost's --- */

/* 1 if the network spec could be opened */
int EmHost__NetOpen(const char *spec, int len) {
    char s[512];
    int n = 0;
    while (n < len && n < (int)sizeof(s) - 1 && spec[n]) { s[n] = spec[n]; n++; }
    s[n] = 0;
    if (strncmp(s, "udp:", 4) == 0) { if (udpOpen(s + 4)) { kind = UDP; return 1; } }
    else if (strncmp(s, "vmnet", 5) == 0) { if (vmnetOpen(s)) { kind = VMNET; return 1; } }
    else fprintf(stderr, "em16: -net %s: vmnet, vmnet-host, vmnet-bridged:IF or udp:LPORT:RPORT[:HOST]\n", s);
    return 0;
}

/* a frame received, into buf: its length, 0 if none is waiting */
int EmHost__NetRecv(uint8_t *buf, int len) {
    int n = 0;
    if (kind == UDP) udpPoll();
    pthread_mutex_lock(&lock);
    if (head != tail) {
        n = ringLen[head] < len ? ringLen[head] : len;
        memcpy(buf, ring[head], (size_t)n);
        head = (head + 1) % RING;
    }
    pthread_mutex_unlock(&lock);
    return n;
}

/* the first n bytes of buf sent as a frame */
void EmHost__NetSend(uint8_t *buf, int len, int n) {
    (void)len;
    if (n <= 0) return;
    if (kind == UDP) sendto(sock, buf, (size_t)n, 0, (struct sockaddr *)&peer, sizeof peer);
    else if (kind == VMNET) {
        struct iovec iov = { buf, (size_t)n };
        struct vmpktdesc pkt = { (size_t)n, &iov, 1, 0 };
        int count = 1;
        if ((size_t)n <= maxPacket) vmnet_write(iface, &pkt, &count);
    }
}
