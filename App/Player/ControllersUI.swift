import CoreKit
import SwiftUI

/// What the second screen (or the space below the game) shows while a physical controller plays:
/// save-state slots, rewind / fast-forward, the menu, who's playing, and the hotkey combos.
struct ControllerCompanion: View {
    let model: PlayerModel
    var onQuit: () -> Void
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "gamecontroller.fill")
                    .font(.rounded(.title3))
                    .foregroundStyle(Theme.ember)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(padSummary)
                        .font(.rounded(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text("Touch controls hidden")
                        .font(.rounded(.caption))
                        .foregroundStyle(Theme.inkDim)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                CompanionKey(symbol: "backward.fill", label: "Rewind (hold)", active: model.rewinding) { model.setRewind($0) }
                CompanionKey(symbol: "forward.fill", label: "Fast forward (hold)", active: model.fastForward) { model.setFastForward($0) }
                Button { model.menuOpen = true } label: {
                    Image(systemName: "ellipsis").font(.rounded(.footnote, weight: .bold)).frame(width: 34, height: 34)
                }
                .buttonStyle(ChipStyle(selected: false, dense: true))
                .accessibilityLabel("Menu")
            }
            SlotShelf(model: model, compact: compact)
            if !compact {
                hotkeyHints
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.28))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
        )
    }

    private var padSummary: String {
        let active = model.gamepads.pads.filter { $0.player != nil }
        if active.count >= 2 { return "\(active.count) controllers" }
        return active.first?.name ?? "Controller"
    }

    private var hotkeyHints: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HOTKEYS")
                .font(.rounded(.caption2, weight: .heavy)).tracking(1.4)
                .foregroundStyle(Theme.inkDim)
            ForEach(model.gamepads.mapping.hotkeys, id: \.self) { h in
                HStack {
                    Text(ControllersSheet.comboName(h)).font(.rounded(.caption, weight: .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(ControllersSheet.hotkeyName(h.hotkey)).font(.rounded(.caption)).foregroundStyle(Theme.inkDim)
                }
            }
        }
    }
}

/// Controllers: who plays which player, remapping (controller and keyboard), hotkeys, the stick.
struct ControllersSheet: View {
    let model: PlayerModel
    @State private var waitingFor: String?

    private var hub: GamepadHub { model.gamepads }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if hub.pads.isEmpty {
                        Text("No controller connected. Pair one in Settings › Bluetooth; it can join at any time, even mid-game.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(hub.pads) { pad in
                        Picker(selection: Binding(get: { pad.player ?? -1 }, set: { hub.assign(pad.id, to: $0 < 0 ? nil : $0) })) {
                            Text("Player 1").tag(0)
                            if model.players > 1 { Text("Player 2").tag(1) }
                            Text("Not playing").tag(-1)
                        } label: {
                            Label(pad.name, systemImage: "gamecontroller")
                        }
                    }
                    if hub.keyboardConnected {
                        Label("Keyboard (player 1)", systemImage: "keyboard")
                    }
                    Toggle("Keep touch controls visible", isOn: Binding(get: { model.keepTouchControls },
                                                                        set: { model.keepTouchControls = $0 }))
                } header: {
                    Text("Connected")
                } footer: {
                    Text(model.players > 1 ? "This system has two controller ports: give a second controller to player 2."
                                           : "This system has one controller port.")
                }

                Section("Controller buttons") {
                    ForEach(Self.buttons(for: model.game.system), id: \.1) { item in
                        row(item.1, value: hub.mapping.inputs(pressing: item.0).map(Self.physicalName).joined(separator: ", "),
                            id: "pad.\(item.0.rawValue)") {
                            waitingFor = "Press a controller button for \(item.1)"
                            hub.beginCapture { inputs in
                                var m = hub.mapping
                                for p in m.inputs(pressing: item.0) { m.bind(p, to: (m.buttons[p] ?? []).subtracting(item.0)) }
                                if let first = inputs.first { m.bind(first, to: (m.buttons[first] ?? []).union(item.0)) }
                                hub.mapping = m
                                waitingFor = nil
                            }
                        }
                    }
                    Toggle("Left stick moves the D-pad", isOn: Binding(get: { hub.mapping.stickAsDpad }, set: { hub.mapping.stickAsDpad = $0 }))
                    VStack(alignment: .leading) {
                        Text("Stick dead zone: \(Int(hub.mapping.stickDeadZone * 100))%")
                        Slider(value: Binding(get: { hub.mapping.stickDeadZone }, set: { hub.mapping.stickDeadZone = $0 }), in: 0.1...0.8)
                    }
                }

