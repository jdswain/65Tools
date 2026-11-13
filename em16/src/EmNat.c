/* EmNat.c - em16's built-in NAT (-net nat): the guest's Ethernet ends at
   a router of em16's own, as QEMU's user networking does, and what the
   guest sends out goes through the host's own sockets. No privileges,
   no other machine: the network of a phone (the Android em16) as of a
   Mac.

   The guest's network is 10.0.2.0/24:
     10.0.2.2   the router; to the guest, the host itself (127.0.0.1)
     10.0.2.3   the name server
     10.0.2.15  the guest, given by DHCP
   ARP for any 10.0.2.x but the guest's own is answered with the router's
   MAC; DHCP is answered (DISCOVER, REQUEST); a name's A records are
   looked up with getaddrinfo, other questions answered with none; ICMP
   echo to the router is answered, to the world sent with a ping socket;
   UDP from each guest port goes out of a socket of its own; a TCP
   connection the guest opens is opened by the host, and the bytes
   relayed both ways, with the guest's window, retransmission and FIN.
   The guest is not reachable from outside (no ports forwarded).

   EmNet_rt.c passes the frames the guest sends to EmNat_input, on the
   CPU's thread; a thread of the NAT's polls the sockets and its timers.
   What either makes for the guest goes into EmNet_rt.c's ring
   (EmNet_put). One lock over the NAT's state. */

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <poll.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

void EmNet_put(const uint8_t *f, int n);

#define NET     0x0A000200u   /* 10.0.2.0 */
#define GW      0x0A000202u
#define DNS     0x0A000203u
#define GUEST   0x0A00020Fu
#define MAXF    1514
#define MSS     1460
#define NUDP    32
#define NTCP    64
#define NPING   16
#define BUF     65536

static const uint8_t gwMac[6] = { 0x52, 0x55, 0x0A, 0x00, 0x02, 0x02 };
static uint8_t guestMac[6] = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
static pthread_mutex_t nat = PTHREAD_MUTEX_INITIALIZER;
static int wake[2] = { -1, -1 };
static int verbose;

/* ---- bytes ---- */

static unsigned get16(const uint8_t *p) { return (unsigned)p[0] << 8 | p[1]; }
static uint32_t get32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }
static void put16(uint8_t *p, unsigned x) { p[0] = (uint8_t)(x >> 8); p[1] = (uint8_t)x; }
static void put32(uint8_t *p, uint32_t x) { p[0] = (uint8_t)(x >> 24); p[1] = (uint8_t)(x >> 16); p[2] = (uint8_t)(x >> 8); p[3] = (uint8_t)x; }

static uint32_t sum(const uint8_t *p, int n, uint32_t s) {
    while (n > 1) { s += get16(p); p += 2; n -= 2; }
    if (n) s += (uint32_t)p[0] << 8;
    return s;
}
static unsigned fold(uint32_t s) { while (s >> 16) s = (s & 0xFFFF) + (s >> 16); return ~s & 0xFFFF; }

