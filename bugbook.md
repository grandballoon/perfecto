# Perfecto Bug Book

Errors encountered during development, with cause and fix. Fed into an LLM for learning.

---

## MIDIReceived on session.sourceEndpoint() silently fails
**Error:** No MIDI events received in MIDI Monitor despite `MIDIReceived` returning `noErr`.
**Cause:** `MIDINetworkSession.default().sourceEndpoint()` is owned by the network driver, not the app process. Calling `MIDIReceived` on an endpoint you don't own silently does nothing.
**Fix:** Use `MIDISourceCreate(client, name, &source)` to create a process-owned virtual source, then call `MIDIReceived(source, &list)` on that.

---

## New Swift files not found in scope after adding to Xcode project folder
**Error:**
```
Cannot find type 'SequencerState' in scope
Cannot find type 'SequencerMode' in scope
Referencing instance method 'environment(_:)' on 'View' requires the types 'SequencerState' and 'Subject' be equivalent
```
**Cause:** Files were created on disk but not added to the Xcode project target. Swift only compiles files listed in the `.xcodeproj/project.pbxproj` Sources build phase — files on disk that aren't in the project are invisible to the compiler.
**Fix:** Manually edit `project.pbxproj` to add three entries per new file: a `PBXFileReference` (declares the file), a `PBXBuildFile` (adds it to a target), a group membership entry (shows it in the navigator), and a `Sources` build phase entry (compiles it). Then clean build (`Cmd+Shift+K`) and rebuild.

---

## AudioPlayer loops stop after a few seconds — write-mode AVAudioFile
**Error:** Loops recorded by `NodeRecorder` stop repeating after a few seconds instead of looping indefinitely.
**Cause:** `NodeRecorder.audioFile` returns the `AVAudioFile` that was open in write mode during recording. Passing that handle to `AudioPlayer.load(file:)` gives the player an incomplete or write-mode file — it plays what's in the buffer then stops. `isLooping` has nothing to loop.
**Fix (partial):** After `stopRecording()`, extract the URL with `recorder.audioFile?.url` and call `AudioPlayer.load(url:)` instead of passing the write-mode file directly. But this alone doesn't fix looping — see next entry.

---

## AVAudioFile(forWriting:) silently fails with iOS hardware input format settings
**Error:** `ExtAudioFileOpenURL error 2003334207` when loading the recorded file — file doesn't exist because it was never written.
**Cause:** `AVAudioFile(forWriting: url, settings: buf.format.settings)` was called with `try?`, silently failing. The iOS hardware mic input delivers non-interleaved PCM buffers; passing those settings directly to `AVAudioFile(forWriting:)` is rejected because the file writer requires an interleaved format.
**Fix:** Build explicit settings with `AVLinearPCMIsNonInterleaved: false` (and the other standard PCM keys) rather than forwarding `buf.format.settings`. Also replace `try?` with `do/catch` to surface any future file-creation errors.

---

## AVAudioFile(forWriting:) still silently fails — AVFormatIDKey type mismatch
**Error:** `ExtAudioFileOpenURL error 2003334207` persists even after switching to an explicit settings dict.
**Cause:** `kAudioFormatLinearPCM` is typed as `UInt32` in Swift. `AVFormatIDKey` in the settings dictionary expects `Int`. Passing the raw `UInt32` constant is silently rejected. Similarly `buf.format.channelCount` returns `AVAudioChannelCount` (a `UInt32`), which must also be cast.
**Fix:** `AVFormatIDKey: Int(kAudioFormatLinearPCM)` and `AVNumberOfChannelsKey: Int(buf.format.channelCount)`. All numeric values in AVAudioFile settings dicts must be `Int`, not `UInt32`.

---

