// Our C glue over the vendored ares cores (ISC). Not part of ares.
//
// Implements ares::Platform so that everything comes from memory: the system "pak" (a VFS
// directory) holds our own SPC700 boot program and the board database; the cartridge pak holds the
// ROM (sliced as ares' boards expect) and the save RAM. No file is ever opened and no firmware is
// ever loaded. The SNES cartridge analysis is a port of ares' own heuristics (mia/medium/
// super-famicom.cpp, ISC) reduced to what the core needs; the Mega Drive part ports the header
// reading of mia/medium/mega-drive.cpp (ISC).
//
// One live handle per process (ares keeps hardware in globals and reports through the global
// `ares::platform`); guarded by `gLive`.
#include "../shim/ares_prelude.h"
#include <ares/ares.hpp>
#include <AresGlue.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <vector>

namespace ares::SuperFamicom {
auto load(Node::System& node, string name) -> bool;
auto option(string name, string value) -> bool;
}
namespace ares::MegaDrive {
auto load(Node::System& node, string name) -> bool;
auto option(string name, string value) -> bool;
}

namespace {

std::atomic<bool> gLive{false};

// ares' heuristic board database (ISC), embedded unmodified from the vendored file.
const unsigned char kBoards[] = {
#embed "../../ares/mia/Database/Super Famicom Boards.bml"
};

// Our own SPC700 boot program, written for this project (not Nintendo's IPL ROM, which we never
// ship). It implements only the publicly documented upload handshake, with its own structure:
// no RAM clear, stack at $FF, destination pointer in $02/$03, and a single data loop that tells
// "not yet" (port 0 still holds the previous index) from "new command" (anything else).
// Protocol: show $AA/$BB on ports 0/1; wait for $CC; each command = destination on ports 2/3,
// command on port 1 (0 = jump there, else receive a block), kick value on port 0 which is echoed;
// block bytes arrive on port 1 tagged with an 8-bit index on port 0, each index echoed back.
// Entry $FFC0 (reset vector at $FFFE). Port 0 is read once per decision (the CPU can change it
// at any moment).
//   FFC0 mov x,#$FF / mov sp,x
//   FFC3 mov $F4,#$AA / mov $F5,#$BB
//   FFC9 cmp $F4,#$CC / bne FFC9
//   FFCE cmd:   movw ya,$F6 / movw $02,ya / mov a,$F4 / mov x,$F5 / mov $F4,a / beq run
//   FFDA        mov y,#0
//   FFDC first: cmp y,$F4 / bne first
//   FFE0 got:   mov a,$F5 / mov [$02]+y,a / mov $F4,y / inc y / bne wait / inc $03
//   FFEB wait:  cmp y,$F4 / beq got / bmi cmd / bra wait   ; ahead of us = a new command
//   FFF3 run:   jmp [$0002+x]            ; x = 0 here
const unsigned char kBootProgram[64] = {
  0xCD, 0xFF, 0xBD, 0x8F, 0xAA, 0xF4, 0x8F, 0xBB, 0xF5, 0x78, 0xCC, 0xF4, 0xD0, 0xFB, 0xBA, 0xF6,
  0xDA, 0x02, 0xE4, 0xF4, 0xF8, 0xF5, 0xC4, 0xF4, 0xF0, 0x19, 0x8D, 0x00, 0x7E, 0xF4, 0xD0, 0xFC,
  0xE4, 0xF5, 0xD7, 0x02, 0xCB, 0xF4, 0xFC, 0xD0, 0x02, 0xAB, 0x03, 0x7E, 0xF4, 0xF0, 0xF1, 0x30,
  0xDD, 0x2F, 0xF8, 0x1F, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0xFF,
};

struct Memory {
  string name;  // ares file name: [architecture.]content.type, lowercase
  u32 size;
  bool rom;
};

// ---- SNES cartridge analysis (port of mia's SuperFamicom heuristics) ----
struct SNESAnalysis {
  bool ok = false;
  bool needsFirmware = false;
  string title, board, region;
  u32 oscillator = 0;
  std::vector<Memory> memory;
};

struct SNESHeader {
  const std::vector<u8>& rom;
  u32 h = 0;  // header address

  auto at(u32 offset) const -> u8 { return h + offset < rom.size() ? rom[h + offset] : 0; }

