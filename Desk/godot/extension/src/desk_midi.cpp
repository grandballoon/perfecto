#include "desk_midi.h"

#include <algorithm>
#include <cmath>

#ifdef __APPLE__
#include <CoreFoundation/CoreFoundation.h>
#include <CoreMIDI/CoreMIDI.h>
#endif

using perfecto::desk::Line;

namespace perfecto_godot {

namespace {

uint8_t channel(Line line) { return line == Line::chord ? 0 : 1; }

uint8_t byte(double value) { return uint8_t(std::clamp(std::round(value * 127), 0.0, 127.0)); }

bool contains(const std::vector<int> &notes, int note) {
    return std::find(notes.begin(), notes.end(), note) != notes.end();
}

} // namespace

#ifdef __APPLE__

struct DeskMidi::Port {
    MIDIClientRef client = 0;
    MIDIEndpointRef source = 0;
};

DeskMidi::DeskMidi(const std::string &name) {
    auto port = std::make_unique<Port>();
    const CFStringRef cfName = CFStringCreateWithCString(nullptr, name.c_str(), kCFStringEncodingUTF8);
    const bool made = MIDIClientCreate(cfName, nullptr, nullptr, &port->client) == noErr &&
                      MIDISourceCreateWithProtocol(port->client, cfName, kMIDIProtocol_1_0, &port->source) == noErr;
    CFRelease(cfName);
    if (!made) return;
    port_ = std::move(port);
    for (const Line line : perfecto::desk::allLines) {
        const uint8_t status = 0xB0 | channel(line);
        // RPN 0, pitch bend range, then back to no RPN.
        send({{status, 101, 0}, {status, 100, 0}, {status, 6, bendRange}, {status, 38, 0}, {status, 101, 127},
              {status, 100, 127}});
    }
}

DeskMidi::~DeskMidi() {
    if (!port_) return;
    MIDIEndpointDispose(port_->source);
    MIDIClientDispose(port_->client);
}

/// Sends each message at once, as MIDI 1.0 in universal packets.
void DeskMidi::send(const std::vector<std::array<uint8_t, 3>> &messages) {
    if (!port_ || messages.empty()) return;
    MIDIEventList list;
    MIDIEventPacket *packet = MIDIEventListInit(&list, kMIDIProtocol_1_0);
    for (const auto &message : messages) {
        const uint32_t word = uint32_t(0x20) << 24 | uint32_t(message[0]) << 16 | uint32_t(message[1]) << 8 | message[2];
        packet = MIDIEventListAdd(&list, sizeof list, packet, 0, 1, &word);
        if (!packet) break;
    }
    MIDIReceivedEventList(port_->source, &list);
}

#else

struct DeskMidi::Port {};

DeskMidi::DeskMidi(const std::string &) {}
DeskMidi::~DeskMidi() = default;
void DeskMidi::send(const std::vector<std::array<uint8_t, 3>> &) {}

#endif

bool DeskMidi::isReady() const { return port_ != nullptr; }

void DeskMidi::sound(Line line, const std::vector<int> &notes, double level, double brightness, bool tie) {
    const uint8_t ch = channel(line);
    auto &sounding = sounding_[line];
    std::vector<int> held;
    if (tie)
        for (const int note : sounding)
            if (contains(notes, note)) held.push_back(note);
    std::vector<std::array<uint8_t, 3>> offs;
    for (const int note : sounding)
        if (!contains(held, note)) offs.push_back({uint8_t(0x80 | ch), uint8_t(note), 0});
    send(offs);
    if (!tie) {
        struck_[line] = std::max(0.01, level);
        shape(line, level, brightness, 0);
    }
    const uint8_t velocity = uint8_t(std::clamp(std::round(level * 127), 1.0, 127.0));
    std::vector<std::array<uint8_t, 3>> ons;
    for (const int note : notes)
        if (!contains(held, note)) ons.push_back({uint8_t(0x90 | ch), uint8_t(note), velocity});
    send(ons);
    sounding = notes;
}

void DeskMidi::shape(Line line, double level, double brightness, double bend) {
    const uint8_t ch = channel(line);
    const double range = bendRange;
    const auto bendValue = uint16_t(std::clamp(8192 + std::round(bend / range * 8192), 0.0, 16383.0));
    const auto struck = struck_.find(line);
    const uint8_t expression = byte(level / (struck == struck_.end() ? 1 : struck->second));
    const auto last = sent_.find(line);
    const bool known = last != sent_.end();
    std::vector<std::array<uint8_t, 3>> messages;
    if (!known || last->second.level != expression) messages.push_back({uint8_t(0xB0 | ch), 11, expression});
    if (!known || last->second.brightness != byte(brightness))
        messages.push_back({uint8_t(0xB0 | ch), 74, byte(brightness)});
    if (!known || last->second.bend != bendValue)
        messages.push_back({uint8_t(0xE0 | ch), uint8_t(bendValue & 0x7F), uint8_t(bendValue >> 7)});
    send(messages);
    sent_[line] = {expression, byte(brightness), bendValue};
}

void DeskMidi::silence(Line line) {
    std::vector<std::array<uint8_t, 3>> offs;
    for (const int note : sounding_[line]) offs.push_back({uint8_t(0x80 | channel(line)), uint8_t(note), 0});
    send(offs);
    sounding_[line].clear();
}

void DeskMidi::silenceAll() {
    for (const Line line : perfecto::desk::allLines) silence(line);
}

} // namespace perfecto_godot
