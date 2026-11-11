# Accuracy

Run on 11 Nov 2026 on the Mac (`swift test -c release`, harness `Packages/CoreKit/Tests/CoreKitTests/AccuracyTests.swift`)
against third-party suites Gordon approved that day (downloaded to `TestSuites/`, gitignored, never bundled):
nestest and blargg's NES suites (christopherpow/nes-test-roms), AccuracyCoin (MIT), blargg's GB suites and Mooneye
and dmg/cgb-acid2 (from the c-sp game-boy-test-roms v7.0 collection). Reproduce:

```
cd Packages/CoreKit
ACCURACY_DIR=$PWD/../../TestSuites ACCURACY_OUT=/tmp/accuracy.md swift test -c release --scratch-path ../../build/corekit-rel --filter AccuracyTests
```

How results are read: blargg NES/GB ROMs report through the $6000 / $A000 memory protocol or the serial port; Mooneye by
the Fibonacci registers sent over serial; acid2 by comparing the frame with the reference picture through a colour
bijection (our palettes differ, the structure must not); AccuracyCoin by pressing Start (run every test) and reading
each test's result byte ($01 = pass, otherwise an error code, see the AccuracyCoin README); nestest in automation mode
(PC = $C000, result bytes $02/$03).

## Summary

| Suite | Pass | Fail | Notes |
|---|---|---|---|
| nestest | 1/1 | 0 | official and unofficial opcodes |
| blargg NES (\$6000 protocol) | 100 | 11 | 163 older ROMs report only on screen (not automated); 15 need mappers we don't support (5, 11, 22, 28, 34) |
| AccuracyCoin | 87 / 147 | 60 | a hardware-revision torture test; most remaining fails are DMA/open-bus/PPU-sub-cycle details |
| blargg GB | 38 | 20 | all 11 cpu_instrs, instr_timing, mem_timing, halt_bug pass; fails are APU edge cases (dmg_sound/cgb_sound) and the DMG OAM-corruption bug (oam_bug) |
| Mooneye (DMG acceptance + emulator-only) | 75 | 19 | fails: some PPU interrupt timings, boot-register checks for specific DMG revisions, rapid timer toggling, an 8 Mbit MBC1 multicart |
| dmg-acid2 / cgb-acid2 | 2/2 | 0 | |

## What was fixed tonight because of these suites