  auto score(u32 address) const -> u32 {
    s32 score = 0;
    if(rom.size() < address + 0x50) return 0;
    u8 mapMode = rom[address + 0x25] & ~0x10;
    u16 complement = rom[address + 0x2c] | rom[address + 0x2d] << 8;
    u16 checksum = rom[address + 0x2e] | rom[address + 0x2f] << 8;
    u16 reset = rom[address + 0x4c] | rom[address + 0x4d] << 8;
    if(reset < 0x8000) return 0;
    u32 at = (address & ~0x7fff) | (reset & 0x7fff);
    u8 op = at < rom.size() ? rom[at] : 0;
    if(op == 0x78 || op == 0x18 || op == 0x38 || op == 0x9c || op == 0x4c || op == 0x5c) score += 8;
    if(op == 0xc2 || op == 0xe2 || op == 0xad || op == 0xae || op == 0xac || op == 0xaf || op == 0xa9
    || op == 0xa2 || op == 0xa0 || op == 0x20 || op == 0x22) score += 4;
    if(op == 0x40 || op == 0x60 || op == 0x6b || op == 0xcd || op == 0xec || op == 0xcc) score -= 4;
    if(op == 0x00 || op == 0x02 || op == 0xdb || op == 0x42 || op == 0xff) score -= 8;
    if(checksum + complement == 0xffff) score += 4;
    if(address == 0x7fb0 && mapMode == 0x20) score += 2;
    if(address == 0xffb0 && mapMode == 0x21) score += 2;
    return score < 0 ? 0 : score;
  }

  auto label() const -> string {
    string label;
    for(u32 n = 0; n < 0x15; n++) {
      u8 x = at(0x10 + n);
      if(x >= 0x20 && x <= 0x7e) label.append((char)x);
    }
    return label.strip();
  }

  auto serial() const -> string {
    char A = at(2), B = at(3), C = at(4), D = at(5);
    auto valid = [](char n) { return (n >= '0' && n <= '9') || (n >= 'A' && n <= 'Z'); };
    if(at(0x2a) == 0x33 && valid(A) && valid(B) && valid(C) && valid(D)) return string{A, B, C, D};
    return "";
  }

  auto typeLo() const -> u32 { return at(0x26) & 15; }
  auto typeHi() const -> u32 { return at(0x26) >> 4; }
  auto subType() const -> u32 { return at(0x0f); }

  auto firmwareSize() const -> u32 {
    u32 size = rom.size();
    if(serial() == "042J" || (typeLo() == 0x3 && typeHi() == 0xe)) { if((size & 0x7fff) == 0x100) return 0x100; }
    if(typeLo() >= 0x3 && typeHi() == 0xf && subType() == 0x10) { if((size & 0x7fff) == 0xc00) return 0xc00; }
    if(typeLo() >= 0x3 && typeHi() == 0x0) { if((size & 0x7fff) == 0x2000) return 0x2000; }
    if(typeLo() >= 0x3 && typeHi() == 0xf && subType() == 0x01) { if((size & 0xffff) == 0xd000) return 0xd000; }
    if(typeLo() >= 0x3 && typeHi() == 0xf && subType() == 0x02) { if((size & 0x3ffff) == 0x28000) return 0x28000; }
    return 0;
  }
  auto romSize() const -> u32 { return rom.size() - firmwareSize(); }

  auto ramSize() const -> u32 {
    u8 n = at(0x28);
    return n ? (1u << (((n - 1) & 7) + 1)) << 10 : 0;
  }
  auto expansionRamSize() const -> u32 {
    if(at(0x2a) == 0x33) { u32 n = at(0x0d) & 7; if(n) return 1024u << n; }
    if(typeHi() == 1) return 0x8000;
    return 0;
  }