static long long now_ms(void) {
    struct timeval tv; gettimeofday(&tv, NULL);
    return (long long)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

/* seq a before b, modulo 2^32 */
static int before(uint32_t a, uint32_t b) { return (int32_t)(a - b) < 0; }

/* ---- frames to the guest ---- */

static int frame = 0;   /* an IPv4 packet's id */

/* an IPv4 packet of proto from src to dst, its payload p (n), as an
   Ethernet frame to the guest */
static void sendIP(int proto, uint32_t src, uint32_t dst, const uint8_t *p, int n) {
    uint8_t f[MAXF];
    uint8_t *ip = f + 14;
    if (14 + 20 + n > MAXF) return;
    memcpy(f, guestMac, 6); memcpy(f + 6, gwMac, 6); put16(f + 12, 0x0800);
    ip[0] = 0x45; ip[1] = 0; put16(ip + 2, (unsigned)(20 + n)); put16(ip + 4, (unsigned)(frame++ & 0xFFFF));
    put16(ip + 6, 0x4000); ip[8] = 64; ip[9] = (uint8_t)proto; put16(ip + 10, 0);
    put32(ip + 12, src); put32(ip + 16, dst);
    put16(ip + 10, fold(sum(ip, 20, 0)));
    memcpy(ip + 20, p, (size_t)n);
    EmNet_put(f, 14 + 20 + n);
}

/* the checksum of a UDP or TCP segment s (n) from src to dst */
static unsigned l4sum(int proto, uint32_t src, uint32_t dst, const uint8_t *s, int n) {
    uint8_t ph[12];
    put32(ph, src); put32(ph + 4, dst); ph[8] = 0; ph[9] = (uint8_t)proto; put16(ph + 10, (unsigned)n);
    return fold(sum(s, n, sum(ph, 12, 0)));
}

static void sendUDP(uint32_t src, unsigned sport, uint32_t dst, unsigned dport, const uint8_t *p, int n) {
    uint8_t s[MAXF];
    unsigned c;
    if (8 + n > MAXF - 34) return;
    put16(s, sport); put16(s + 2, dport); put16(s + 4, (unsigned)(8 + n)); put16(s + 6, 0);
    memcpy(s + 8, p, (size_t)n);
    c = l4sum(17, src, dst, s, 8 + n); put16(s + 6, c ? c : 0xFFFF);
    sendIP(17, src, dst, s, 8 + n);
}

/* the guest's view of a host address: the host's loopback is the router */
static uint32_t outside(uint32_t host) { return host == 0x7F000001u ? GW : host; }
static uint32_t inside(uint32_t guest) { return guest == GW ? 0x7F000001u : guest; }

static void nonblock(int s) { fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK); }
static void poke(void) { char c = 1; if (wake[1] >= 0 && write(wake[1], &c, 1) < 0) { } }

/* ---- ARP ---- */

static void arp(const uint8_t *a, int n) {
    uint8_t f[42];
    uint32_t tip;
    if (n < 28 || get16(a) != 1 || get16(a + 2) != 0x0800 || get16(a + 6) != 1) return;
    tip = get32(a + 24);
    if ((tip & 0xFFFFFF00u) != NET || tip == get32(a + 14)) return;
    memcpy(f, a + 8, 6); memcpy(f + 6, gwMac, 6); put16(f + 12, 0x0806);
    put16(f + 14, 1); put16(f + 16, 0x0800); f[18] = 6; f[19] = 4; put16(f + 20, 2);
    memcpy(f + 22, gwMac, 6); put32(f + 28, tip);
    memcpy(f + 32, a + 8, 6); memcpy(f + 38, a + 14, 4);
    EmNet_put(f, 42);
}

/* ---- DHCP ---- */

static void dhcp(const uint8_t *b, int n) {
    uint8_t r[300];
    const uint8_t *o;
    int type = 0, i = 240;
    if (n < 240 || b[0] != 1 || get32(b + 236) != 0x63825363u) return;
    while (i < n && b[i] != 255) {
        if (b[i] == 0) { i++; continue; }
        if (i + 1 >= n) break;
        if (b[i] == 53 && b[i + 1] >= 1) type = b[i + 2];
        i += 2 + b[i + 1];
    }
    if (type != 1 && type != 3) return;   /* DISCOVER, REQUEST */
    memset(r, 0, sizeof r);
    r[0] = 2; r[1] = 1; r[2] = 6; memcpy(r + 4, b + 4, 4);   /* xid */
    memcpy(r + 10, b + 10, 2);                             /* flags */
    put32(r + 16, GUEST); put32(r + 20, GW); memcpy(r + 28, b + 28, 16);
    put32(r + 236, 0x63825363u);
    o = r + 240; i = 240;
    r[i++] = 53; r[i++] = 1; r[i++] = type == 1 ? 2 : 5;     /* OFFER, ACK */
    r[i++] = 54; r[i++] = 4; put32(r + i, GW); i += 4;
    r[i++] = 51; r[i++] = 4; put32(r + i, 86400); i += 4;
    r[i++] = 1;  r[i++] = 4; put32(r + i, 0xFFFFFF00u); i += 4;
    r[i++] = 3;  r[i++] = 4; put32(r + i, GW); i += 4;
    r[i++] = 6;  r[i++] = 4; put32(r + i, DNS); i += 4;
    r[i++] = 255; (void)o;
    memcpy(guestMac, b + 28, 6);
    if (verbose) fprintf(stderr, "em16: nat: DHCP %s\n", type == 1 ? "offer" : "ack");
    sendUDP(GW, 67, 0xFFFFFFFFu, 68, r, i < 300 ? 300 : i);
}