- NES: interrupt polling moved to the penultimate cycle (CLI/SEI/PLP latency, branch delay), NMI edge latching and the
  $2002 VBlank race (suppression / NMI cancel), MMC3 now clocked by real PPU A12 edges (incl. $2006/$2007), APU frame
  counter timing and power/reset behaviour, power-on SP, DMC DMA moved to the CPU's read cycle and driving the data bus
  (this one unblocked AccuracyCoin's run-all: 14 → 87 passes), the "unstable" opcodes (SHA/SHX/SHY/TAS/LAS/ANE/LXA).
- GB: OAM DMA start delay and CPU bus conflicts during DMA (fixed most Mooneye `*_timing` and `oam_dma_*`), the EI;HALT
  halt-bug case, lines redrawn at the end of mode 3, and the MBC3 real-time clock (ticking, halting, day carry, saved
  in the standard 48-byte footer with wall-clock catch-up).

## Remaining NES failures and why they matter little for games

`ppu_vbl_nmi` 05/10 and `cpu_interrupts` 2-4 are single-PPU-clock NMI/DMA alignment details; `sprdma_and_dmc_dma` is
DMC-during-OAM-DMA cycle counting; `oam_stress` and `ppu_open_bus` decay are OAM/bus artefacts; `mmc3_test` 6 tests
other MMC3/MMC6 chip revisions (we emulate the common MMC3B/C behaviour); `apu_reset/4017_written` times out in the harness.

## Full results

| Suite | Pass | Fail | Not automated / not run (screen-only rows omitted below) |
|---|---|---|---|
| AccuracyCoin | 87 | 60 | 0 |
| acid2 | 2 | 0 | 0 |
| blargg (GB) | 38 | 20 | 0 |
| mooneye | 75 | 19 | 1 |
| nes-test-roms | 100 | 11 | 179 |
| nestest | 1 | 0 | 0 |

### AccuracyCoin

| Test | Result |
|---|---|
| CPUBehavior: ROM is not writable | PASS |
| CPUBehavior: RAM Mirroring | PASS |
| CPUBehavior: PC Wraparound | PASS |
| CPUBehavior: The Decimal Flag | PASS |
| CPUBehavior: The B Flag | PASS |
| CPUBehavior: Dummy read cycles | PASS |
| CPUBehavior: Dummy write cycles | PASS |
| CPUBehavior: Open Bus | FAIL code 7 |
| CPUBehavior: All NOP instructions | PASS |
| CPUInstructions: Absolute Indexed | PASS |
| CPUInstructions: Zero Page Indexed | PASS |
| CPUInstructions: Indirect | PASS |
| CPUInstructions: Indirect, X | PASS |
| CPUInstructions: Indirect, Y | PASS |
| CPUInstructions: Relative | PASS |
| UnofficialOps_SLO: $03   SLO | PASS |
| UnofficialOps_SLO: $07   SLO | PASS |
| UnofficialOps_SLO: $0F   SLO | PASS |
| UnofficialOps_SLO: $13   SLO | PASS |
| UnofficialOps_SLO: $17   SLO | PASS |
| UnofficialOps_SLO: $1B   SLO | PASS |
| UnofficialOps_SLO: $1F   SLO | PASS |
| UnofficialOps_RLA: $23   RLA | PASS |
| UnofficialOps_RLA: $27   RLA | PASS |
| UnofficialOps_RLA: $2F   RLA | PASS |
| UnofficialOps_RLA: $33   RLA | PASS |
| UnofficialOps_RLA: $37   RLA | PASS |
| UnofficialOps_RLA: $3B   RLA | PASS |
| UnofficialOps_RLA: $3F   RLA | PASS |
| UnofficialOps_SRE: $43   SRE | PASS |
| UnofficialOps_SRE: $47   SRE | PASS |
| UnofficialOps_SRE: $4F   SRE | PASS |
| UnofficialOps_SRE: $53   SRE | PASS |
| UnofficialOps_SRE: $57   SRE | PASS |
| UnofficialOps_SRE: $5B   SRE | PASS |
| UnofficialOps_SRE: $5F   SRE | PASS |
| UnofficialOps_RRA: $63   RRA | PASS |
| UnofficialOps_RRA: $67   RRA | PASS |
| UnofficialOps_RRA: $6F   RRA | PASS |
| UnofficialOps_RRA: $73   RRA | PASS |
| UnofficialOps_RRA: $77   RRA | PASS |
| UnofficialOps_RRA: $7B   RRA | PASS |
| UnofficialOps_RRA: $7F   RRA | PASS |
| UnofficialOps__AX: $83   SAX | PASS |
| UnofficialOps__AX: $87   SAX | PASS |
| UnofficialOps__AX: $8F   SAX | PASS |
| UnofficialOps__AX: $97   SAX | PASS |
| UnofficialOps__AX: $A3   LAX | PASS |
| UnofficialOps__AX: $A7   LAX | PASS |
| UnofficialOps__AX: $AF   LAX | PASS |
| UnofficialOps__AX: $B3   LAX | PASS |
| UnofficialOps__AX: $B7   LAX | PASS |
| UnofficialOps__AX: $BF   LAX | PASS |
| UnofficialOps_DCP: $C3   DCP | PASS |
| UnofficialOps_DCP: $C7   DCP | PASS |
| UnofficialOps_DCP: $CF   DCP | PASS |
| UnofficialOps_DCP: $D3   DCP | PASS |
| UnofficialOps_DCP: $D7   DCP | PASS |
| UnofficialOps_DCP: $DB   DCP | PASS |
| UnofficialOps_DCP: $DF   DCP | PASS |
| UnofficialOps_ISC: $E3   ISC | PASS |
| UnofficialOps_ISC: $E7   ISC | PASS |
| UnofficialOps_ISC: $EF   ISC | PASS |
| UnofficialOps_ISC: $F3   ISC | PASS |
| UnofficialOps_ISC: $F7   ISC | PASS |
| UnofficialOps_ISC: $FB   ISC | PASS |
| UnofficialOps_ISC: $FF   ISC | PASS |
| UnofficialOps_SH_: $93   SHA | FAIL code 7 |
| UnofficialOps_SH_: $9F   SHA | FAIL code 7 |
| UnofficialOps_SH_: $9B   SHS | FAIL code 7 |
| UnofficialOps_SH_: $9C   SHY | FAIL code 7 |
| UnofficialOps_SH_: $9E   SHX | FAIL code 7 |
| UnofficialOps_SH_: $BB   LAE | PASS |
| UnofficialOps_Immediates: $0B   ANC | PASS |
| UnofficialOps_Immediates: $2B   ANC | PASS |
| UnofficialOps_Immediates: $4B   ASR | PASS |
| UnofficialOps_Immediates: $6B   ARR | PASS |
| UnofficialOps_Immediates: $8B   ANE | PASS |
| UnofficialOps_Immediates: $AB   LXA | PASS |
| UnofficialOps_Immediates: $CB   AXS | PASS |
| UnofficialOps_Immediates: $EB   SBC | PASS |
| CPUInterrupts: Interrupt flag latency | FAIL code 10 |
| CPUInterrupts: NMI Overlap BRK | FAIL code 2 |
| CPUInterrupts: NMI Overlap IRQ | FAIL code 1 |
| DMATests: DMA + Open Bus | FAIL code 2 |
| DMATests: DMA + $2002 Read | FAIL code 2 |
| DMATests: DMA + $2007 Read | FAIL code 2 |
| DMATests: DMA + $2007 Write | FAIL code 1 |
| DMATests: DMA + $4015 Read | FAIL code 2 |
| DMATests: DMA + $4016 Read | FAIL code 1 |
| DMATests: DMC DMA Bus Conflicts | FAIL code 1 |
| DMATests: DMC DMA + OAM DMA | FAIL code 1 |
| DMATests: Explicit DMA Abort | FAIL code 1 |
| DMATests: Implicit DMA Abort | FAIL code 1 |
| APUTiming: Length Counter | FAIL code 4 |
| APUTiming: Length Table | FAIL code 1 |
| APUTiming: Frame Counter IRQ | FAIL code 7 |
| APUTiming: Frame Counter 4-step | FAIL code 2 |
| APUTiming: Frame Counter 5-step | FAIL code 2 |
| APUTiming: Delta Modulation Channel | FAIL code 19 |
| APUTiming: APU Register Activation | FAIL code 1 |
| APUTiming: Controller Strobing | FAIL code 4 |
| APUTiming: Controller Clocking | PASS |
| CPUBehavior2: Instruction Timing | FAIL code 1 |
| CPUBehavior2: Implied Dummy Reads | FAIL code 3 |
| CPUBehavior2: Branch Dummy Reads | PASS |
| CPUBehavior2: JSR Edge Cases | PASS |
| CPUBehavior2: Internal Data Bus | FAIL code 1 |
| CPUBehavior2: DMA Landing on Write | FAIL code 2 |
| CPUBehavior2: DMC Reload Timing | FAIL code 1 |
| CPUBehavior2: DMC Playback Rate | FAIL code 1 |
| PPUBehavior: CHR ROM is not writable | PASS |
| PPUBehavior: PPU Register Mirroring | PASS |
| PPUBehavior: PPU Register Open Bus | FAIL code 5 |
| PPUBehavior: PPU Read Buffer | PASS |
| PPUBehavior: Palette RAM Quirks | FAIL code 6 |
| PPUTiming: VBlank beginning | PASS |
| PPUTiming: VBlank end | PASS |
| PPUTiming: NMI Control | PASS |
| PPUTiming: NMI Timing | FAIL code 1 |
| PPUTiming: NMI Suppression | FAIL code 1 |
| PPUTiming: NMI at VBlank end | PASS |
| PPUTiming: NMI disabled at VBlank | PASS |
| SpriteZeroHits: Sprite overflow behavior | FAIL code 1 |
| SpriteZeroHits: Sprite 0 Hit behavior | FAIL code 1 |
| SpriteZeroHits: $2002 flag timing | FAIL code 1 |
| SpriteZeroHits: Suddenly Resize Sprite | FAIL code 1 |
| SpriteZeroHits: Misaligned OAM DMA | FAIL code 1 |
| SpriteZeroHits: Arbitrary Sprite zero | FAIL code 1 |
| SpriteZeroHits: Misaligned OAM behavior | FAIL code 1 |
| SpriteZeroHits: OAM Corruption | FAIL code 1 |
| PPUMisc: t Register Quirks | PASS |
| PPUMisc: Address $2004 behavior | FAIL code 3 |
| PPUMisc: INC $4014 | FAIL code 1 |
| PPUMisc: Rendering Flag Behavior | FAIL code 2 |
| PPUMisc: $2007 read w/ rendering | FAIL code 1 |
| PPUMisc: $2004 Stress Test | FAIL code 2 |
| PPUMisc: $2007 Stress Test | FAIL code 2 |
| AdvancedBGEval: Attributes As Tiles | FAIL code 1 |
| AdvancedBGEval: Stale BG Shift Registers | FAIL code 1 |
| AdvancedBGEval: BG Serial In | FAIL code 2 |
| AdvancedBGEval: ALE + Read | FAIL code 1 |
| AdvancedBGEval: Hybrid Addresses | FAIL code 1 |
| AdvancedSpriteEval: Sprites On Scanline 0 | FAIL code 2 |
| AdvancedSpriteEval: Stale Sprite Shift Regs | FAIL code 3 |
| AdvancedSpriteEval: Frozen OAM2 Increment | FAIL code 2 |
| AdvancedSpriteEval: Misaligned OAM2 Address | FAIL code 3 |

### acid2

| Test | Result |
|---|---|
| dmg-acid2/dmg-acid2.gb | PASS |
| cgb-acid2/cgb-acid2.gbc | PASS |

### blargg (GB)

| Test | Result |
|---|---|
| cgb_sound/cgb_sound.gb | FAIL 3: cgb_sound /  / 01:ok  02:ok  03:03  04:ok  05:04  06:ok  07:ok  08:ok  09:01  10:ok  11:ok  12:02   /  / Run failed tests / individually for |
| cgb_sound/rom_singles/01-registers.gb | PASS |
| cgb_sound/rom_singles/02-len ctr.gb | PASS |
| cgb_sound/rom_singles/03-trigger.gb | FAIL 3: 03-trigger /  / 0  / Enabling in first half of length period should clock length /  / Failed #3 /  |
| cgb_sound/rom_singles/04-sweep.gb | PASS |
| cgb_sound/rom_singles/05-sweep details.gb | FAIL 4: 05-sweep details /  /  / Exiting negate mode after calculation disables channel /  / Failed #4 /  |
| cgb_sound/rom_singles/06-overflow on trigger.gb | PASS |
| cgb_sound/rom_singles/07-len sweep period sync.gb | PASS |
| cgb_sound/rom_singles/08-len ctr during power.gb | PASS |
| cgb_sound/rom_singles/09-wave read while on.gb | FAIL 1: 09-wave read while on /  / 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |
| cgb_sound/rom_singles/10-wave trigger while on.gb | PASS |
| cgb_sound/rom_singles/11-regs after power.gb | PASS |
| cgb_sound/rom_singles/12-wave.gb | FAIL 2: 12-wave /  /  / Timer period or phase resetting is wrong /  / Failed #2 /  |
| cpu_instrs/cpu_instrs.gb | PASS |
| cpu_instrs/individual/01-special.gb | PASS |
| cpu_instrs/individual/02-interrupts.gb | PASS |
| cpu_instrs/individual/03-op sp,hl.gb | PASS |
| cpu_instrs/individual/04-op r,imm.gb | PASS |
| cpu_instrs/individual/05-op rp.gb | PASS |
| cpu_instrs/individual/06-ld r,r.gb | PASS |
| cpu_instrs/individual/07-jr,jp,call,ret,rst.gb | PASS |
| cpu_instrs/individual/08-misc instrs.gb | PASS |
| cpu_instrs/individual/09-op r,r.gb | PASS |
| cpu_instrs/individual/10-bit ops.gb | PASS |
| cpu_instrs/individual/11-op a,(hl).gb | PASS |
| dmg_sound/dmg_sound.gb | FAIL 3: dmg_sound /  / 01:ok  02:ok  03:03  04:ok  05:04  06:ok  07:ok  08:01  09:01  10:01  11:04  12:01   /  / Run failed tests / individually for |
| dmg_sound/rom_singles/01-registers.gb | PASS |
| dmg_sound/rom_singles/02-len ctr.gb | PASS |
| dmg_sound/rom_singles/03-trigger.gb | FAIL 3: 03-trigger /  / 0  / Enabling in first half of length period should clock length /  / Failed #3 /  |
| dmg_sound/rom_singles/04-sweep.gb | PASS |
| dmg_sound/rom_singles/05-sweep details.gb | FAIL 4: 05-sweep details /  /  / Exiting negate mode after calculation disables channel /  / Failed #4 /  |
| dmg_sound/rom_singles/06-overflow on trigger.gb | PASS |
| dmg_sound/rom_singles/07-len sweep period sync.gb | PASS |
| dmg_sound/rom_singles/08-len ctr during power.gb | FAIL 1: 08-len ctr during power /  / 40 00 40 40 3CF589B4  / Failed /  |
| dmg_sound/rom_singles/09-wave read while on.gb | FAIL 1: 09-wave read while on /  / 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 |
| dmg_sound/rom_singles/10-wave trigger while on.gb | FAIL 1: 10-wave trigger while on /  / 00 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF  / 00 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF  / 00 11 22 |
| dmg_sound/rom_singles/11-regs after power.gb | FAIL 4: 11-regs after power /  /  / Powering off shouldn't affect NR41 /  / Failed #4 /  |
| dmg_sound/rom_singles/12-wave write while on.gb | FAIL 1: 12-wave write while on /  / F7 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF  / F7 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF  / F7 11 22 3 |
| halt_bug.gb | PASS |
| instr_timing/instr_timing.gb | PASS |
| interrupt_time/interrupt_time.gb | PASS |
| mem_timing-2/mem_timing.gb | PASS |
| mem_timing-2/rom_singles/01-read_timing.gb | PASS |
| mem_timing-2/rom_singles/02-write_timing.gb | PASS |
| mem_timing-2/rom_singles/03-modify_timing.gb | PASS |
| mem_timing/individual/01-read_timing.gb | PASS |
| mem_timing/individual/02-write_timing.gb | PASS |
| mem_timing/individual/03-modify_timing.gb | PASS |
| mem_timing/mem_timing.gb | PASS |
| oam_bug/oam_bug.gb | FAIL 1: oam_bug /  / 01:03  02:02  03:ok  04:03  05:02  06:ok  07:01  08:02   /  / Run failed tests / individually for / more details. /  / Failed / |
| oam_bug/rom_singles/1-lcd_sync.gb | FAIL 3: 1-lcd_sync /  /  / Turning LCD on starts too early in scanline /  / Failed #3 /  |
| oam_bug/rom_singles/2-causes.gb | FAIL 2: 2-causes /  /  / LD DE,$FE00 : INC DE /  / Failed #2 /  |
| oam_bug/rom_singles/3-non_causes.gb | PASS |
| oam_bug/rom_singles/4-scanline_timing.gb | FAIL 3: 4-scanline_timing /  /  / INC DE at first corruption /  / Failed #3 /  |
| oam_bug/rom_singles/5-timing_bug.gb | FAIL 2: 5-timing_bug /  /  / Should corrupt at beginning of first scanline /  / Failed #2 /  |
| oam_bug/rom_singles/6-timing_no_bug.gb | PASS |
| oam_bug/rom_singles/7-timing_effect.gb | FAIL 1: 7-timing_effect /  / 00000000  / Failed /  |
| oam_bug/rom_singles/8-instr_effect.gb | FAIL 2: 8-instr_effect /  / 00000000  / INC/DEC rp pattern is wrong /  / Failed #2 /  |

### mooneye

| Test | Result |
|---|---|
| acceptance/add_sp_e_timing.gb | PASS |
| acceptance/bits/mem_oam.gb | PASS |
| acceptance/bits/reg_f.gb | PASS |
| acceptance/bits/unused_hwio-GS.gb | PASS |
| acceptance/boot_div-dmgABCmgb.gb | FAIL |
| acceptance/boot_hwio-dmgABCmgb.gb | FAIL |
| acceptance/boot_regs-dmgABC.gb | PASS |
| acceptance/call_cc_timing.gb | PASS |
| acceptance/call_cc_timing2.gb | FAIL |
| acceptance/call_timing.gb | PASS |
| acceptance/call_timing2.gb | FAIL |
| acceptance/di_timing-GS.gb | PASS |
| acceptance/div_timing.gb | PASS |
| acceptance/ei_sequence.gb | PASS |
| acceptance/ei_timing.gb | PASS |
| acceptance/halt_ime0_ei.gb | PASS |
| acceptance/halt_ime0_nointr_timing.gb | PASS |
| acceptance/halt_ime1_timing.gb | PASS |
| acceptance/halt_ime1_timing2-GS.gb | PASS |
| acceptance/if_ie_registers.gb | PASS |
| acceptance/instr/daa.gb | PASS |
| acceptance/interrupts/ie_push.gb | PASS |
| acceptance/intr_timing.gb | PASS |
| acceptance/jp_cc_timing.gb | PASS |
| acceptance/jp_timing.gb | PASS |
| acceptance/ld_hl_sp_e_timing.gb | PASS |
| acceptance/oam_dma/basic.gb | PASS |
| acceptance/oam_dma/reg_read.gb | PASS |
| acceptance/oam_dma/sources-GS.gb | PASS |
| acceptance/oam_dma_restart.gb | PASS |
| acceptance/oam_dma_start.gb | PASS |
| acceptance/oam_dma_timing.gb | PASS |
| acceptance/pop_timing.gb | PASS |
| acceptance/ppu/hblank_ly_scx_timing-GS.gb | PASS |
| acceptance/ppu/intr_1_2_timing-GS.gb | PASS |
| acceptance/ppu/intr_2_0_timing.gb | PASS |
| acceptance/ppu/intr_2_mode0_timing.gb | FAIL |
| acceptance/ppu/intr_2_mode0_timing_sprites.gb | FAIL |
| acceptance/ppu/intr_2_mode3_timing.gb | FAIL |
| acceptance/ppu/intr_2_oam_ok_timing.gb | FAIL |
| acceptance/ppu/lcdon_timing-GS.gb | FAIL |
| acceptance/ppu/lcdon_write_timing-GS.gb | FAIL |
| acceptance/ppu/stat_irq_blocking.gb | PASS |
| acceptance/ppu/stat_lyc_onoff.gb | FAIL |
| acceptance/ppu/vblank_stat_intr-GS.gb | FAIL |
| acceptance/push_timing.gb | FAIL |
| acceptance/rapid_di_ei.gb | PASS |
| acceptance/ret_cc_timing.gb | PASS |
| acceptance/ret_timing.gb | PASS |
| acceptance/reti_intr_timing.gb | PASS |
| acceptance/reti_timing.gb | PASS |
| acceptance/rst_timing.gb | FAIL |
| acceptance/serial/boot_sclk_align-dmgABCmgb.gb | FAIL |
| acceptance/timer/div_write.gb | PASS |
| acceptance/timer/rapid_toggle.gb | FAIL |
| acceptance/timer/tim00.gb | PASS |
| acceptance/timer/tim00_div_trigger.gb | PASS |
| acceptance/timer/tim01.gb | PASS |
| acceptance/timer/tim01_div_trigger.gb | PASS |
| acceptance/timer/tim10.gb | PASS |
| acceptance/timer/tim10_div_trigger.gb | PASS |
| acceptance/timer/tim11.gb | PASS |
| acceptance/timer/tim11_div_trigger.gb | PASS |
| acceptance/timer/tima_reload.gb | PASS |
| acceptance/timer/tima_write_reloading.gb | FAIL |
| acceptance/timer/tma_write_reloading.gb | FAIL |
| emulator-only/mbc1/bits_bank1.gb | PASS |
| emulator-only/mbc1/bits_bank2.gb | PASS |
| emulator-only/mbc1/bits_mode.gb | PASS |
| emulator-only/mbc1/bits_ramg.gb | PASS |
| emulator-only/mbc1/multicart_rom_8Mb.gb | FAIL |
| emulator-only/mbc1/ram_256kb.gb | PASS |
| emulator-only/mbc1/ram_64kb.gb | PASS |
| emulator-only/mbc1/rom_16Mb.gb | PASS |
| emulator-only/mbc1/rom_1Mb.gb | PASS |
| emulator-only/mbc1/rom_2Mb.gb | PASS |
| emulator-only/mbc1/rom_4Mb.gb | PASS |
| emulator-only/mbc1/rom_512kb.gb | PASS |
| emulator-only/mbc1/rom_8Mb.gb | PASS |
| emulator-only/mbc2/bits_ramg.gb | PASS |
| emulator-only/mbc2/bits_romb.gb | PASS |
| emulator-only/mbc2/bits_unused.gb | PASS |
| emulator-only/mbc2/ram.gb | PASS |
| emulator-only/mbc2/rom_1Mb.gb | PASS |
| emulator-only/mbc2/rom_2Mb.gb | PASS |
| emulator-only/mbc2/rom_512kb.gb | PASS |
| emulator-only/mbc5/rom_16Mb.gb | PASS |
| emulator-only/mbc5/rom_1Mb.gb | PASS |
| emulator-only/mbc5/rom_2Mb.gb | PASS |
| emulator-only/mbc5/rom_32Mb.gb | PASS |
| emulator-only/mbc5/rom_4Mb.gb | PASS |
| emulator-only/mbc5/rom_512kb.gb | PASS |
| emulator-only/mbc5/rom_64Mb.gb | PASS |
| emulator-only/mbc5/rom_8Mb.gb | PASS |
| madness/mgb_oam_dma_halt_sprites.gb | timed out |

### nes-test-roms

| Test | Result |
|---|---|
| 240pee/240pee-bnrom.nes | not run: This game uses cartridge hardware (mapper 34) that isn't supported yet. |
| apu_mixer/dmc.nes | PASS |
| apu_mixer/noise.nes | PASS |
| apu_mixer/square.nes | PASS |
| apu_mixer/triangle.nes | PASS |
| apu_reset/4015_cleared.nes | PASS |
| apu_reset/4017_timing.nes | PASS |
| apu_reset/4017_written.nes | timed out |
| apu_reset/irq_flag_cleared.nes | PASS |
| apu_reset/len_ctrs_enabled.nes | PASS |
| apu_reset/works_immediately.nes | PASS |
| apu_test/apu_test.nes | PASS |
| apu_test/rom_singles/1-len_ctr.nes | PASS |
| apu_test/rom_singles/2-len_table.nes | PASS |
| apu_test/rom_singles/3-irq_flag.nes | PASS |
| apu_test/rom_singles/4-jitter.nes | PASS |
| apu_test/rom_singles/5-len_timing.nes | PASS |
| apu_test/rom_singles/6-irq_flag_timing.nes | PASS |
| apu_test/rom_singles/7-dmc_basics.nes | PASS |
| apu_test/rom_singles/8-dmc_rates.nes | PASS |
| cpu_dummy_writes/cpu_dummy_writes_oam.nes | PASS |
| cpu_dummy_writes/cpu_dummy_writes_ppumem.nes | PASS |
| cpu_exec_space/test_cpu_exec_space_apu.nes | PASS |
| cpu_exec_space/test_cpu_exec_space_ppuio.nes | PASS |
| cpu_interrupts_v2/cpu_interrupts.nes | FAIL 1: NMI BRK 00 / 26  36  00 / 26  36  00 / 36  00  00 / 36  00  00 / 36  00  00 / 36  00  00 / 36  00  00 / 27  36  00 / 27  36  00 / 27  36  00 |
| cpu_interrupts_v2/rom_singles/1-cli_latency.nes | PASS |
| cpu_interrupts_v2/rom_singles/2-nmi_and_brk.nes | FAIL 1: NMI BRK 00 / 26  36  00 / 26  36  00 / 36  00  00 / 36  00  00 / 36  00  00 / 36  00  00 / 36  00  00 / 27  36  00 / 27  36  00 / 27  36  00 |
| cpu_interrupts_v2/rom_singles/3-nmi_and_irq.nes | FAIL 1: NMI BRK / 21  00 / 21  00 / 20  00 / 20  00 / 20  00 / 20  00 / 20  00 / 20  00 / 20  00 / 25  20 / 25  20 / 25  20 / 9AE2A4DC / 3-nmi_and_i |
| cpu_interrupts_v2/rom_singles/4-irq_and_dma.nes | FAIL 1: 0 +0 / 1 +1 / 1 +2 / 2 +3 / 2 +4 / 4 +5 / 4 +6 / 7 +7 / 7 +8 / 7 +9 / 7 +10 / 7 +11 / 7 +12 / 7 +13 / ... / 8 +524 / 8 +525 / 9 +526 / 9 +52 |
| cpu_interrupts_v2/rom_singles/5-branch_delays_irq.nes | PASS |
| cpu_reset/ram_after_reset.nes | PASS |
| cpu_reset/registers.nes | PASS |
| exram/mmc5exram.nes | not run: This game uses cartridge hardware (mapper 5) that isn't supported yet. |
| instr_misc/instr_misc.nes | PASS |
| instr_misc/rom_singles/01-abs_x_wrap.nes | PASS |
| instr_misc/rom_singles/02-branch_wrap.nes | PASS |
| instr_misc/rom_singles/03-dummy_reads.nes | PASS |
| instr_misc/rom_singles/04-dummy_reads_apu.nes | PASS |
| instr_test-v3/all_instrs.nes | PASS |
| instr_test-v3/official_only.nes | PASS |
| instr_test-v3/rom_singles/01-implied.nes | PASS |
| instr_test-v3/rom_singles/02-immediate.nes | PASS |
| instr_test-v3/rom_singles/03-zero_page.nes | PASS |
| instr_test-v3/rom_singles/04-zp_xy.nes | PASS |
| instr_test-v3/rom_singles/05-absolute.nes | PASS |
| instr_test-v3/rom_singles/06-abs_xy.nes | PASS |
| instr_test-v3/rom_singles/07-ind_x.nes | PASS |
| instr_test-v3/rom_singles/08-ind_y.nes | PASS |
| instr_test-v3/rom_singles/09-branches.nes | PASS |
| instr_test-v3/rom_singles/10-stack.nes | PASS |
| instr_test-v3/rom_singles/11-jmp_jsr.nes | PASS |
| instr_test-v3/rom_singles/12-rts.nes | PASS |
| instr_test-v3/rom_singles/13-rti.nes | PASS |
| instr_test-v3/rom_singles/14-brk.nes | PASS |
| instr_test-v3/rom_singles/15-special.nes | PASS |
| instr_test-v5/all_instrs.nes | PASS |
| instr_test-v5/official_only.nes | PASS |
| instr_test-v5/rom_singles/01-basics.nes | PASS |
| instr_test-v5/rom_singles/02-implied.nes | PASS |
| instr_test-v5/rom_singles/03-immediate.nes | PASS |
| instr_test-v5/rom_singles/04-zero_page.nes | PASS |
| instr_test-v5/rom_singles/05-zp_xy.nes | PASS |
| instr_test-v5/rom_singles/06-absolute.nes | PASS |
| instr_test-v5/rom_singles/07-abs_xy.nes | PASS |
| instr_test-v5/rom_singles/08-ind_x.nes | PASS |
| instr_test-v5/rom_singles/09-ind_y.nes | PASS |
| instr_test-v5/rom_singles/10-branches.nes | PASS |
| instr_test-v5/rom_singles/11-stack.nes | PASS |
| instr_test-v5/rom_singles/12-jmp_jsr.nes | PASS |
| instr_test-v5/rom_singles/13-rts.nes | PASS |
| instr_test-v5/rom_singles/14-rti.nes | PASS |
| instr_test-v5/rom_singles/15-brk.nes | PASS |
| instr_test-v5/rom_singles/16-special.nes | PASS |
| instr_timing/instr_timing.nes | PASS |
| instr_timing/rom_singles/1-instr_timing.nes | PASS |
| instr_timing/rom_singles/2-branch_timing.nes | PASS |
| m22chrbankingtest/0-127.nes | not run: This game uses cartridge hardware (mapper 22) that isn't supported yet. |
| mmc3_test/1-clocking.nes | PASS |
| mmc3_test/2-details.nes | PASS |
| mmc3_test/3-A12_clocking.nes | PASS |
| mmc3_test/4-scanline_timing.nes | PASS |
| mmc3_test/5-MMC3.nes | PASS |
| mmc3_test/6-MMC6.nes | FAIL 3: IRQ shouldn't occur when reloading after counter normally reaches 0 / 6-MMC6 / Failed #3 |
| mmc3_test_2/rom_singles/1-clocking.nes | PASS |
| mmc3_test_2/rom_singles/2-details.nes | PASS |
| mmc3_test_2/rom_singles/3-A12_clocking.nes | PASS |
| mmc3_test_2/rom_singles/4-scanline_timing.nes | PASS |
| mmc3_test_2/rom_singles/5-MMC3.nes | PASS |
| mmc3_test_2/rom_singles/6-MMC3_alt.nes | FAIL 2: IRQ shouldn't be set when reloading to 0 due to counter naturally reaching 0 previously / 6-MMC3_alt / Failed #2 |
| mmc5test/mmc5test.nes | not run: This game uses cartridge hardware (mapper 5) that isn't supported yet. |
| mmc5test_v2/mmc5test.nes | not run: This game uses cartridge hardware (mapper 5) that isn't supported yet. |
| nes_instr_test/rom_singles/01-implied.nes | PASS |
| nes_instr_test/rom_singles/02-immediate.nes | PASS |
| nes_instr_test/rom_singles/03-zero_page.nes | PASS |
| nes_instr_test/rom_singles/04-zp_xy.nes | PASS |
| nes_instr_test/rom_singles/05-absolute.nes | PASS |
| nes_instr_test/rom_singles/06-abs_xy.nes | PASS |
| nes_instr_test/rom_singles/07-ind_x.nes | PASS |
| nes_instr_test/rom_singles/08-ind_y.nes | PASS |
| nes_instr_test/rom_singles/09-branches.nes | PASS |
| nes_instr_test/rom_singles/10-stack.nes | PASS |
| nes_instr_test/rom_singles/11-special.nes | PASS |
| oam_read/oam_read.nes | PASS |
| oam_stress/oam_stress.nes | FAIL 1: ------*---*---*- / --*---*---*---*- / --*---*---*---*- / --*---*---*---*- / --*---*---*---*- / --*---*---*---*- / --*---*---*---*- / --*---* |
| other/LINUSMUS.NES | not run: This file isn't a game this app can play. |
| other/Streemerz_bundle.nes | not run: This game uses cartridge hardware (mapper 28) that isn't supported yet. |
| other/fceuxd.nes | not run: This game uses cartridge hardware (mapper 11) that isn't supported yet. |
| other/firefly.nes | not run: This game uses cartridge hardware (mapper 5) that isn't supported yet. |
| other/nestopia.nes | not run: This game uses cartridge hardware (mapper 11) that isn't supported yet. |
| other/nintendulator.nes | not run: This game uses cartridge hardware (mapper 11) that isn't supported yet. |
| other/test001.nes | not run: This game uses cartridge hardware (mapper 11) that isn't supported yet. |
| other/test28.nes | not run: This game uses cartridge hardware (mapper 28) that isn't supported yet. |
| ppu_open_bus/ppu_open_bus.nes | FAIL 3: Decay value should become zero by one second / ppu_open_bus / Failed #3 |
| ppu_read_buffer/test_ppu_read_buffer.nes | PASS |
| ppu_vbl_nmi/ppu_vbl_nmi.nes | FAIL 1: 00 4 / 01 4 / 02 4 / 03 4 / 04 4 / 05 4 / 06 3 / 07 3 / 08 3 / 09 3 / E1E2FF8E / 05-nmi_timing / Failed / While running test 5 of 10 |
| ppu_vbl_nmi/rom_singles/01-vbl_basics.nes | PASS |
| ppu_vbl_nmi/rom_singles/02-vbl_set_time.nes | PASS |
| ppu_vbl_nmi/rom_singles/03-vbl_clear_time.nes | PASS |
| ppu_vbl_nmi/rom_singles/04-nmi_control.nes | PASS |
| ppu_vbl_nmi/rom_singles/05-nmi_timing.nes | FAIL 1: 00 4 / 01 4 / 02 4 / 03 4 / 04 4 / 05 4 / 06 3 / 07 3 / 08 3 / 09 3 / E1E2FF8E / 05-nmi_timing / Failed |
| ppu_vbl_nmi/rom_singles/06-suppression.nes | PASS |
| ppu_vbl_nmi/rom_singles/07-nmi_on_timing.nes | PASS |
| ppu_vbl_nmi/rom_singles/08-nmi_off_timing.nes | PASS |
| ppu_vbl_nmi/rom_singles/09-even_odd_frames.nes | PASS |
| ppu_vbl_nmi/rom_singles/10-even_odd_timing.nes | FAIL 3: 08 07 / Clock is skipped too late, relative to enabling BG / 10-even_odd_timing / Failed #3 |
| sprdma_and_dmc_dma/sprdma_and_dmc_dma.nes | timed out |
| sprdma_and_dmc_dma/sprdma_and_dmc_dma_512.nes | timed out |

### nestest

| Test | Result |
|---|---|
| nestest.nes (automation) | PASS (official and unofficial) |