  auto board() const -> string {
    string board;
    u8 mapMode = at(0x25);
    string mode;
    if(mapMode == 0x20 || mapMode == 0x30) mode = "LOROM-";
    if(mapMode == 0x21 || mapMode == 0x31) mode = "HIROM-";
    if(mapMode == 0x22 || mapMode == 0x32) mode = "SDD1-";
    if(mapMode == 0x23 || mapMode == 0x33) mode = "SA1-";
    if(mapMode == 0x25 || mapMode == 0x35) mode = "EXHIROM-";
    if(mapMode == 0x2a || mapMode == 0x3a) mode = "SPC7110-";
    if(!mode) {
      if(h == 0x7fb0) mode = "LOROM-";
      if(h == 0xffb0) mode = "HIROM-";
      if(h == 0x407fb0) mode = "EXLOROM-";
      if(h == 0x40ffb0) mode = "EXHIROM-";
    }
    if(label() == "YUYU NO QUIZ DE GO!GO") mode = "LOROM-";
    if(mode == "LOROM-" && h == 0x407fb0) mode = "EXLOROM-";

    bool epsonRTC = false, sharpRTC = false;
    if(serial() == "ZBSJ") board.append("BS-MCC-");
    else if(serial() == "042J") board.append("GB-", mode);
    else if(serial().match("Z??J")) board.append("BS-", mode);
    else if(typeLo() >= 0x3) {
      if(typeHi() == 0x0) board.append("NEC-", mode);
      if(typeHi() == 0x1) board.append("GSU-");
      if(typeHi() == 0x2) board.append("OBC1-", mode);
      if(typeHi() == 0x3) board.append("SA1-");
      if(typeHi() == 0x4) board.append("SDD1-");
      if(typeHi() == 0x5) board.append(mode), sharpRTC = true;
      if(typeHi() == 0xe && typeLo() == 0x3) board.append("GB-", mode);
      if(typeHi() == 0xf && typeLo() == 0x5 && subType() == 0x00) board.append("SPC7110-");
      if(typeHi() == 0xf && typeLo() == 0x9 && subType() == 0x00) board.append("SPC7110-"), epsonRTC = true;
      if(typeHi() == 0xf && subType() == 0x01) board.append("EXNEC-", mode);
      if(typeHi() == 0xf && subType() == 0x02) board.append("ARM-", mode);
      if(typeHi() == 0xf && subType() == 0x10) board.append("HITACHI-", mode);
    }
    if(!board) board.append(mode);
    if(ramSize() || expansionRamSize()) board.append("RAM-");
    if(epsonRTC) board.append("EPSONRTC-");
    if(sharpRTC) board.append("SHARPRTC-");
    board.trimRight("-", 1L);
    if(board.beginsWith("LOROM-RAM") && romSize() <= 0x200000) board.append("#A");
    if(board.beginsWith("NEC-LOROM-RAM") && romSize() <= 0x100000) board.append("#A");
    if(board.beginsWith("SPC7110-") && romSize() == 0x700000) board.prepend("EX");
    return board;
  }
};

auto analyzeSNES(std::vector<u8>& rom) -> SNESAnalysis {
  SNESAnalysis a;
  if((rom.size() & 0x7fff) == 512) rom.erase(rom.begin(), rom.begin() + 512);  // copier header
  if(rom.size() < 0x8000) return a;

  SNESHeader hd{rom};
  u32 lo = hd.score(0x7fb0), hi = hd.score(0xffb0), exlo = hd.score(0x407fb0), exhi = hd.score(0x40ffb0);
  if(exlo) exlo += 4;
  if(exhi) exhi += 4;
  if(lo >= hi && lo >= exlo && lo >= exhi) hd.h = 0x7fb0;
  else if(hi >= exlo && hi >= exhi) hd.h = 0xffb0;
  else if(exlo >= exhi) hd.h = 0x407fb0;
  else hd.h = 0x40ffb0;

  a.title = hd.label();
  a.board = hd.board();
  u8 region = hd.at(0x29);
  a.region = (region == 0x00 || region == 0x01 || region == 0x0b || region == 0x0d || region == 0x0f || region == 0x10)
           ? "NTSC" : "PAL";

  auto parts = nall::split(string{a.board}.trimRight("#A", 1L), "-");
  if(parts.size() <= 1) parts.resize(2);
  auto& first = parts[0];

  // Super Game Boy needs the Game Boy core and its BIOS; neither is built.
  if(first == "GB") { a.needsFirmware = true; return a; }

  u32 size = hd.romSize();
  if(first == "SPC7110" && size > 0x100000) {
    a.memory.push_back({"program.rom", 0x100000, true});
    a.memory.push_back({"data.rom", size - 0x100000, true});
  } else if(first == "EXSPC7110" && size == 0x700000) {
    a.memory.push_back({"program.rom", 0x100000, true});
    a.memory.push_back({"data.rom", 0x500000, true});
    a.memory.push_back({"expansion.rom", 0x100000, true});
  } else {
    a.memory.push_back({"program.rom", size, true});
  }
  if(auto n = hd.ramSize()) a.memory.push_back({"save.ram", n, false});
  if(auto n = hd.expansionRamSize()) a.memory.push_back({"save.ram", n, false});

  // Coprocessors whose program/data ROM is chip firmware. Usable only if the player's own dump has
  // the firmware appended (as some dumps do); otherwise the game is refused.
  bool firmwareBoard = first == "ARM" || first == "EXNEC" || first == "HITACHI" || first == "NEC";
  if(firmwareBoard && !hd.firmwareSize()) { a.needsFirmware = true; return a; }
  if(first == "ARM") {
    a.memory.push_back({"arm6.program.rom", 0x20000, true});
    a.memory.push_back({"arm6.data.rom", 0x8000, true});
    a.memory.push_back({"arm6.data.ram", 0x4000, false});
    a.oscillator = 21440000;
  } else if(first == "BS" && parts[1] == "MCC") {
    a.memory.push_back({"download.ram", 0x80000, false});
  } else if(first == "EXNEC") {
    a.memory.push_back({"upd96050.program.rom", 0xc000, true});
    a.memory.push_back({"upd96050.data.rom", 0x1000, true});
    a.memory.push_back({"upd96050.data.ram", 0x1000, false});
    a.oscillator = a.title == "2DAN MORITA SHOUGI" ? 15000000 : 11000000;
  } else if(first == "GSU") {
    a.oscillator = 21440000;
  } else if(first == "HITACHI") {
    a.memory.push_back({"hg51bs169.data.rom", 0xc00, true});
    a.memory.push_back({"hg51bs169.data.ram", 0xc00, false});
    a.oscillator = 20000000;
  } else if(first == "NEC") {
    a.memory.push_back({"upd7725.program.rom", 0x1800, true});
    a.memory.push_back({"upd7725.data.rom", 0x800, true});
    a.memory.push_back({"upd7725.data.ram", 0x200, false});
    a.oscillator = 7600000;
  } else if(first == "SA1" || parts[1] == "SA1") {
    a.memory.push_back({"internal.ram", 0x800, false});
  }
  if(parts.back() == "EPSONRTC" || parts.back() == "SHARPRTC") a.memory.push_back({"time.rtc", 0x10, false});

  a.ok = true;
  return a;
}

// ---- Mega Drive header (port of mia's MegaDrive analysis: region, SRAM) ----
struct MDAnalysis {
  string title;
  std::vector<string> regions;
  string ramMode;
  u32 ramAddress = 0, ramSize = 0;
};

auto analyzeMD(const std::vector<u8>& rom) -> MDAnalysis {
  MDAnalysis a;
  auto text = [&](u32 offset, u32 length) {
    string s;
    for(u32 n = 0; n < length && offset + n < rom.size(); n++) {
      char c = rom[offset + n];
      s.append((c < 0x20 || c > 0x7e) ? ' ' : c);
    }
    return s;
  };
  a.title = text(0x150, 48).strip();

  string serial = text(0x180, 14);
  u32 offset = (serial == "GM MK-1563 -00" && rom.size() == 4 * 1024 * 1024) ? 0x200000 : 0;
  string region = string{text(0x1f0 + offset, 16)}.trimRight(" ");
  auto& r = a.regions;
  if(region == "JAPAN") r.push_back("NTSC-J");
  if(region == "EUROPE") r.push_back("PAL");
  if(r.empty()) {
    if(region.find("J") || region.find("K")) r.push_back("NTSC-J");
    if(region.find("U")) r.push_back("NTSC-U");
    if(region.find("E")) r.push_back("PAL");
  }
  if(r.empty() && region.size() == 1) {
    char f = region(0);
    int bits = (f >= '0' && f <= '9') ? f - '0' : (f >= 'A' && f <= 'F') ? f - 'A' + 10 : 0;
    if(bits & 1) r.push_back("NTSC-J");
    if(bits & 4) r.push_back("NTSC-U");
    if(bits & 8) r.push_back("PAL");
  }
  if(r.empty()) r = {"NTSC-J", "NTSC-U", "PAL"};

  u32 o = 0x1b0 + offset;
  if(o + 12 <= rom.size() && rom[o] == 'R' && rom[o + 1] == 'A') {
    u32 from = rom[o + 4] << 24 | rom[o + 5] << 16 | rom[o + 6] << 8 | rom[o + 7];
    u32 to = rom[o + 8] << 24 | rom[o + 9] << 16 | rom[o + 10] << 8 | rom[o + 11];
    if(!(from & 1) && !(to & 1)) a.ramMode = "upper";
    if((from & 1) && (to & 1)) a.ramMode = "lower";
    if(!(from & 1) && (to & 1)) a.ramMode = "word";
    if(a.ramMode == "upper" || a.ramMode == "lower") a.ramSize = (to - from + 2) >> 1;
    if(a.ramMode == "word") a.ramSize = to - from + 1;
    a.ramAddress = from & ~1;
    if(a.ramSize > 1024 * 1024) a.ramMode = "", a.ramSize = 0;  // nonsense header
  }
  return a;
}

}  // namespace

