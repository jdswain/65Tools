/* EmAudio.c - the host's sound for the Mini816's speaker (EmSound):
   EmHost.SoundStart and SoundPut on an AudioQueue.

   The CPU thread puts samples into a ring as the board's time passes,
   which EmMini816.Run keeps to the host's; the queue's callback, on the
   queue's own thread, takes them three buffers of 10 ms behind. The two
   clocks drift apart a little: a ring run dry plays silence until 20 ms
   are waiting again, and one grown past 80 ms (the board ran ahead, or
   fast) loses its oldest down to 20 ms. */

#include <AudioToolbox/AudioToolbox.h>
#include <stdint.h>

enum { ringSize = 16384, bufFrames = 480, nBufs = 3, target = 960, ceiling = 3840 };

static int16_t ring[ringSize];
static volatile uint32_t head, tail;   /* written by the CPU thread, the queue's */
static AudioQueueRef queue;
static int priming = 1;                /* the queue's: waiting for target samples */

static void fill(void *user, AudioQueueRef q, AudioQueueBufferRef b) {
    int16_t *out = (int16_t *)b->mAudioData;
    uint32_t h = __atomic_load_n(&head, __ATOMIC_ACQUIRE), t = tail, n = h - t;
    (void)user;
    if (n > ceiling) { t = h - target; n = target; }
    if (priming && n >= target) priming = 0;
    for (int i = 0; i < bufFrames; i++) {
        if (!priming && n > 0) { out[i] = ring[t % ringSize]; t++; n--; }
        else { out[i] = 0; priming = 1; }
    }
    __atomic_store_n(&tail, t, __ATOMIC_RELEASE);
    b->mAudioDataByteSize = bufFrames * 2;
    AudioQueueEnqueueBuffer(q, b, 0, NULL);
}

int EmHost__SoundStart(int rate) {
    AudioStreamBasicDescription f = {0};
    f.mSampleRate = rate;
    f.mFormatID = kAudioFormatLinearPCM;
    f.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    f.mBytesPerPacket = 2; f.mFramesPerPacket = 1; f.mBytesPerFrame = 2;
    f.mChannelsPerFrame = 1; f.mBitsPerChannel = 16;
    if (queue) return 1;
    if (AudioQueueNewOutput(&f, fill, NULL, NULL, NULL, 0, &queue) != noErr) { queue = NULL; return 0; }
    for (int i = 0; i < nBufs; i++) {
        AudioQueueBufferRef b;
        if (AudioQueueAllocateBuffer(queue, bufFrames * 2, &b) != noErr) goto fail;
        fill(NULL, queue, b);
    }
    if (AudioQueueStart(queue, NULL) != noErr) goto fail;
    return 1;
fail:
    AudioQueueDispose(queue, true);
    queue = NULL;
    return 0;
}

void EmHost__SoundPut(int s) {
    uint32_t h = head;
    if (h - __atomic_load_n(&tail, __ATOMIC_ACQUIRE) >= ringSize) return;   /* full: lost */
    ring[h % ringSize] = (int16_t)s;
    __atomic_store_n(&head, h + 1, __ATOMIC_RELEASE);
}