## Mic sample recorded but buttons do nothing — buffer accumulation race condition
**Error:** Recording UI works, but chord buttons produce no sound after stopping.
**Cause:** The tap callback ran on the audio thread and dispatched `Task { @MainActor { recordingBuffers.append(copy) } }` for each buffer. Those tasks were still queued when `stopRecording()` ran on MainActor and tried to read `recordingBuffers` — the array was empty so no file was written and `hasContent` stayed false.
**Fix:** Write directly to `AVAudioFile` from the tap callback. Create the file lazily on the first buffer (so we have the actual hardware format), write each buffer synchronously, then `nil` the file in `stopRecording()` after `removeTap()` to flush and close it. This eliminates the dispatch entirely. Mark the file reference `nonisolated(unsafe)` — thread safety is guaranteed by the contract that `removeTap()` always precedes any MainActor reads.

---

## installTap crash: IsFormatSampleRateAndChannelCountValid(format)
**Error:** `Terminating app due to uncaught exception 'com.apple.coreaudio.avfaudio', reason: 'required condition is false: IsFormatSampleRateAndChannelCountValid(format)'`
**Cause:** `AVAudioEngine.inputNode.outputFormat(forBus: 0)` returns a format with sample rate 0 when called before the hardware audio session has fully negotiated its format. Passing that zero-rate format to `installTap(onBus:bufferSize:format:block:)` triggers a fatal assertion inside CoreAudio.
**Fix:** Pass `nil` as the format argument to `installTap`. AVAudioEngine then uses the actual negotiated hardware format, and the `buffer` delivered in the tap block already carries the correct format for writing to `AVAudioFile`.

---

## Stray character in source file from external edit breaks function declaration
**Error:** `Expected '{' in body of function declaration` / `Expected 'func' keyword` on a line containing only `b`
**Cause:** A linter or external tool inserted a stray `b` character between two function declarations. Swift sees it as a malformed declaration rather than whitespace.
**Fix:** Delete the stray character — it was on a line by itself between `}` and `func stopRecording`.

---

## AudioPlayer isLooping has no effect without buffered: true
**Error:** Loop plays through once and stops even with `isLooping = true`.
**Cause:** AudioKit 5's non-buffered `AudioPlayer` uses `AVAudioPlayerNode.scheduleFile(_:at:completionHandler:)` internally, which plays through once and stops — `isLooping` is ignored in that path. The `.loops` scheduling option is only used in the buffered code path.
**Fix:** `try players[track].load(url: url, buffered: true)`. Loading into a buffer switches AudioKit to `scheduleBuffer(_:at:options:)` with the `.loops` option, which actually loops.

---

## Buffered AudioPlayer loop pitches down ~1.5 semitones
**Error:** Loops play at the correct pitch with `buffered: false`, but switching to `buffered: true` (required for `isLooping` to work — see previous entry) causes every loop to play back flat.
**Cause:** `AudioPlayer()` is created empty and wired into the mixer at init time via `outputMixer.addInput(p)`. At that moment, `makeInternalConnections()` calls `engine.connect(playerNode, to: mixerNode, format: nil)`. With nil format, `AVAudioEngine` resolves to `AVAudioPlayerNode`'s default output format — 44100 Hz — because the node has no content scheduled yet. Later, `AudioPlayer.load(url:buffered:true)` only reconnects the node if the file format *changed from a previously loaded file*; on the very first load (when `self.file` is nil), no reconnect happens. The node stays wired at 44100 Hz. Loading a 48000 Hz recording file creates a 48 kHz buffer, but `AVAudioPlayerNode.scheduleBuffer` plays it through a 44100 Hz connection — 48000 frames at 44100 fps = ~1.09× slower = ~1.5 semitones flat.
**Fix:** Call `AudioPlayer.load(buffer:)` instead of `load(url:buffered:)`. That overload always checks `playerNode.outputFormat(forBus: 0)` against the buffer's format and disconnects/reconnects if they differ. Build the `AVAudioPCMBuffer` manually from an `AVAudioFile` opened for reading (which uses the file's native 48 kHz `processingFormat`), then pass it to `load(buffer:)`. This forces the node connection to update to 48 kHz before the buffer is scheduled.

---

## NodeRecorder(node:file:) — extra argument 'file' in call
**Error:** `/Audio/Looper.swift Extra argument 'file' in call`
**Cause:** AudioKit 5's `NodeRecorder` init only accepts `node:` — it manages its own internal temp file. Passing a pre-created `AVAudioFile` via a `file:` argument is not part of the public API.
**Fix:** Remove the `AVAudioFile` creation and `file:` argument. Init with `try NodeRecorder(node:)` only, then retrieve the recorded file URL via `recorder.audioFile?.url` after stopping.

