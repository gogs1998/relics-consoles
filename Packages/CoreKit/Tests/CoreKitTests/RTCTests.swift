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
        c.tickRTC(units: Cartridge.rtcUnitsPerSecond * 3)   // 3 s: 23:59:58 day 255 -> 00:00:01 day 256
        #expect(c.rtc[0] == 1 && c.rtc[1] == 0 && c.rtc[2] == 0)
        #expect(c.rtc[3] == 0 && (c.rtc[4] & 1) == 1)
        c.rtc[4] |= 0x40                                      // halted
        c.tickRTC(units: Cartridge.rtcUnitsPerSecond * 10)
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
}