/* ---- names ---- */

typedef struct { uint8_t q[512]; int n; unsigned sport; } Ask;

/* the question's answer, looked up on a thread of its own */
static void *lookup(void *arg) {
    Ask *a = arg;
    uint8_t r[512];
    char name[256];
    int i = 12, j = 0, qend, n = 0, rcode = 0, type;
    struct addrinfo hints, *res = NULL, *p;
    while (i < a->n && a->q[i] && j < 250) {
        int l = a->q[i++];
        if (j) name[j++] = '.';
        while (l-- > 0 && i < a->n && j < 254) name[j++] = (char)a->q[i++];
    }
    name[j] = 0; i++;
    qend = i + 4;
    if (qend > a->n) { free(a); return NULL; }
    type = (int)get16(a->q + i);
    memcpy(r, a->q, (size_t)qend);
    if (type == 1) {
        memset(&hints, 0, sizeof hints); hints.ai_family = AF_INET; hints.ai_socktype = SOCK_STREAM;
        if (getaddrinfo(name, NULL, &hints, &res) != 0) rcode = 3;
    }
    i = qend;
    for (p = res; p && n < 4 && i + 16 <= (int)sizeof r; p = p->ai_next) {
        put16(r + i, 0xC00C); put16(r + i + 2, 1); put16(r + i + 4, 1); put32(r + i + 6, 60); put16(r + i + 10, 4);
        memcpy(r + i + 12, &((struct sockaddr_in *)p->ai_addr)->sin_addr, 4);
        i += 16; n++;
    }
    if (res) freeaddrinfo(res);
    r[2] = 0x81 | (a->q[2] & 0x01); r[3] = (uint8_t)(0x80 | rcode);   /* a response, recursion */
    put16(r + 4, 1); put16(r + 6, (unsigned)n); put16(r + 8, 0); put16(r + 10, 0);
    if (verbose) fprintf(stderr, "em16: nat: %s: %d\n", name, n);
    pthread_mutex_lock(&nat); sendUDP(DNS, 53, GUEST, a->sport, r, i); pthread_mutex_unlock(&nat);
    free(a);
    return NULL;
}

static void dns(const uint8_t *b, int n, unsigned sport) {
    Ask *a;
    pthread_t t;
    if (n < 17 || n > 512 || (b[2] & 0x80) || get16(b + 4) != 1) return;
    a = malloc(sizeof *a);
    if (!a) return;
    memcpy(a->q, b, (size_t)n); a->n = n; a->sport = sport;
    if (pthread_create(&t, NULL, lookup, a) == 0) pthread_detach(t); else free(a);
}

/* ---- UDP ---- */

typedef struct { int s; unsigned port; long long used; } Udp;
static Udp udp[NUDP];