struct AresHandle : ares::Platform {
  AresSystem kind;
  ares::Node::System root;
  ares::VFS::Pak systemPak, gamePak;
  std::vector<ares::Node::Audio::Stream> streams;
  double audioRate = 48000;
  double refreshRate = 60;
  bool pal = false;
  // Held buttons per controller port (index 0 = port 1).
  uint32_t buttons[2] = {0, 0};
  // The peripherals connected to ports 1 and 2 (identifies which port a polled button belongs to).
  const void* peripheral[2] = {nullptr, nullptr};
  // Debug: per port, how many button reads the core made and which pressed bits it saw,
  // since the start of the last ares_run_frame.
  uint32_t debugReads[2] = {0, 0};
  uint32_t debugSeen[2] = {0, 0};
  ares::Event lastEvent = ares::Event::None;
  uint32_t frames = 0;

  // Video arrives on ares' screen thread; guarded by `videoMutex`.
  std::mutex videoMutex;
  std::condition_variable videoCV;
  uint64_t videoCount = 0;
  std::vector<uint32_t> frame;
  uint32_t width = 0, height = 0;
  std::vector<uint32_t> published;  // copy handed to the caller
  uint32_t publishedWidth = 0, publishedHeight = 0;

  std::vector<float> samples;

  // ---- ares::Platform ----
  auto attach(ares::Node::Object node) -> void override {
    // The visible picture only (ares' frontend default), not the full overscan canvas.
    if(auto screen = node->cast<ares::Node::Video::Screen>()) screen->setOverscan(false);
    if(auto stream = node->cast<ares::Node::Audio::Stream>()) {
      stream->setResamplerFrequency(audioRate);
      streams.push_back(stream);
    }
  }

