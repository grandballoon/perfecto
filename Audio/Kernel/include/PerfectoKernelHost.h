// What the audio kernel needs from the platform to be an Audio Unit's
// renderer: memory set aside before rendering starts, and a render block
// that hands the unit's buffers to the kernel.
//
// The render block is Objective-C++ so that nothing on the render thread
// passes through Swift, which makes no promise about allocating there.

#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>

#import "PerfectoKernel.h"

NS_ASSUME_NONNULL_BEGIN

@interface PerfectoKernelHost : NSObject

/// The kernel, for sending events to and reading the time from.
@property (nonatomic, readonly) PerfectoKernel *kernel;

/// Readies the kernel and the buffers for rendering at `sampleRate`, with
/// `channels` in and out and at most `maximumFrames` a render call. Call it
/// from `allocateRenderResources`, never while rendering.
- (void)prepareWithSampleRate:(double)sampleRate
                     channels:(NSInteger)channels
                maximumFrames:(AUAudioFrameCount)maximumFrames;

/// The block for an `AUAudioUnit` to give as its `internalRenderBlock`.
/// It pulls the unit's input, if anything is connected to it, and renders.
@property (nonatomic, readonly) AUInternalRenderBlock renderBlock;

@end

NS_ASSUME_NONNULL_END