static void udpOut(uint32_t dst, unsigned sport, unsigned dport, const uint8_t *p, int n) {
    int i, free_ = -1, old = 0;
    struct sockaddr_in to;
    for (i = 0; i < NUDP; i++) {
        if (udp[i].s > 0 && udp[i].port == sport) break;
        if (udp[i].s <= 0 && free_ < 0) free_ = i;
        if (udp[i].used < udp[old].used) old = i;
    }
    if (i == NUDP) {
        if (free_ < 0) { close(udp[old].s); udp[old].s = 0; free_ = old; }
        i = free_;
        udp[i].s = socket(AF_INET, SOCK_DGRAM, 0);
        if (udp[i].s < 0) { udp[i].s = 0; return; }
        nonblock(udp[i].s); udp[i].port = sport;
        poke();
    }
    udp[i].used = now_ms();
    if (verbose) fprintf(stderr, "em16: nat: UDP from %u to %u.%u.%u.%u:%u\n", sport, dst >> 24, dst >> 16 & 255, dst >> 8 & 255, dst & 255, dport);
    memset(&to, 0, sizeof to); to.sin_family = AF_INET; to.sin_port = htons((uint16_t)dport);
    to.sin_addr.s_addr = htonl(inside(dst));
    sendto(udp[i].s, p, (size_t)n, 0, (struct sockaddr *)&to, sizeof to);
}

static void udpIn(Udp *u) {
    uint8_t b[MAXF];
    struct sockaddr_in from;
    socklen_t fl = sizeof from;
    ssize_t n;
    while ((n = recvfrom(u->s, b, MAXF - 42, 0, (struct sockaddr *)&from, &fl)) > 0) {
        sendUDP(outside(ntohl(from.sin_addr.s_addr)), ntohs(from.sin_port), GUEST, u->port, b, (int)n);
        u->used = now_ms(); fl = sizeof from;
    }
}

/* ---- ICMP echo ---- */

typedef struct { int s; uint32_t dst; unsigned id; long long used; } Ping;
static Ping ping[NPING];

static void echo(uint32_t src, uint32_t dst, const uint8_t *p, int n) {
    uint8_t r[MAXF];
    int i, k = -1;
    struct sockaddr_in to;
    if (n < 8 || n > MAXF - 34 || p[0] != 8) return;
    if (dst == GW || dst == DNS) {
        memcpy(r, p, (size_t)n); r[0] = 0; put16(r + 2, 0); put16(r + 2, fold(sum(r, n, 0)));
        sendIP(1, dst, src, r, n); return;
    }
    for (i = 0; i < NPING; i++) {
        if (ping[i].s > 0 && ping[i].dst == dst && ping[i].id == get16(p + 4)) { k = i; break; }
        if (ping[i].s <= 0 && k < 0) k = i;
    }
    if (k < 0) return;
    if (ping[k].s <= 0) {
        ping[k].s = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
        if (ping[k].s < 0) { ping[k].s = 0; return; }
        nonblock(ping[k].s); ping[k].dst = dst; ping[k].id = get16(p + 4);
        poke();
    }
    ping[k].used = now_ms();
    memset(&to, 0, sizeof to); to.sin_family = AF_INET; to.sin_addr.s_addr = htonl(inside(dst));
    sendto(ping[k].s, p, (size_t)n, 0, (struct sockaddr *)&to, sizeof to);
}

static void echoIn(Ping *g) {
    uint8_t b[MAXF], *p;
    ssize_t n;
    while ((n = recv(g->s, b, MAXF - 34, 0)) > 0) {
        p = b;
        if ((b[0] >> 4) == 4 && n >= 20 + 8) { int h = (b[0] & 15) * 4; p += h; n -= h; }   /* the Mac's: with the IP header */
        if (n < 8 || p[0] != 0) continue;
        put16(p + 4, g->id); put16(p + 2, 0); put16(p + 2, fold(sum(p, (int)n, 0)));
        sendIP(1, outside(g->dst), GUEST, p, (int)n);
        g->used = now_ms();
    }
}

/* ---- TCP ---- */

enum { FREE, CONNECTING, SYNACK, OPEN };

