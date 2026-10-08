# MIDI troubleshooting — Perfecto on-device virtual source

## Architecture (v1)

`MidiSink` → `CoreMidiBackend` → `MIDISourceCreateWithProtocol` (protocol `._1_0`) → `MIDIReceivedEventList`

The app registers an on-device virtual source named **"Perfecto"**.

- **Same-device GarageBand**: Settings → GarageBand → MIDI → enable "Perfecto" as a MIDI input.
- **Mac via USB**: virtual sources on iPhone appear automatically as inputs on the Mac side through the USB MIDI bridge — no setup required beyond connecting the cable.
- **Network MIDI (WiFi/RTP-MIDI)**: not used in v1.

---

## Symptom: GarageBand doesn't see "Perfecto" as a MIDI input

### Step 1 — Check `logTopology()` output

Add a call to `MidiSink.logTopology()` at app launch (or call it from the Xcode console via `po MidiSink.logTopology()`). You should see "Perfecto" listed in the sources.

```
[MIDI] topology: N src, M dest
[MIDI]   src[0] Perfecto
```

If "Perfecto" does not appear, `MIDISourceCreateWithProtocol` failed. Check the error printed to console at init time.

### Step 2 — Verify `MIDIReceivedEventList` return codes

The production sink logs `[MIDI] MIDIReceivedEventList error: <code>` when `result != noErr`. Common values:

| OSStatus | Meaning |
|---|---|
| 0 | noErr — success |
| -10844 | kMIDIInvalidClient — client creation failed earlier |
| -10845 | kMIDIInvalidPort |
| -10846 | kMIDIWrongEndpointType — wrong API for endpoint type |

### Step 3 — Check UMP word construction

Each `MIDIEventList` packet is a single 32-bit UMP word with this layout for MIDI 1.0 Channel Voice:

```
Bits 31-28: Message Type = 0x2 (MIDI 1.0 Channel Voice)
Bits 27-24: Group = 0x0
Bits 23-16: Status byte (0x90 = Note On ch1, 0x80 = Note Off ch1)
Bits 15-8:  Note number (0-127)
Bits 7-0:   Velocity
```

Example: Note On, note 60 (C4), velocity 100 → `0x20903C64`
Example: Note Off, note 60, velocity 0   → `0x20803C00`

### Step 4 — GarageBand iOS MIDI input is disabled

Settings app → GarageBand → Advanced → "Allow MIDI Background Audio" and check that the Perfecto virtual source is enabled in GarageBand's MIDI settings panel.

### Step 5 — Source disappears when app is backgrounded

Virtual MIDI sources only live while the creating app is active (or has background audio entitlements). For live use, keep the app in the foreground. For background operation, the app needs `UIBackgroundModes: audio` in Info.plist (already required for the Looper mode).

---

## Testing without a real device

Use `RecordingMidiBackend` in unit tests — it records every `sendNoteOn` / `sendNoteOff` call without touching CoreMIDI. See `Tests/SinkTests/MidiSinkTests.swift`.

---

## Phase-exit checklist

- [ ] `MidiSink.logTopology()` shows "Perfecto" in sources list
- [ ] Note On/Off calls return `noErr` in Xcode console
- [ ] GarageBand on-device receives chords when buttons are pressed in PlayMode
- [ ] Per-note Note Off: each note in the previous voicing is silenced individually before the new voicing plays (no stuck notes)
- [ ] All 5 `MidiSinkTests` pass (⌘U green)