  auto detach(ares::Node::Object node) -> void override {
    if(auto stream = node->cast<ares::Node::Audio::Stream>()) std::erase(streams, stream);
  }

  auto pak(ares::Node::Object node) -> std::shared_ptr<vfs::directory> override {
    auto name = node->name();
    if(name == "Super Famicom" || name == "Mega Drive") return systemPak;
    if(name == "Super Famicom Cartridge" || name == "Mega Drive Cartridge") return gamePak;
    return {};
  }

  auto event(ares::Event e) -> void override { lastEvent = e; }

  auto refreshRateHint(double rate) -> void override { if(rate > 1) refreshRate = rate; }

  auto video(ares::Node::Video::Screen, const u32* data, u32 pitch, u32 w, u32 h) -> void override {
    std::lock_guard<std::mutex> lock(videoMutex);
    u32 stride = pitch / sizeof(u32);
    if(kind == ARES_SYSTEM_SNES && w == 512) {
      // ares draws every SNES pixel twice; collapse to 256 unless the frame uses hi-res.
      bool doubled = true;
      for(u32 y = 0; y < h && doubled; y++) {
        auto line = data + y * stride;
        for(u32 x = 0; x < w; x += 2) if(line[x] != line[x + 1]) { doubled = false; break; }
      }
      if(doubled) return store(data, stride, 2, 256, h);
      return store(data, stride, 1, 512, h);
    }
    if(kind == ARES_SYSTEM_MD && w == 1280) {
      // ares draws H40 (320) pixels 4 wide and H32 (256) pixels 5 wide.
      auto uniform = [&](u32 n) {
        for(u32 y = 0; y < h; y++) {
          auto line = data + y * stride;
          for(u32 x = 0; x < w; x += n) for(u32 k = 1; k < n; k++) if(line[x + k] != line[x]) return false;
        }
        return true;
      };
      if(!uniform(4) && uniform(5)) return store(data, stride, 5, 256, h);
      return store(data, stride, 4, 320, h);
    }
    store(data, stride, 1, w, h);
  }