typedef struct {
    int state, s;
    uint32_t dst; unsigned sport, dport;
    uint32_t rcv;           /* the guest's next byte's seq, acked */
    uint32_t una, nxt;      /* ours: the oldest unacked, the next to send */
    uint32_t iss;
    unsigned wnd, mss;      /* the guest's */
    uint8_t *in;  int inN;  /* from the host, from una on, to send the guest */
    uint8_t *out; int outN; /* from the guest, to write to the host */
    int hostEof, finSent, guestFin, shut;
    long long rto, sent;    /* retransmission */
} Tcp;
static Tcp tcp[NTCP];

#define FIN 0x01
#define SYN 0x02
#define RST 0x04
#define PSH 0x08
#define ACK 0x10

static void seg(uint32_t src, unsigned sport, uint32_t dst, unsigned dport, uint32_t seq, uint32_t ack, int flags,
                const uint8_t *p, int n, int mss) {
    uint8_t s[MAXF];
    int h = mss ? 24 : 20;
    put16(s, sport); put16(s + 2, dport); put32(s + 4, seq); put32(s + 8, ack);
    s[12] = (uint8_t)((h / 4) << 4); s[13] = (uint8_t)flags; put16(s + 14, 32768); put16(s + 16, 0); put16(s + 18, 0);
    if (mss) { s[20] = 2; s[21] = 4; put16(s + 22, MSS); }
    if (n) memcpy(s + h, p, (size_t)n);
    put16(s + 16, l4sum(6, src, dst, s, h + n));
    sendIP(6, src, dst, s, h + n);
}

static void tsend(Tcp *t, uint32_t seq, int flags, const uint8_t *p, int n) {
    seg(outside(t->dst), t->dport, GUEST, t->sport, seq, t->rcv, flags, p, n, 0);
}

static void tfree(Tcp *t) {
    if (t->s > 0) close(t->s);
    free(t->in); free(t->out);
    memset(t, 0, sizeof *t);
}

static void reset(uint32_t src, unsigned sport, uint32_t dst, unsigned dport, uint32_t seq, uint32_t ack, int withAck) {
    seg(dst, dport, src, sport, seq, ack, RST | (withAck ? ACK : 0), NULL, 0, 0);
}

/* what of t's bytes from the host the guest's window has room for, sent */
static void push(Tcp *t) {
    long long tm = now_ms();
    int off, n;
    if (t->state != OPEN) return;
    for (;;) {
        off = (int)(t->nxt - t->una);
        n = t->inN - off;
        if ((unsigned)off >= t->wnd) break;
        if (n > (int)(t->wnd - (unsigned)off)) n = (int)(t->wnd - (unsigned)off);
        if (n > (int)t->mss) n = (int)t->mss;
        if (n <= 0) break;
        tsend(t, t->nxt, ACK | PSH, t->in + off, n);
        if (t->una == t->nxt) t->sent = tm;
        t->nxt += (uint32_t)n;
    }
    if (t->hostEof && !t->finSent && (int)(t->nxt - t->una) == t->inN) {
        tsend(t, t->nxt, FIN | ACK, NULL, 0); t->nxt++; t->finSent = 1;
        if (t->sent == 0 || t->una + 1 == t->nxt) t->sent = tm;
    }
}

/* the bytes from the guest written to the host, as many as it takes */
static void drain(Tcp *t) {
    ssize_t w;
    while (t->outN > 0) {
        w = send(t->s, t->out, (size_t)t->outN, 0);
        if (w <= 0) break;
        memmove(t->out, t->out + w, (size_t)(t->outN - w)); t->outN -= (int)w;
    }
    if (t->outN == 0 && t->guestFin && !t->shut) { shutdown(t->s, SHUT_WR); t->shut = 1; }
}

