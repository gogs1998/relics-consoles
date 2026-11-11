import CoreKit
import SwiftUI

/// The pause menu. On the Duo it opens on the near half (bottom in table pose, right page in book
/// pose), where the hands already are.
struct PlayerMenu: View {
    let model: PlayerModel
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paused")
                        .font(.rounded(.title3, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(model.game.title)
                        .font(.rounded(.footnote))
                        .foregroundStyle(Theme.inkDim)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    model.menuOpen = false
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(EmberButtonStyle())
            }
            SlotShelf(model: model, compact: false)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ScreenMode.allCases) { mode in
                        Button {
                            model.screenMode = mode
                        } label: {
                            Label(mode.title, systemImage: mode.symbol)
                        }
                        .buttonStyle(ChipStyle(selected: model.screenMode == mode))
                    }
                }
            }
            if model.game.system == .md {
                Toggle(isOn: Binding(get: { model.sixButtonPad }, set: { model.sixButtonPad = $0 })) {
                    Text("Six-button pad")
                        .font(.rounded(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.ember)
            }
            HStack(spacing: 8) {
                Button { model.beginEditingControls() } label: { Label("Edit controls", systemImage: "slider.horizontal.3") }
                    .buttonStyle(ChipStyle(selected: false))
                    .accessibilityIdentifier("menu.editControls")
                Button {
                    model.showingControllers = true
                    model.menuOpen = false
                } label: { Label("Controllers", systemImage: "gamecontroller") }
                    .buttonStyle(ChipStyle(selected: false))
                    .accessibilityIdentifier("menu.controllers")
            }
            HStack(spacing: 8) {
                Button { model.reset() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(ChipStyle(selected: false))
                Button { model.startOver() } label: { Label("Start over", systemImage: "backward.end.fill") }
                    .buttonStyle(ChipStyle(selected: false))
                Spacer()
                Button(role: .destructive) { onQuit() } label: { Label("Quit", systemImage: "xmark") }
                    .buttonStyle(ChipStyle(selected: false))
            }
        }
        .padding(16)
        .frame(maxWidth: 560)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.graphite.opacity(0.97))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 24, y: 10)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityAddTraits(.isModal)
    }
}

/// Four save-state slots with thumbnails. Tap Save to write, tap the picture to load.
struct SlotShelf: View {
    let model: PlayerModel
    var compact: Bool

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...4, id: \.self) { slot in
                VStack(spacing: 6) {
                    Button {
                        model.loadState(slot: slot)
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.black.opacity(0.55))
                            if let img = model.slotThumbs[slot] {
                                Image(uiImage: img)
                                    .interpolation(.none)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .padding(3)
                            } else {
                                Text("\(slot)")
                                    .font(.rounded(.title3, weight: .heavy))
                                    .foregroundStyle(Theme.inkDim.opacity(0.5))
                            }
                        }
                        .aspectRatio(16 / 14, contentMode: .fit)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.slotThumbs[slot] == nil && model.slotDates[slot] == nil)
                    .accessibilityLabel(model.slotDates[slot] == nil ? "Slot \(slot), empty" : "Load slot \(slot)")
                    Button {
                        model.saveState(slot: slot)
                    } label: {
                        Group {
                            if compact {
                                Image(systemName: "square.and.arrow.down")
                            } else {
                                Text("Save \(slot)")
                            }
                        }
                        .font(.rounded(.caption, weight: .bold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ChipStyle(selected: false, dense: true))
                    .accessibilityLabel("Save to slot \(slot)")
                }
            }
        }
    }
}

/// Book pose, right page top: the things you reach for mid-game.
struct CompanionPage: View {
    let model: PlayerModel
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("STATES")
                    .font(.rounded(.caption2, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkDim)
                    .fixedSize()
                Spacer(minLength: 4)
                CompanionKey(symbol: "backward.fill", label: "Rewind (hold)", active: model.rewinding) { on in
                    model.setRewind(on)
                }
                CompanionKey(symbol: "forward.fill", label: "Fast forward (hold)", active: model.fastForward) { on in
                    model.setFastForward(on)
                }
                Button { model.menuOpen = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.rounded(.footnote, weight: .bold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(ChipStyle(selected: false, dense: true))
                .accessibilityLabel("Menu")
            }
            SlotShelf(model: model, compact: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.28))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        )
    }
}

/// A key that reports press and release (hold-to-rewind, hold-to-fast-forward).
struct CompanionKey: View {
    var symbol: String
    var label: String
    var active: Bool
    var onChange: (Bool) -> Void
    @GestureState private var down = false

    var body: some View {
        Image(systemName: symbol)
            .font(.rounded(.footnote, weight: .bold))
            .foregroundStyle(active ? Theme.ember : Theme.ink)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Color.white.opacity(active ? 0.14 : 0.07)))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($down) { _, state, _ in state = true }
            )
            .onChange(of: down) { _, now in onChange(now) }
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }
}

struct EmberButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(.subheadline, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.78))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(LinearGradient(colors: [Theme.ember, Theme.emberDeep], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.8))
                    .shadow(color: Theme.ember.opacity(0.35), radius: configuration.isPressed ? 2 : 8, y: 3)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct ChipStyle: ButtonStyle {
    var selected: Bool
    var dense = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(dense ? .caption : .footnote, weight: .semibold))
            .foregroundStyle(selected ? Color.black.opacity(0.8) : Theme.ink)
            .padding(.horizontal, dense ? 8 : 12)
            .padding(.vertical, dense ? 6 : 8)
            .background(
                Capsule().fill(selected ? AnyShapeStyle(Theme.sand) : AnyShapeStyle(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08)))
            )
    }
}
