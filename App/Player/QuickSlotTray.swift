import SwiftUI

/// Duo table pose, one-screen systems: three quick save slots in a recessed tray along the hinge
/// edge of the bottom half. Tap an empty slot to save into it, tap a full one to load it (Undo
/// in the toast), hold any slot to choose Save or Load.
struct QuickSlotTray: View {
    let model: PlayerModel
    static let slots = [1, 2, 3]

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 8
            let inner = CGSize(width: geo.size.width - 16, height: geo.size.height - 12)
            let tileW = min((inner.width - gap * 2) / 3, inner.height * 1.2)
            HStack(spacing: gap) {
                ForEach(Self.slots, id: \.self) { slot in
                    tile(slot).frame(width: tileW, height: inner.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(tray)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick save slots")
        .accessibilityIdentifier("table.quickSlots")
    }

    /// A shallow well in the body, lit from above like the controller's keys.
    private var tray: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.32)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.black.opacity(0.7), Color.white.opacity(0.09)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
    }

    private func tile(_ slot: Int) -> some View {
        let full = model.slotDates[slot] != nil
        return Menu {
            Button { model.saveState(slot: slot) } label: { Label("Save to slot \(slot)", systemImage: "square.and.arrow.down") }
            if full {
                Button { model.quickLoad(slot: slot) } label: { Label("Load slot \(slot)", systemImage: "arrow.uturn.backward") }
            }
        } label: {
            SlotTileFace(slot: slot, image: model.slotThumbs[slot], full: full, pulse: model.savingPulse)
        } primaryAction: {
            if full { model.quickLoad(slot: slot) } else { model.saveState(slot: slot) }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(full ? "Slot \(slot). Tap to load, hold to save over it" : "Slot \(slot), empty. Tap to save")
        .accessibilityIdentifier("table.slot\(slot)")
    }
}

/// One slot: a tiny dark screen showing the saved moment, or an inviting empty well.
private struct SlotTileFace: View {
    let slot: Int
    let image: UIImage?
    let full: Bool
    let pulse: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(full ? Theme.screenGlass : Color.white.opacity(0.03))
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(2)
                    .overlay(
                        LinearGradient(colors: [.clear, Color.black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .padding(2)
                    )
            } else {
                Image(systemName: "plus")
                    .font(.rounded(.footnote, weight: .bold))
                    .foregroundStyle(Theme.inkDim.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text("\(slot)")
                .font(.rounded(.caption2, weight: .heavy))
                .foregroundStyle(full ? Theme.ink : Theme.inkDim)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(full ? Color.white.opacity(0.14) : Color.white.opacity(0.16),
                              style: StrokeStyle(lineWidth: 1, dash: full ? [] : [4, 3]))
        )
        .shadow(color: .black.opacity(full ? 0.45 : 0), radius: 3, y: 2)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.25), value: pulse)
    }
}