static void tcpIn(uint32_t src, uint32_t dst, const uint8_t *s, int n) {
    unsigned sport, dport, flags, h, wnd;
    uint32_t seq, ack;
    int i, k = -1, len;
    Tcp *t;
    struct sockaddr_in to;
    if (n < 20) return;
    sport = get16(s); dport = get16(s + 2); seq = get32(s + 4); ack = get32(s + 8);
    h = (unsigned)(s[12] >> 4) * 4; flags = s[13]; wnd = get16(s + 14);
    if (h < 20 || (int)h > n) return;
    len = n - (int)h;
    for (i = 0; i < NTCP; i++) {
        if (tcp[i].state != FREE && tcp[i].sport == sport && tcp[i].dst == dst && tcp[i].dport == dport) { k = i; break; }
    }
    if (k < 0) {
        if (flags & RST) return;
        if ((flags & (SYN | ACK)) != SYN) { reset(src, sport, dst, dport, ack, seq + (uint32_t)len, (flags & ACK) == 0); return; }
        for (i = 0; i < NTCP && tcp[i].state != FREE; i++) { }
        if (i == NTCP) { reset(src, sport, dst, dport, 0, seq + 1, 1); return; }
        t = &tcp[i];
        memset(t, 0, sizeof *t);
        t->in = malloc(BUF); t->out = malloc(BUF);
        t->s = socket(AF_INET, SOCK_STREAM, 0);
        if (!t->in || !t->out || t->s < 0) { tfree(t); reset(src, sport, dst, dport, 0, seq + 1, 1); return; }
        nonblock(t->s);
        t->dst = dst; t->sport = sport; t->dport = dport;
        t->rcv = seq + 1; t->iss = (uint32_t)rand() << 1; t->una = t->nxt = t->iss;
        t->wnd = wnd; t->mss = 536;
        for (i = 20; i + 1 < (int)h; ) {
            if (s[i] == 0) break;
            if (s[i] == 1) { i++; continue; }
            if (s[i] == 2 && s[i + 1] == 4 && i + 4 <= (int)h) t->mss = get16(s + i + 2);
            if (s[i + 1] < 2) break;
            i += s[i + 1];
        }
        if (t->mss > MSS) t->mss = MSS;
        memset(&to, 0, sizeof to); to.sin_family = AF_INET; to.sin_port = htons((uint16_t)dport);
        to.sin_addr.s_addr = htonl(inside(dst));
        if (connect(t->s, (struct sockaddr *)&to, sizeof to) < 0 && errno != EINPROGRESS) {
            tfree(t); reset(src, sport, dst, dport, 0, seq + 1, 1); return;
        }
        t->state = CONNECTING;
        if (verbose) fprintf(stderr, "em16: nat: TCP to %u.%u.%u.%u:%u\n", dst >> 24, dst >> 16 & 255, dst >> 8 & 255, dst & 255, dport);
        poke();
        return;
    }
    t = &tcp[k];
    if (flags & RST) { tfree(t); return; }
    if (flags & SYN) { if (t->state == SYNACK) seg(outside(t->dst), t->dport, GUEST, t->sport, t->iss, t->rcv, SYN | ACK, NULL, 0, 1); return; }
    if (t->state == CONNECTING) return;
    if (flags & ACK) {
        if (t->state == SYNACK && ack == t->iss + 1) { t->state = OPEN; t->una = t->nxt = ack; }
        if (t->state == OPEN && !before(ack, t->una) && !before(t->nxt, ack)) {
            int acked = (int)(ack - t->una);
            int data = acked;
            if (t->finSent && ack == t->nxt) data--;   /* our FIN's */
            if (data > t->inN) data = t->inN;
            if (data > 0) { memmove(t->in, t->in + data, (size_t)(t->inN - data)); t->inN -= data; }
            if (acked > 0) { t->una = ack; t->rto = 0; t->sent = now_ms(); }
        }
        t->wnd = wnd;
    }
    if (t->state != OPEN) return;
    if (len > 0 || (flags & FIN)) {
        if (seq != t->rcv) { tsend(t, t->nxt, ACK, NULL, 0); return; }   /* not the next: what we have, again */
        if (len > 0) {
            if (t->outN + len > BUF) { tsend(t, t->nxt, ACK, NULL, 0); return; }   /* no room: dropped, sent again */
            memcpy(t->out + t->outN, s + h, (size_t)len); t->outN += len; t->rcv += (uint32_t)len;
        }
        if (flags & FIN) { t->rcv++; t->guestFin = 1; }
        drain(t);
        tsend(t, t->nxt, ACK, NULL, 0);
        poke();
    }
    push(t);
    if (t->guestFin && t->finSent && t->una == t->nxt && t->outN == 0) tfree(t);
}

