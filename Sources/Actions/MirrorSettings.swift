import AppKit

/// The mirror: a window with the camera in it, for checking yourself before a
/// call without opening anything.
struct MirrorSettings: Equatable {
    /// Mirrored, the way a real mirror is — which is what most people expect
    /// and not what the camera actually sends.
    var isFlipped = true
    /// 0 for square corners, up to half the side for a circle.
    var cornerRadius: CGFloat = 22
    var side: CGFloat = 260
    /// Stays on top of everything until it is clicked away.
    var floats = true
    /// Lights your face with the screen while the mirror is open, and puts the
    /// setting back the way it was when it closes.
    var studioLight = false
    /// Lights the screen edges as soon as the mirror opens.
    var ringLight = false
    /// Where the light sits on the amber-to-daylight scale.
    var ringColour: Double = 0.5

    enum Key {
        static let flipped = "mirror.flipped"
        static let cornerRadius = "mirror.cornerRadius"
        static let side = "mirror.side"
        static let floats = "mirror.floats"
        static let studioLight = "mirror.studioLight"
        static let ringLight = "mirror.ringLight"
        static let ringColour = "mirror.ringColour"
    }

    static var current: MirrorSettings {
        let store = SettingsStore.shared
        let defaults = MirrorSettings()
        return MirrorSettings(
            isFlipped: store.bool(Key.flipped, or: defaults.isFlipped),
            cornerRadius: CGFloat(store.double(Key.cornerRadius,
                                               or: Double(defaults.cornerRadius))),
            side: CGFloat(min(max(store.double(Key.side, or: Double(defaults.side)), 140), 520)),
            floats: store.bool(Key.floats, or: defaults.floats),
            studioLight: store.bool(Key.studioLight, or: defaults.studioLight),
            ringLight: store.bool(Key.ringLight, or: defaults.ringLight),
            ringColour: store.double(Key.ringColour, or: defaults.ringColour)
        )
    }

    func save() {
        SettingsStore.shared.set([
            Key.flipped: isFlipped,
            Key.cornerRadius: Double(cornerRadius),
            Key.side: Double(side),
            Key.floats: floats,
            Key.studioLight: studioLight,
            Key.ringLight: ringLight,
            Key.ringColour: ringColour,
        ])
    }

    /// The radius the window can actually take, given its size.
    var effectiveRadius: CGFloat { min(cornerRadius, side / 2) }
}
