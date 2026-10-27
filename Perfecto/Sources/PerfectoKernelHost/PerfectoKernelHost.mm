#import "PerfectoKernelHost.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <limits>
#include <vector>

#include <mach/mach_time.h>

namespace {

/// Everything the render block touches. The block holds a plain pointer to
/// it, so rendering never retains, releases or messages an object.
struct RenderState {
    PerfectoKernel *kernel = nullptr;
    AUAudioFrameCount maximumFrames = 0;
    double sampleRate = 48000;
    /// Seconds in one tick of the host's clock.
    double secondsPerTick = 0;
    /// When frame 0 was rendered for, by the latest render (see the header).
    std::atomic<double> uptimeAtFrameZero{std::numeric_limits<double>::quiet_NaN()};
    /// One buffer per channel, for the unit's input to be pulled into, and
    /// for output when the caller brings no buffers of its own.
    std::vector<std::vector<float>> input;
    std::vector<std::vector<float>> output;
    /// The list handed to the pull block, and the channel pointers handed
    /// to the kernel: laid out once, pointed at buffers each render.
    std::vector<char> inputListStorage;
    std::vector<const float *> inputChannels;
    std::vector<float *> outputChannels;

    AudioBufferList *inputList() {
        return reinterpret_cast<AudioBufferList *>(inputListStorage.data());
    }
};

}

@implementation PerfectoKernelHost {
    RenderState _state;
}

- (instancetype)init {
    if ((self = [super init])) {
        _state.kernel = perfecto_kernel_create();
    }
    return self;
}

- (void)dealloc {
    perfecto_kernel_destroy(_state.kernel);
}

- (PerfectoKernel *)kernel {
    return _state.kernel;
}

- (double)uptimeAtFrameZero {
    return _state.uptimeAtFrameZero.load(std::memory_order_relaxed);
}

- (void)prepareWithSampleRate:(double)sampleRate
                     channels:(NSInteger)channels
                maximumFrames:(AUAudioFrameCount)maximumFrames {
    const auto count = static_cast<size_t>(std::max<NSInteger>(channels, 1));
    _state.maximumFrames = maximumFrames;
    _state.input.assign(count, std::vector<float>(maximumFrames, 0));
    _state.output.assign(count, std::vector<float>(maximumFrames, 0));
    _state.inputListStorage.assign(offsetof(AudioBufferList, mBuffers) + count * sizeof(AudioBuffer), 0);
    _state.inputChannels.assign(count, nullptr);
    _state.outputChannels.assign(count, nullptr);
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    _state.secondsPerTick = static_cast<double>(timebase.numer) / static_cast<double>(timebase.denom) * 1e-9;
    _state.sampleRate = sampleRate;
    // The kernel counts its frames from 0 again.
    _state.uptimeAtFrameZero.store(std::numeric_limits<double>::quiet_NaN());
    perfecto_kernel_prepare(_state.kernel, sampleRate);
}

- (AUInternalRenderBlock)renderBlock {
    RenderState *state = &_state;
    return ^AUAudioUnitStatus(AudioUnitRenderActionFlags *actionFlags,
                              const AudioTimeStamp *timestamp,
                              AUAudioFrameCount frameCount,
                              NSInteger outputBusNumber,
                              AudioBufferList *outputData,
                              const AURenderEvent *realtimeEventListHead,
                              AURenderPullInputBlock pullInputBlock) {
        if (frameCount > state->maximumFrames) return kAudioUnitErr_TooManyFramesToProcess;
        const UInt32 channels = static_cast<UInt32>(state->output.size());
        const UInt32 byteSize = frameCount * sizeof(float);

        // Input: whatever is connected, or silence if nothing is.
        bool hasInput = false;
        if (pullInputBlock) {
            AudioBufferList *inputList = state->inputList();
            inputList->mNumberBuffers = channels;
            for (UInt32 channel = 0; channel < channels; ++channel) {
                inputList->mBuffers[channel].mNumberChannels = 1;
                inputList->mBuffers[channel].mDataByteSize = byteSize;
                inputList->mBuffers[channel].mData = state->input[channel].data();
            }
            AudioUnitRenderActionFlags pullFlags = 0;
            if (pullInputBlock(&pullFlags, timestamp, frameCount, 0, inputList) == noErr) {
                hasInput = true;
                for (UInt32 channel = 0; channel < channels; ++channel) {
                    state->inputChannels[channel] = static_cast<const float *>(inputList->mBuffers[channel].mData);
                }
            }
        }

        // Output: the caller's buffers, or ours where it brought none.
        const UInt32 outputs = std::min(outputData->mNumberBuffers, channels);
        for (UInt32 channel = 0; channel < outputs; ++channel) {
            AudioBuffer &buffer = outputData->mBuffers[channel];
            if (buffer.mData == nullptr) buffer.mData = state->output[channel].data();
            buffer.mDataByteSize = byteSize;
            state->outputChannels[channel] = static_cast<float *>(buffer.mData);
        }

        // Each render says when it is for, which keeps the kernel's count
        // of frames tied to the clock everything else is timed by.
        if (timestamp->mFlags & kAudioTimeStampHostTimeValid) {
            const double uptime = static_cast<double>(timestamp->mHostTime) * state->secondsPerTick;
            const double frames = static_cast<double>(perfecto_kernel_time(state->kernel));
            state->uptimeAtFrameZero.store(uptime - frames / state->sampleRate, std::memory_order_relaxed);
        }

        perfecto_kernel_render(state->kernel,
                               hasInput ? state->inputChannels.data() : nullptr, hasInput ? static_cast<int32_t>(channels) : 0,
                               state->outputChannels.data(), static_cast<int32_t>(outputs),
                               static_cast<int32_t>(frameCount));
        return noErr;
    };
}

@end