  auto store(const u32* data, u32 stride, u32 step, u32 w, u32 h) -> void {
    frame.resize(size_t(w) * h);
    for(u32 y = 0; y < h; y++) {
      auto src = data + y * stride;
      auto dst = frame.data() + size_t(y) * w;
      for(u32 x = 0; x < w; x++) dst[x] = src[x * step] | 0xff000000u;
    }
    width = w;
    height = h;
    videoCount++;
    videoCV.notify_all();
  }

  auto audio(ares::Node::Audio::Stream) -> void override {
    while(true) {
      for(auto& s : streams) if(!s->pending()) return;
      double sum = 0;
      for(auto& s : streams) {
        f64 buffer[8] = {};
        u32 channels = s->read(buffer);
        if(channels == 1) sum += buffer[0];
        else if(channels >= 2) sum += (buffer[0] + buffer[1]) * 0.5;
      }
      if(sum > 1) sum = 1;
      if(sum < -1) sum = -1;
      samples.push_back(float(sum));
      // Nobody draining (paused host): keep at most the last second.
      if(samples.size() > size_t(audioRate) * 2) samples.erase(samples.begin(), samples.begin() + size_t(audioRate));
    }
  }

  auto input(ares::Node::Input::Input node) -> void override {
    auto button = node->cast<ares::Node::Input::Button>();
    if(!button) return;
    auto name = node->name();
    uint32_t bit = 0;
    if(name == "Up") bit = ARES_BTN_UP;
    else if(name == "Down") bit = ARES_BTN_DOWN;
    else if(name == "Left") bit = ARES_BTN_LEFT;
    else if(name == "Right") bit = ARES_BTN_RIGHT;
    else if(name == "Start") bit = ARES_BTN_START;
    else if(name == "Select" || name == "Mode") bit = ARES_BTN_SELECT;
    else if(kind == ARES_SYSTEM_SNES) {
      if(name == "B") bit = ARES_SNES_B;
      else if(name == "Y") bit = ARES_SNES_Y;
      else if(name == "A") bit = ARES_SNES_A;
      else if(name == "X") bit = ARES_SNES_X;
      else if(name == "L") bit = ARES_SNES_L;
      else if(name == "R") bit = ARES_SNES_R;
    } else {
      if(name == "A") bit = ARES_MD_A;
      else if(name == "B") bit = ARES_MD_B;
      else if(name == "C") bit = ARES_MD_C;
      else if(name == "X") bit = ARES_MD_X;
      else if(name == "Y") bit = ARES_MD_Y;
      else if(name == "Z") bit = ARES_MD_Z;
    }
    u32 port = 0;
    if(auto parent = node->parent().lock()) {
      if(peripheral[1] && (const void*)parent.get() == peripheral[1]) port = 1;
    }
    bool pressed = bit && (buttons[port] & bit);
    button->setValue(pressed);
    debugReads[port]++;
    if(pressed) debugSeen[port] |= bit;
  }

  // ---- helpers ----
  auto runUntilFrame() -> void {
    uint64_t before;
    {
      std::lock_guard<std::mutex> lock(videoMutex);
      before = videoCount;
    }
    for(int guard = 0; guard < 64; guard++) {
      lastEvent = ares::Event::None;
      root->run();
      if(lastEvent == ares::Event::Frame) break;
    }
    // The screen node converts and delivers the frame on its own thread; wait for it.
    std::unique_lock<std::mutex> lock(videoMutex);
    videoCV.wait_for(lock, std::chrono::milliseconds(250), [&] { return videoCount > before; });
    if(width && height) {
      published = frame;
      publishedWidth = width;
      publishedHeight = height;
    }
  }
};

static void setError(char* error, size_t size, const char* text) {
  if(error && size) { std::strncpy(error, text, size - 1); error[size - 1] = 0; }
}