/* t's socket ready: connected, readable or writable */
static void tcpReady(Tcp *t, int revents) {
    int err = 0;
    socklen_t el = sizeof err;
    ssize_t r;
    if (t->state == CONNECTING) {
        if (!(revents & (POLLOUT | POLLERR | POLLHUP))) return;
        getsockopt(t->s, SOL_SOCKET, SO_ERROR, &err, &el);
        if (err) { reset(GUEST, t->sport, t->dst, t->dport, 0, t->rcv, 1); tfree(t); return; }
        t->state = SYNACK;
        seg(outside(t->dst), t->dport, GUEST, t->sport, t->iss, t->rcv, SYN | ACK, NULL, 0, 1);
        t->sent = now_ms();
        return;
    }
    if (revents & POLLOUT) drain(t);
    if ((revents & (POLLIN | POLLHUP | POLLERR)) && !t->hostEof && t->state == OPEN) {
        while (t->inN < BUF) {
            r = recv(t->s, t->in + t->inN, (size_t)(BUF - t->inN), 0);
            if (r > 0) t->inN += (int)r;
            else {
                if (r == 0) t->hostEof = 1;
                else if (errno != EAGAIN && errno != EWOULDBLOCK) {
                    tsend(t, t->nxt, RST | ACK, NULL, 0); tfree(t); return;
                }
                break;
            }
        }
        push(t);
    }
}

/* resent from una what the guest has not acked in time */
static void timers(void) {
    long long tm = now_ms();
    int i;
    for (i = 0; i < NTCP; i++) {
        Tcp *t = &tcp[i];
        if (t->state == SYNACK && tm - t->sent > 1000) {
            seg(outside(t->dst), t->dport, GUEST, t->sport, t->iss, t->rcv, SYN | ACK, NULL, 0, 1); t->sent = tm;
        } else if (t->state == OPEN && t->una != t->nxt) {
            long long rto = t->rto ? t->rto : 300;
            if (tm - t->sent > rto) {
                t->nxt = t->una; if (t->finSent) t->finSent = 0;
                t->rto = rto * 2 > 4000 ? 4000 : rto * 2; t->sent = tm;
                push(t);
            }
        } else if (t->state == OPEN && t->wnd == 0 && t->inN > 0 && tm - t->sent > 1000) {
            tsend(t, t->nxt, ACK, NULL, 0); t->sent = tm;   /* the window probed */
        }
    }
    for (i = 0; i < NUDP; i++) if (udp[i].s > 0 && tm - udp[i].used > 120000) { close(udp[i].s); udp[i].s = 0; }
    for (i = 0; i < NPING; i++) if (ping[i].s > 0 && tm - ping[i].used > 30000) { close(ping[i].s); ping[i].s = 0; }
}

/* ---- the NAT's thread ---- */

