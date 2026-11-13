#include "ApplicationAudioDSP.h"
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

// Only lock-free primitives are allowed on the HAL thread on either release architecture.
_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "Audio gain requires lock-free 32-bit atomics");
struct STAudioDSP { _Atomic(unsigned int) gainBits; };

static float boundedGain(float gain) {
    return !isfinite(gain) ? 1.0f : fminf(1.0f, fmaxf(0.0f, gain));
}

STAudioDSP *STAudioDSPCreate(float gain) {
    STAudioDSP *context = calloc(1, sizeof(*context));
    if (context) {
        unsigned int bits;
        gain = boundedGain(gain);
        memcpy(&bits, &gain, sizeof(bits));
        atomic_init(&context->gainBits, bits);
    }
    return context;
}

void STAudioDSPDestroy(STAudioDSP *context) { free(context); }

void STAudioDSPSetGain(STAudioDSP *context, float gain) {
    unsigned int bits;
    gain = boundedGain(gain);
    memcpy(&bits, &gain, sizeof(bits));
    atomic_store_explicit(&context->gainBits, bits, memory_order_relaxed);
}

float STAudioDSPGetGain(const STAudioDSP *context) {
    unsigned int bits = atomic_load_explicit(&context->gainBits, memory_order_relaxed);
    float gain;
    memcpy(&gain, &bits, sizeof(gain));
    return gain;
}

bool STAudioDSPSupportsFormat(const AudioStreamBasicDescription *f) {
    if (!f || f->mFormatID != kAudioFormatLinearPCM ||
        f->mChannelsPerFrame != 2 || f->mBitsPerChannel != 32 ||
        !isfinite(f->mSampleRate) || f->mSampleRate < 8000 || f->mSampleRate > 384000 ||
        f->mFramesPerPacket != 1) return false;
    const unsigned int required = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    const unsigned int allowed = required | kAudioFormatFlagIsNonInterleaved;
    if ((f->mFormatFlags & required) != required || (f->mFormatFlags & ~allowed)) return false;
    const unsigned int bytes = (f->mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? 4 : 8;
    return f->mBytesPerFrame == bytes && f->mBytesPerPacket == bytes;
}

// Both layouts have exactly two channels. Every buffer must contain complete frames.
static unsigned int stereoFrames(const AudioBufferList *list) {
    if (!list || (list->mNumberBuffers != 1 && list->mNumberBuffers != 2)) return 0;
    unsigned int frames = 0;
    for (unsigned int b = 0; b < list->mNumberBuffers; ++b) {
        const AudioBuffer *buffer = &list->mBuffers[b];
        const unsigned int channels = list->mNumberBuffers == 1 ? 2 : 1;
        const unsigned int stride = channels * sizeof(float);
        if (!buffer->mData || buffer->mNumberChannels != channels ||
            buffer->mDataByteSize % stride != 0) return 0;
        const unsigned int count = buffer->mDataByteSize / stride;
        if (!count || count > 65536 || (b && count != frames)) return 0;
        frames = count;
    }
    return frames;
}

void STAudioDSPProcess(STAudioDSP *context, const AudioBufferList *input, AudioBufferList *output) {
    if (!output) return;
    const unsigned int inputFrames = stereoFrames(input);
    const unsigned int outputFrames = stereoFrames(output);
    if (!context || !inputFrames || inputFrames != outputFrames) {
        // HAL owns these sizes. An invalid layout must never leak old output samples.
        for (unsigned int b = 0; b < output->mNumberBuffers; ++b) {
            if (output->mBuffers[b].mData)
                memset(output->mBuffers[b].mData, 0, output->mBuffers[b].mDataByteSize);
        }
        return;
    }
    const float gain = STAudioDSPGetGain(context);
    for (unsigned int channel = 0; channel < 2; ++channel) {
        const float *source = input->mBuffers[input->mNumberBuffers == 1 ? 0 : channel].mData;
        float *destination = output->mBuffers[output->mNumberBuffers == 1 ? 0 : channel].mData;
        const unsigned int inputStride = input->mNumberBuffers == 1 ? 2 : 1;
        const unsigned int outputStride = output->mNumberBuffers == 1 ? 2 : 1;
        if (inputStride == 2) source += channel;
        if (outputStride == 2) destination += channel;
        for (unsigned int frame = 0; frame < outputFrames; ++frame) {
            // Mute also suppresses NaNs in malformed source samples.
            destination[frame * outputStride] = gain == 0 ? 0 : source[frame * inputStride] * gain;
        }
    }
}

OSStatus STAudioDSPIOProc(AudioObjectID device, const AudioTimeStamp *now,
    const AudioBufferList *input, const AudioTimeStamp *inputTime,
    AudioBufferList *output, const AudioTimeStamp *outputTime, void *context) {
    STAudioDSPProcess(context, input, output);
    return noErr;
}