// The same pad type in controller ports 1 and 2.
static void connectPads(AresHandle* h, const char* type) {
  const char* names[2] = {"Controller Port 1", "Controller Port 2"};
  for(int i = 0; i < 2; i++) {
    if(auto port = h->root->find<ares::Node::Port>(names[i])) {
      auto pad = port->allocate(type);
      port->connect();
      h->peripheral[i] = pad ? (const void*)static_cast<ares::Core::Object*>(pad.get()) : nullptr;
    }
  }
}

static bool buildSNES(AresHandle* h, std::vector<u8> rom, const uint8_t* save, size_t saveSize, char* error, size_t errorSize) {
  auto a = analyzeSNES(rom);
  if(a.needsFirmware) { setError(error, errorSize, "firmware"); return false; }
  if(!a.ok) { setError(error, errorSize, "rom"); return false; }

  h->systemPak = std::make_shared<vfs::directory>();
  h->systemPak->append("ipl.rom", std::span<const u8>{kBootProgram, sizeof kBootProgram});
  h->systemPak->append("boards.bml", std::span<const u8>{kBoards, sizeof kBoards});

  auto& pak = h->gamePak = std::make_shared<vfs::directory>();
  pak->setAttribute("title", a.title);
  pak->setAttribute("board", a.board);
  pak->setAttribute("region", a.region);
  if(a.oscillator) pak->setAttribute("oscillator", string{a.oscillator});

  size_t offset = 0;
  for(auto& m : a.memory) {
    if(m.rom) {
      if(offset + m.size > rom.size()) break;
      pak->append(m.name, std::span<const u8>{rom.data() + offset, m.size});
      offset += m.size;
    } else {
      if(pak->find(m.name)) continue;
      pak->append(m.name, (u64)m.size);
      if(m.name == "save.ram" && save && saveSize) {
        if(auto fp = pak->write(m.name)) std::memcpy(fp->data(), save, std::min<size_t>(saveSize, m.size));
      }
    }
  }

  h->pal = a.region == "PAL";
  // The fast scanline PPU ("Pixel Accuracy" off), as ares' own frontend defaults to.
  ares::SuperFamicom::option("Pixel Accuracy", "false");
  if(!ares::SuperFamicom::load(h->root, {"[Nintendo] Super Famicom (", a.region, ")"})) {
    setError(error, errorSize, "load");
    return false;
  }
  if(auto port = h->root->find<ares::Node::Port>("Cartridge Slot")) { port->allocate(); port->connect(); }
  connectPads(h, "Gamepad");
  return true;
}

static bool buildMD(AresHandle* h, std::vector<u8> rom, const uint8_t* save, size_t saveSize, char* error, size_t errorSize) {
  if(rom.size() < 0x200) { setError(error, errorSize, "rom"); return false; }
  if(rom.size() & 1) rom.push_back(0);
  auto a = analyzeMD(rom);

  // Region preference when the cartridge allows several: NTSC-U, then NTSC-J, then PAL.
  string region = "PAL";
  if(std::ranges::find(a.regions, string{"NTSC-J"}) != a.regions.end()) region = "NTSC-J";
  if(std::ranges::find(a.regions, string{"NTSC-U"}) != a.regions.end()) region = "NTSC-U";

  h->systemPak = std::make_shared<vfs::directory>();  // no TMSS ROM: TMSS stays off
  auto& pak = h->gamePak = std::make_shared<vfs::directory>();
  pak->setAttribute("title", a.title);
  pak->setAttribute("region", nall::merge(a.regions, ", "));
  pak->setAttribute("bootable", string{"true"});
  pak->append("program.rom", std::span<const u8>{rom.data(), rom.size()});
  if(a.ramSize) {
    pak->append("save.ram", (u64)a.ramSize);
    if(auto fp = pak->write("save.ram")) {
      if(save && saveSize) std::memcpy(fp->data(), save, std::min<size_t>(saveSize, a.ramSize));
      fp->setAttribute("mode", a.ramMode);
      fp->setAttribute("address", string{a.ramAddress});
      fp->setAttribute("enable", string{"false"});
    }
  }

  h->pal = region == "PAL";
  ares::MegaDrive::option("TMSS", "false");
  if(!ares::MegaDrive::load(h->root, {"[Sega] Mega Drive (", region, ")"})) {
    setError(error, errorSize, "load");
    return false;
  }
  if(auto port = h->root->find<ares::Node::Port>("Cartridge Slot")) { port->allocate(); port->connect(); }
  connectPads(h, "Fighting Pad");
  return true;
}

