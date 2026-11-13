/* EmVmnet.c - macOS's vmnet.framework under em16's network (EmNet_rt.c):
   -net vmnet, vmnet-host and vmnet-bridged:IF. The frames it receives go
   into EmNet_rt.c's ring (EmNet_put); NetSend's frames come out here
   (EmNet_vmnetSend). Linked into the Mac em16 only: elsewhere the weak
   hooks of EmNet_rt.c are left unset and -net vmnet is refused. */

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/uio.h>
#include <dispatch/dispatch.h>
#include <vmnet/vmnet.h>

#define MAXFRAME 1536

void EmNet_put(const uint8_t *f, int n);
#define put EmNet_put

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

int EmNet_vmnetOpen(const char *arg) {
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

void EmNet_vmnetSend(uint8_t *buf, int n) {
    struct iovec iov = { buf, (size_t)n };
    struct vmpktdesc pkt = { (size_t)n, &iov, 1, 0 };
    int count = 1;
    if ((size_t)n <= maxPacket) vmnet_write(iface, &pkt, &count);
}