---

## Sound only works when headphones are already plugged in at hard-restart
**Symptom:** Audio works when headphones are connected before launching the app, but is silent when the app is opened with no headphones, or when headphones are plugged in after launch.
**Source:** `Audio/AudioSink.swift` — `init()` set the session options before `engine.start()`, and `restartEngine()` only called `engine.start()` with no session configuration.
**Cause:** AudioKit's `engine.start()` internally reconfigures `AVAudioSession`, overwriting the `.defaultToSpeaker` option set before the call. Without that option, iOS routes `.playAndRecord` audio to the earpiece (nearly silent) instead of the built-in speaker. Wired headphones are always preferred by iOS regardless of session options, which is why that one case worked. Additionally, `restartEngine()` (called on route changes) never re-applied the session configuration, so plugging headphones in after launch also failed to produce sound.
**Fix:** Extract session configuration into a `configureSession()` helper that sets `.playAndRecord` + `.mixWithOthers` + `.defaultToSpeaker` and calls `setActive(true)`. Call it both before and after `engine.start()` in `init` (to survive AudioKit's internal reconfiguration), and call it before and after `engine.start()` in `restartEngine()`.

---

## 5-finger UITapGestureRecognizer never fires on window
**Error:** 5-finger simultaneous tap produces no action even with recognizer installed on UIWindow.
**Cause:** Multiple factors: (1) `updateUIView` fires before the view is in the window so the guard exits; (2) iOS system gestures may intercept 5-finger touches before they reach app-level recognizers; (3) `UITapGestureRecognizer` with `numberOfTouchesRequired > 1` is unreliable on iPhone in practice.
**Fix:** Abandoned the approach entirely. Replaced with a 3-second `onLongPressGesture` on the OLED display — simpler, more reliable, and just as unlikely to fire accidentally during performance.

---

## Window gesture recognizer never installed — uiView.window is nil in updateUIView
**Error:** 5-finger tap on window fires nothing; recognizer was never added.
**Cause:** `updateUIView` is called immediately after `makeUIView`, before SwiftUI inserts the view into a window. At that point `uiView.window` is `nil`, so the `guard let window` exits and the recognizer is never installed.
**Fix:** Subclass `UIView` as `TapInstallerView` and override `didMoveToWindow()`, which is called by UIKit after the view is actually placed in the window hierarchy — `self.window` is guaranteed non-nil at that point.

---

## hitTest touch-count check always returns nil — 5-finger gesture never fires
**Error:** 5-finger tap overlay view installs correctly but gesture never triggers.
**Cause:** `hitTest(_:with:)` is called by UIKit one touch at a time as each finger lands. At the moment the first finger is hit-tested, `event.allTouches.count` is 1, not 5. The guard `>= 5` always fails, `nil` is always returned, and the gesture recognizer never receives any touch events.
**Fix:** Move the gesture recognizer off the overlay view entirely — install it on the `UIWindow` instead. Window-level recognizers see all touches without intercepting SwiftUI's gesture responders. Set `isUserInteractionEnabled = false` on the view itself to make it fully touch-transparent. Guard the installation in `updateUIView` with a `name`-based check to prevent duplicates across re-renders.

---

## UIViewRepresentable conformance broken when changing UIView subtype
**Error:** `Type 'FiveFingerTapView' does not conform to protocol 'UIViewRepresentable'`
**Cause:** `makeUIView` was changed to return a concrete `PassthroughView` subclass, but `updateUIView(_:context:)` still had the old `UIView` signature (and was then accidentally deleted). `UIViewRepresentable` requires both `makeUIView` and `updateUIView` with matching `UIViewType` — the associated type is inferred from `makeUIView`'s return type, so `updateUIView` must also accept `PassthroughView`.
**Fix:** Add `func updateUIView(_ uiView: PassthroughView, context: Context) {}` alongside the updated `makeUIView`.

---

## Two AVAudioEngine instances corrupt iOS audio session — black screen on relaunch
**Symptom:** After granting mic permission and tapping REC, the UI stutters, the app becomes unresponsive, the microphone indicator persists after force-close, and the app shows a black screen on relaunch.
**Cause:** `MicSampler` created its own `AVAudioEngine` (`micEngine`) and called `micEngine.start()` while AudioKit's `AudioEngine` was already running. iOS does not reliably support two concurrent `AVAudioEngine` instances — the shared `AVAudioSession` ends up in a corrupted state. The black screen on relaunch is `AudioSink.init()` failing to start its engine because the session is still broken.
**Fix:** Remove `micEngine` from `MicSampler` entirely. Pass AudioKit's `AudioEngine` at init and use `engine.avEngine.inputNode` to install the recording tap. The shared engine is already running; no second `start()` call is needed.

---

## Permission gate check unreachable — early guard exits before switch
**Error:** Tests asserting `state.micSampleState.permissionFlow == .prePrompt` (etc.) fail; value stays nil.
**Cause:** `startMicRecording()` opened with `guard let sampler = engine?.micSampler else { return }`. Tests inject no engine, so the guard exits immediately — the `switch micGate.state` block below it never executes and `permissionFlow` is never set.
**Fix:** Move the `guard let sampler` inside the `.granted` case only. The permission check (setting `permissionFlow`) needs no engine; the engine is only required when permission is confirmed and recording actually starts.

---

## Assigning property to itself — parameter name shadowed by property name
**Error:** `Assigning a property to itself` — `self.micGate = micGate`
**Cause:** The init parameter was named `gate` but the assignment wrote `micGate` (the property name), so Swift resolved `micGate` as `self.micGate` on both sides.
**Fix:** `self.micGate = gate` — use the parameter name on the right-hand side.

---

## FiveFingerTapView intercepts all touches — app appears frozen, buttons unresponsive
**Error:** App renders normally on launch but does not respond to any button presses.
**Cause:** `FiveFingerTapView` (a `UIViewRepresentable`) was placed last in the `ZStack` with no frame, so it expanded to cover the entire screen. UIKit's hit-testing routes all touches to the topmost view first. The `UITapGestureRecognizer(numberOfTouchesRequired: 5)` fails for single-finger taps, but the UIKit touch event is never forwarded back to SwiftUI's gesture recognizers on sibling views beneath it. The result is a fully rendered but completely unresponsive UI.
**Fix:** Subclass `UIView` as `PassthroughView` and override `hitTest(_:with:)` to return `nil` (pass the touch through) unless `event.allTouches.count >= 5`. This makes the overlay invisible to normal touches while still capturing 5-finger taps.

---

## JSONEncoder / JSONSerialization not in scope in test file
**Error:**
```
Tests/LoggingTests/LoggerTests.swift:27:24 Cannot find 'JSONEncoder' in scope
Tests/LoggingTests/LoggerTests.swift:28:24 Cannot find 'JSONSerialization' in scope
```
**Cause:** `LoggerTests.swift` only imported `Testing` and `@testable import Perfecto`. `JSONEncoder` and `JSONSerialization` live in Foundation, which is not automatically available in Swift Testing files without an explicit import.
**Fix:** Add `import Foundation` at the top of the test file.

---

## TestFlight user reports no sound — speaker silent, headphones silent
**Error:** App produces no audio even with volume at max, mute switch off, and headphones plugged in.
**Cause (speaker):** `AVAudioSession.setCategory(.playAndRecord, options: [.mixWithOthers])` without `.defaultToSpeaker` routes audio to the earpiece (the small in-call speaker at the top of the phone) by default. The main speaker never activates, so the user hears nothing at normal listening distance.
**Cause (headphones / silence):** Engine startup errors were caught and only `print`ed — any initialization failure (session conflict, entitlement missing, format rejection) was invisible to developers and left the engine in a dead state.
**Fix:** Add `.defaultToSpeaker` to the session options and add an explicit `mode: .default` parameter. Also add `assertionFailure` alongside the `print` so startup failures crash debug builds immediately instead of silently producing a silent app.

---