extern "C" {

AresHandle* ares_create(AresSystem system, const uint8_t* rom, size_t romSize, const uint8_t* save,
                        size_t saveSize, double audioRate, char* error, size_t errorSize) {
  if(!rom || romSize == 0 || romSize > 64 * 1024 * 1024) { setError(error, errorSize, "rom"); return nullptr; }
  bool expected = false;
  if(!gLive.compare_exchange_strong(expected, true)) { setError(error, errorSize, "busy"); return nullptr; }

  auto h = new AresHandle;
  h->kind = system;
  h->audioRate = audioRate > 0 ? audioRate : 48000;
  ares::platform = h;

  std::vector<u8> data(rom, rom + romSize);
  bool ok = system == ARES_SYSTEM_SNES ? buildSNES(h, std::move(data), save, saveSize, error, errorSize)
          : system == ARES_SYSTEM_MD ? buildMD(h, std::move(data), save, saveSize, error, errorSize)
          : false;
  if(ok && !h->root) ok = false;
  if(!ok) {
    if(h->root) h->root->unload();
    h->root.reset();
    ares::platform = nullptr;
    delete h;
    gLive = false;
    return nullptr;
  }
  h->root->power(false);
  return h;
}

void ares_destroy(AresHandle* h) {
  if(!h) return;
  if(h->root) h->root->unload();
  h->root.reset();
  h->streams.clear();
  ares::platform = nullptr;
  delete h;
  gLive = false;
}

void ares_reset(AresHandle* h) { h->root->power(true); }

void ares_run_frame(AresHandle* h, uint32_t buttons) {
  h->buttons[0] = buttons;
  h->debugReads[0] = h->debugReads[1] = 0;
  h->debugSeen[0] = h->debugSeen[1] = 0;
  h->runUntilFrame();
  h->frames++;
}

const uint32_t* ares_framebuffer(const AresHandle* h, uint32_t* width, uint32_t* height) {
  if(width) *width = h->publishedWidth;
  if(height) *height = h->publishedHeight;
  return h->published.data();
}

size_t ares_drain_audio(AresHandle* h, const float** out) {
  static thread_local std::vector<float> drained;
  drained.swap(h->samples);
  h->samples.clear();
  *out = drained.data();
  return drained.size();
}

void ares_discard_audio(AresHandle* h) { h->samples.clear(); }

size_t ares_battery(AresHandle* h, uint8_t** out) {
  *out = nullptr;
  h->root->save();  // flushes cartridge memory into the pak
  auto fp = h->gamePak ? h->gamePak->read("save.ram") : nullptr;
  if(!fp || !fp->size()) return 0;
  auto size = (size_t)fp->size();
  *out = (uint8_t*)std::malloc(size);
  std::memcpy(*out, fp->data(), size);
  return size;
}

size_t ares_save_state(AresHandle* h, uint8_t** out) {
  *out = nullptr;
  auto s = h->root->serialize(true);
  if(!s.size()) return 0;
  *out = (uint8_t*)std::malloc(s.size());
  std::memcpy(*out, s.data(), s.size());
  return s.size();
}

bool ares_load_state(AresHandle* h, const uint8_t* data, size_t size) {
  if(!data || !size) return false;
  serializer s(data, (u32)size);
  return h->root->unserialize(s);
}

void ares_set_input(AresHandle* h, uint32_t port, uint32_t buttons) {
  if(port < 2) h->buttons[port] = buttons;
}

void ares_run_frame_ports(AresHandle* h) {
  h->debugReads[0] = h->debugReads[1] = 0;
  h->debugSeen[0] = h->debugSeen[1] = 0;
  h->runUntilFrame();
  h->frames++;
}

uint32_t ares_debug_port_reads(const AresHandle* h, uint32_t port, uint32_t* seen) {
  if(port >= 2) { if(seen) *seen = 0; return 0; }
  if(seen) *seen = h->debugSeen[port];
  return h->debugReads[port];
}

void ares_free(void* p) { std::free(p); }

double ares_frame_rate(const AresHandle* h) { return h->refreshRate; }
uint32_t ares_frame_counter(const AresHandle* h) { return h->frames; }
bool ares_is_pal(const AresHandle* h) { return h->pal; }

}
