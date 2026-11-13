import CoreKit
import Foundation
@testable import GBCore
import Testing

/// MBC3 real-time clock: ticks with emulated time, honours halt, carries days, and survives a
/// battery save with wall-clock catch-up.
@Suite struct RTCTests {
    func cart(type: UInt8 = 0x10) throws -> Cartridge {
        var rom = [UInt8](repeating: 0, count: 0x8000)
        rom[0x147] = type
        rom[0x149] = 0x02
        return try Cartridge(rom: Data(rom))
    }

    func select(_ c: Cartridge, reg: UInt8) {
        c.writeROM(0x0000, 0x0A)       // RAM/RTC enable
        c.writeROM(0x4000, reg)
    }

    @Test func ticksAndRolls() throws {
        let c = try cart()
        c.rtc = [58, 59, 23, 0xFF, 0x00]
        c.addRTC(microseconds: Cartridge.rtcUnitsPerSecond * 3)   // 3 s: 23:59:58 day 255 -> 00:00:01 day 256
        #expect(c.rtc[0] == 1 && c.rtc[1] == 0 && c.rtc[2] == 0)
        #expect(c.rtc[3] == 0 && (c.rtc[4] & 1) == 1)
        c.rtc[4] |= 0x40                                      // halted
        c.addRTC(microseconds: Cartridge.rtcUnitsPerSecond * 10)
        #expect(c.rtc[0] == 1)
        c.rtc = [0, 0, 0, 0xFF, 0x01]                         // day 511 -> carry
        c.advanceRTC(seconds: 86_400)
        #expect((c.rtc[4] & 0x80) != 0 && c.rtc[3] == 0 && (c.rtc[4] & 1) == 0)
    }

    @Test func latchAndRegisters() throws {
        let c = try cart()
        c.rtc = [10, 20, 5, 7, 0]
        c.writeROM(0x6000, 0); c.writeROM(0x6000, 1)          // latch
        select(c, reg: 0x09)
        #expect(c.readRAM(0xA000) == 20)
        c.writeRAM(0xA000, 0xFF)                              // minutes masked to 6 bits
        #expect(c.rtc[1] == 0x3F)
    }

    @Test func batteryRoundTripCatchesUp() throws {
        let c = try cart()
        c.rtc = [0, 0, 12, 3, 0]
        let saved = try #require(c.batteryData(now: Date(timeIntervalSince1970: 1_000_000)))
        #expect(saved.count == 0x2000 + 48)
        let d = try cart()
        d.loadBattery(saved, now: Date(timeIntervalSince1970: 1_000_000 + 3_725))   // 1 h 2 min 5 s later
        #expect(d.rtc[0] == 5 && d.rtc[1] == 2 && d.rtc[2] == 13 && d.rtc[3] == 3)
        // A clock cart without RAM (type $0F) still saves its clock.
        let e = try cart(type: 0x0F)
        #expect(e.batteryData()?.count == 48)
    }

    /// A clock the test moves by hand.
    final class FakeClock: @unchecked Sendable { var now = 2_000_000_000.0 }

    /// A minimal MBC3+RTC+RAM+battery cartridge image that just loops.
    func clockROM() -> Data {
        var rom = [UInt8](repeating: 0, count: 0x8000)
        rom[0x100] = 0x18; rom[0x101] = 0xFE   // JR -2
        rom[0x147] = 0x10
        rom[0x149] = 0x02
        return Data(rom)
    }

    @Test func ticksInRealTimeNotEmulatedTime() throws {
        let gb = try GBSystem(rom: clockROM(), battery: nil)
        let clock = FakeClock()
        gb.cart.wallClock = { clock.now }
        gb.cart.rtcLastWall = clock.now
        // 600 frames (10 s of emulated time) in 1 s of real time: the clock moves 1 s.
        for i in 0..<600 {
            if i % 60 == 0 { clock.now += 1.0 / 10 }
            gb.runFrame(input: [])
        }
        #expect(gb.cart.rtc[0] == 1)
        // Paused for 90 s (no frames run): the next frame catches up.
        clock.now += 90
        gb.runFrame(input: [])
        #expect(gb.cart.rtc[0] == 31 && gb.cart.rtc[1] == 1)
        // A wall clock set back is ignored, not run backwards.
        clock.now -= 3_600
        gb.runFrame(input: [])
        #expect(gb.cart.rtc[0] == 31 && gb.cart.rtc[1] == 1)
    }

    @Test func saveStateCatchesUpAndOldStatesStillLoad() throws {
        let gb = try GBSystem(rom: clockROM(), battery: nil)
        let clock = FakeClock()
        gb.cart.wallClock = { clock.now }
        gb.cart.rtcLastWall = clock.now
        gb.cart.rtc = [0, 0, 10, 0, 0]
        let state = gb.saveState()
        #expect(state.suffix(12).prefix(4) == Data("RTCW".utf8))
        clock.now += 2 * 3_600 + 5      // two hours later
        try gb.loadState(state)
        #expect(gb.cart.rtc[2] == 12 && gb.cart.rtc[0] == 5)
        // A state from before the wall-time section (12 bytes shorter) loads and just carries on.
        try gb.loadState(state.dropLast(12))
        #expect(gb.cart.rtc[2] == 10 && gb.cart.rtc[0] == 0)
        clock.now += 1
        gb.runFrame(input: [])
        #expect(gb.cart.rtc[0] == 1)
    }

    /// The footer byte for byte: 10 little-endian words, then a 64-bit little-endian timestamp.
    @Test func footerLayoutIsTheCommonFormat() throws {
        let c = try cart()
        c.rtc = [7, 8, 9, 0x2A, 0x81]
        c.rtcLatched = [1, 2, 3, 4, 0x01]
        let d = try #require(c.batteryData(now: Date(timeIntervalSince1970: 0x0102_0304)))
        let f = [UInt8](d.suffix(48))
        #expect(Array(f[0..<20]) == [7, 0, 0, 0, 8, 0, 0, 0, 9, 0, 0, 0, 0x2A, 0, 0, 0, 0x81, 0, 0, 0])
        #expect(Array(f[20..<40]) == [1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0, 1, 0, 0, 0])
        #expect(Array(f[40..<48]) == [4, 3, 2, 1, 0, 0, 0, 0])
        // The 32-bit-timestamp variant (44-byte footer) loads too.
        let e = try cart()
        e.loadBattery(d.prefix(d.count - 4), now: Date(timeIntervalSince1970: 0x0102_0304 + 61))
        #expect(e.rtc[0] == 8 && e.rtc[1] == 9 && e.rtcLatched[0] == 1)
    }

    /// Fable review: time paused after the last frame must not vanish when a state or the battery
    /// is written during the pause (both are stamped with the registers' own moment).
    @Test func timePausedBeforeASaveIsKept() throws {
        let gb = try GBSystem(rom: clockROM(), battery: nil)
        let clock = FakeClock()
        gb.cart.wallClock = { clock.now }
        gb.cart.rtcLastWall = clock.now
        gb.runFrame(input: [])
        clock.now += 600                     // ten minutes in the pause menu, no frames
        let state = gb.saveState()
        let battery = try #require(gb.batteryRAM)
        try gb.loadState(state)
        #expect(gb.cart.rtc[1] == 10)
        let fresh = try GBSystem(rom: clockROM(), battery: nil)
        fresh.cart.wallClock = { clock.now }
        fresh.cart.loadBattery(battery)
        #expect(fresh.cart.rtc[1] == 10)
    }
}