                Section {
                    ForEach(Array(hub.mapping.hotkeys.enumerated()), id: \.offset) { index, h in
                        row(Self.hotkeyName(h.hotkey), value: Self.comboName(h), id: "hotkey.\(index)") {
                            waitingFor = "Hold a modifier (optional) and press a button for \(Self.hotkeyName(h.hotkey))"
                            hub.beginCapture { inputs in
                                var m = hub.mapping
                                let sorted = inputs.sorted { $0.rawValue < $1.rawValue }
                                if sorted.count >= 2, let modifier = inputs.first(where: { $0 == .buttonOptions || $0 == .buttonMenu || $0 == .buttonHome }) ?? sorted.first,
                                   let trigger = sorted.first(where: { $0 != modifier }) {
                                    m.hotkeys[index] = HotkeyBinding(modifier: modifier, trigger: trigger, hotkey: h.hotkey)
                                } else if let only = sorted.first {
                                    m.hotkeys[index] = HotkeyBinding(trigger: only, hotkey: h.hotkey)
                                }
                                hub.mapping = m
                                waitingFor = nil
                            }
                        }
                    }
                } header: {
                    Text("Controller hotkeys")
                } footer: {
                    Text("Save and load use slot 1. A combo's buttons don't reach the game while it's held.")
                }

                Section("Keyboard") {
                    ForEach(Self.buttons(for: model.game.system), id: \.1) { item in
                        let keys = hub.keyboardMapping.buttons.filter { !$0.value.isDisjoint(with: item.0) }.keys.sorted()
                        row(item.1, value: keys.map(Self.keyName).joined(separator: ", "), id: "key.\(item.0.rawValue)") {
                            waitingFor = "Press a key for \(item.1)"
                            hub.captureKey = { code in
                                var m = hub.keyboardMapping
                                for (k, v) in m.buttons where !v.isDisjoint(with: item.0) { m.bind(key: k, to: v.subtracting(item.0)) }
                                m.bind(key: code, to: (m.buttons[code] ?? []).union(item.0))
                                hub.keyboardMapping = m
                                waitingFor = nil
                            }
                        }
                    }
                }

                Section {
                    Button("Restore default mapping", role: .destructive) { hub.resetMappings() }
                }
            }
            .navigationTitle("Controllers")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { model.closeControllers() } }
            }
            .safeAreaInset(edge: .bottom) {
                if let waitingFor, hub.isCapturing {
                    HStack {
                        Text(waitingFor).font(.rounded(.subheadline, weight: .semibold))
                        Spacer()
                        Button("Cancel") {
                            hub.capture = nil
                            hub.captureKey = nil
                            self.waitingFor = nil
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ title: String, value: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(value.isEmpty ? "Not set" : value).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier(id)
        .accessibilityHint("Then press the new button")
    }

    /// The emulated buttons a system has, with their on-pad names.
    static func buttons(for system: SystemID) -> [(InputState, String)] {
        var list: [(InputState, String)] = [(.up, "Up"), (.down, "Down"), (.left, "Left"), (.right, "Right")]
        switch system {
        case .nes, .gb, .gbc: list += [(.a, "A"), (.b, "B")]
        case .gba: list += [(.a, "A"), (.b, "B"), (.l, "L"), (.r, "R")]
        case .snes, .ds: list += [(.a, "A"), (.b, "B"), (.x, "X"), (.y, "Y"), (.l, "L"), (.r, "R")]
        case .md: list += [(.y, "A"), (.b, "B"), (.a, "C"), (.x, "X"), (.l, "Y"), (.r, "Z")]
        }
        list += [(.start, "Start"), (.select, system == .md ? "Mode" : "Select")]
        return list
    }

    static func physicalName(_ p: PhysicalInput) -> String {
        switch p {
        case .buttonA: "South"
        case .buttonB: "East"
        case .buttonX: "West"
        case .buttonY: "North"
        case .leftShoulder: "L1"
        case .rightShoulder: "R1"
        case .leftTrigger: "L2"
        case .rightTrigger: "R2"
        case .dpadUp: "D-pad up"
        case .dpadDown: "D-pad down"
        case .dpadLeft: "D-pad left"
        case .dpadRight: "D-pad right"
        case .leftThumbstickButton: "L3"
        case .rightThumbstickButton: "R3"
        case .buttonMenu: "Menu"
        case .buttonOptions: "Options"
        case .buttonHome: "Home"
        }
    }

    static func comboName(_ h: HotkeyBinding) -> String {
        if let m = h.modifier { return "\(physicalName(m)) + \(physicalName(h.trigger))" }
        return physicalName(h.trigger)
    }

    static func hotkeyName(_ h: Hotkey) -> String {
        switch h {
        case .menu: "Menu"
        case .saveState: "Save state"
        case .loadState: "Load state"
        case .fastForward: "Fast-forward"
        case .rewind: "Rewind"
        }
    }

    static func keyName(_ code: Int) -> String {
        switch code {
        case 0x04...0x1D: return String(UnicodeScalar(UInt8(0x41 + code - 0x04)))
        case 0x1E...0x26: return String(code - 0x1D)
        case 0x27: return "0"
        case KeyCode.returnKey: return "Return"
        case KeyCode.escape: return "Esc"
        case KeyCode.backspace: return "Delete"
        case KeyCode.tab: return "Tab"
        case KeyCode.space: return "Space"
        case 0x3A...0x45: return "F\(code - 0x39)"
        case KeyCode.rightArrow: return "→"
        case KeyCode.leftArrow: return "←"
        case KeyCode.downArrow: return "↓"
        case KeyCode.upArrow: return "↑"
        case 0xE1: return "Left Shift"
        case KeyCode.rightShift: return "Right Shift"
        default: return String(format: "Key %02X", code)
        }
    }
}
