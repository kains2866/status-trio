#ifndef APPLICATION_AUDIO_DSP_H
#define APPLICATION_AUDIO_DSP_H
#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>

typedef struct STAudioDSP STAudioDSP;
#pragma clang assume_nonnull begin
STAudioDSP * _Nullable STAudioDSPCreate(float gain);
void STAudioDSPDestroy(STAudioDSP *context);
void STAudioDSPSetGain(STAudioDSP *context, float gain);
float STAudioDSPGetGain(const STAudioDSP *context);
bool STAudioDSPSupportsFormat(const AudioStreamBasicDescription *format);
void STAudioDSPProcess(STAudioDSP *context, const AudioBufferList *input, AudioBufferList *output);
OSStatus STAudioDSPIOProc(AudioObjectID device, const AudioTimeStamp *now,
    const AudioBufferList *input, const AudioTimeStamp *inputTime,
    AudioBufferList *output, const AudioTimeStamp *outputTime, void * _Nullable context);
#pragma clang assume_nonnull end
#endif