static void *loop(void *arg) {
    struct pollfd fds[1 + NUDP + NPING + NTCP];
    void *who[1 + NUDP + NPING + NTCP];
    int kind[1 + NUDP + NPING + NTCP];
    int i, n;
    char c[64];
    (void)arg;
    for (;;) {
        pthread_mutex_lock(&nat);
        n = 0;
        fds[n].fd = wake[0]; fds[n].events = POLLIN; kind[n] = 0; n++;
        for (i = 0; i < NUDP; i++) if (udp[i].s > 0) { fds[n].fd = udp[i].s; fds[n].events = POLLIN; who[n] = &udp[i]; kind[n] = 1; n++; }
        for (i = 0; i < NPING; i++) if (ping[i].s > 0) { fds[n].fd = ping[i].s; fds[n].events = POLLIN; who[n] = &ping[i]; kind[n] = 2; n++; }
        for (i = 0; i < NTCP; i++) {
            Tcp *t = &tcp[i];
            short ev = 0;
            if (t->state == CONNECTING || t->outN > 0) ev |= POLLOUT;
            if (t->state == OPEN && !t->hostEof && t->inN < BUF) ev |= POLLIN;
            if (t->state != FREE) { fds[n].fd = ev ? t->s : -1; fds[n].events = ev; fds[n].revents = 0; who[n] = t; kind[n] = 3; n++; }
        }
        pthread_mutex_unlock(&nat);
        poll(fds, (nfds_t)n, 50);
        pthread_mutex_lock(&nat);
        if (fds[0].revents & POLLIN) while (read(wake[0], c, sizeof c) > 0) { }
        for (i = 1; i < n; i++) {
            if (!fds[i].revents) continue;
            if (kind[i] == 1 && ((Udp *)who[i])->s == fds[i].fd) udpIn(who[i]);
            else if (kind[i] == 2 && ((Ping *)who[i])->s == fds[i].fd) echoIn(who[i]);
            else if (kind[i] == 3 && ((Tcp *)who[i])->state != FREE && ((Tcp *)who[i])->s == fds[i].fd) tcpReady(who[i], fds[i].revents);
        }
        timers();
        pthread_mutex_unlock(&nat);
    }
    return NULL;
}

/* ---- EmNet_rt.c's ---- */

int EmNat_open(const char *arg) {
    pthread_t t;
    verbose = arg && strstr(arg, "verbose") != NULL;
    if (pipe(wake) < 0) return 0;
    nonblock(wake[0]); nonblock(wake[1]);
    srand((unsigned)now_ms());
    if (pthread_create(&t, NULL, loop, NULL) != 0) return 0;
    pthread_detach(t);
    return 1;
}

/* a frame the guest sent */
void EmNat_input(const uint8_t *f, int n) {
    const uint8_t *ip;
    int hl, len, proto;
    uint32_t src, dst;
    if (n < 14) return;
    pthread_mutex_lock(&nat);
    if (get16(f + 12) == 0x0806) arp(f + 14, n - 14);
    else if (get16(f + 12) == 0x0800 && n >= 34) {
        ip = f + 14; hl = (ip[0] & 15) * 4; len = (int)get16(ip + 2); proto = ip[9];
        src = get32(ip + 12); dst = get32(ip + 16);
        if ((ip[0] >> 4) == 4 && hl >= 20 && len >= hl && 14 + len <= n && (get16(ip + 6) & 0x3FFF) == 0) {
            const uint8_t *p = ip + hl;
            int pn = len - hl;
            if (src != 0) memcpy(guestMac, f + 6, 6);
            if (proto == 17 && pn >= 8) {
                unsigned sport = get16(p), dport = get16(p + 2), ul = get16(p + 4);
                if (ul >= 8 && (int)ul <= pn) {
                    if (dport == 67) dhcp(p + 8, (int)ul - 8);
                    else if (dst == DNS && dport == 53) dns(p + 8, (int)ul - 8, sport);
                    else if (dst != 0xFFFFFFFFu && (dst & 0xFF) != 0xFF) udpOut(dst, sport, dport, p + 8, (int)ul - 8);
                }
            } else if (proto == 6) tcpIn(src, dst, p, pn);
            else if (proto == 1) echo(src, dst, p, pn);
        }
    }
    pthread_mutex_unlock(&nat);
}
