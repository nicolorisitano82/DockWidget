import AppKit

/// The camera effects macOS offers in Control Centre while something is
/// filming: Studio Light among them.
///
/// AVFoundation only lets an app read whether Studio Light is on — the public
/// property is class-level and read-only. The switch itself lives in a private
/// corner of AVFCapture, where Control Centre's own module calls it, and it is
/// reached here by name at run time. Everything is per bundle identifier, so
/// turning it on for us leaves FaceTime's own setting alone.
///
/// It is private, so it is allowed to vanish: every entry point is optional and
/// a missing one costs the feature and nothing else.
enum VideoEffects {
    private typealias IsEnabled = @convention(c) (CFString, CFString) -> Bool
    private typealias SetEnabled = @convention(c) (CFString, Bool, CFString) -> Void

    private typealias GetBoolFor = @convention(c) (CFString) -> Bool
    private typealias SetBoolFor = @convention(c) (Bool, CFString) -> Void
    private typealias GetFloatFor = @convention(c) (CFString, CFString) -> Float
    private typealias SetFloatFor = @convention(c) (CFString, Float, CFString) -> Void

    private struct Entry {
        var studioLight: CFString
        var ringLight: CFString
        var isSupported: IsEnabled
        var isEnabled: IsEnabled
        var setEnabled: SetEnabled
        var isRingActive: GetBoolFor
        var setRingActive: SetBoolFor
        var intensity: GetFloatFor
        var setIntensity: SetFloatFor
        var ringColour: GetFloat1
        var setRingColour: SetFloat1
        var setColourAdvice: SetBoolFor
        var setRingWidth: SetFloat1
    }

    private typealias GetFloat1 = @convention(c) (CFString) -> Float
    private typealias SetFloat1 = @convention(c) (Float, CFString) -> Void

    private static let entry: Entry? = {
        let path = "/System/Library/PrivateFrameworks/AVFCapture.framework/AVFCapture"
        guard let handle = dlopen(path, RTLD_LAZY),
              let effect = dlsym(handle, "AVControlCenterVideoEffectStudioLighting")?
                  .assumingMemoryBound(to: CFString?.self).pointee,
              let ring = dlsym(handle, "AVControlCenterVideoEffectRingLight")?
                  .assumingMemoryBound(to: CFString?.self).pointee,
              let supported = dlsym(handle, "AVControlCenterVideoEffectsModuleIsEffectSupportedForBundleID"),
              let enabled = dlsym(handle, "AVControlCenterVideoEffectsModuleIsEffectEnabledForBundleID"),
              let setter = dlsym(handle, "AVControlCenterVideoEffectsModuleSetEffectEnabledForBundleID"),
              let ringActive = dlsym(handle, "AVControlCenterVideoEffectsModuleGetRingLightActiveForBundleID"),
              let setRingActive = dlsym(handle, "AVControlCenterVideoEffectsModuleSetRingLightActiveForBundleID"),
              let intensity = dlsym(handle, "AVControlCenterVideoEffectsModuleGetEffectIntensityForBundleID"),
              let setIntensity = dlsym(handle, "AVControlCenterVideoEffectsModuleSetEffectIntensityForBundleID"),
              let ringColour = dlsym(handle, "AVControlCenterVideoEffectsModuleGetRingLightColorForBundleID"),
              let setRingColour = dlsym(handle, "AVControlCenterVideoEffectsModuleSetRingLightColorForBundleID"),
              let colourAdvice = dlsym(handle, "AVControlCenterVideoEffectsModuleSetRingLightColorRecommendationEnabledForBundleID"),
              let ringWidth = dlsym(handle, "AVControlCenterVideoEffectsModuleSetRingLightWidthForBundleID")
        else {
            Diagnostics.once("videoeffects", "effetti video non raggiungibili su questo macOS")
            return nil
        }
        return Entry(studioLight: effect,
                     ringLight: ring,
                     isSupported: unsafeBitCast(supported, to: IsEnabled.self),
                     isEnabled: unsafeBitCast(enabled, to: IsEnabled.self),
                     setEnabled: unsafeBitCast(setter, to: SetEnabled.self),
                     isRingActive: unsafeBitCast(ringActive, to: GetBoolFor.self),
                     setRingActive: unsafeBitCast(setRingActive, to: SetBoolFor.self),
                     intensity: unsafeBitCast(intensity, to: GetFloatFor.self),
                     setIntensity: unsafeBitCast(setIntensity, to: SetFloatFor.self),
                     ringColour: unsafeBitCast(ringColour, to: GetFloat1.self),
                     setRingColour: unsafeBitCast(setRingColour, to: SetFloat1.self),
                     setColourAdvice: unsafeBitCast(colourAdvice, to: SetBoolFor.self),
                     setRingWidth: unsafeBitCast(ringWidth, to: SetFloat1.self))
    }()

    /// The identifier the effect is set for: this process, whichever it is.
    private static var bundleID: CFString {
        (Bundle.main.bundleIdentifier ?? "dev.nicolo.underdock") as CFString
    }

    static var isStudioLightSupported: Bool {
        guard let entry else { return false }
        return entry.isSupported(entry.studioLight, bundleID)
    }

    static var isStudioLightOn: Bool {
        guard let entry else { return false }
        return entry.isEnabled(entry.studioLight, bundleID)
    }

    // MARK: The ring light

    /// Whether the screen is being used as a light right now.
    static var isRingLightOn: Bool {
        guard let entry else { return false }
        return entry.isRingActive(bundleID)
    }

    static var isRingLightSupported: Bool {
        guard let entry else { return false }
        return entry.isSupported(entry.ringLight, bundleID)
    }

    static func setRingLight(_ on: Bool) {
        guard let entry else { return }
        entry.setRingActive(on, bundleID)
        // The effect and its switch are two different things: one says the
        // light exists, the other that it is shining.
        entry.setEnabled(entry.ringLight, on, bundleID)
    }

    /// 0 to 1. What the system calls the effect's intensity.
    static var ringLightIntensity: Float {
        guard let entry else { return 0.5 }
        return entry.intensity(entry.ringLight, bundleID)
    }

    /// Where the light sits between amber and daylight. Measured, not guessed:
    /// 0 is `1.00 0.63 0.19`, 0.5 is white, 1 is `0.73 0.82 1.00`.
    ///
    /// Five stops across the whole scale: two of them a tenth apart, which is
    /// what the first version offered, are not a choice anybody can see.
    static let lightStops: [Float] = [0, 0.25, 0.5, 0.75, 1]
    static let warmLight: Float = 0
    static let whiteLight: Float = 0.5

    static func lightName(_ value: Float) -> String {
        switch value {
        case ..<0.13: return T("Ambra", "Amber")
        case ..<0.38: return T("Dorata", "Golden")
        case ..<0.63: return T("Bianca", "White")
        case ..<0.88: return T("Fredda", "Cool")
        default: return T("Azzurra", "Blue")
        }
    }

    /// The colour the system will actually shine, so a swatch can show it
    /// rather than approximate it.
    static func lightColour(_ value: Float) -> NSColor {
        guard let converted = converter?(min(max(value, 0), 1))?.takeUnretainedValue(),
              let colour = NSColor(cgColor: converted) else {
            // Between the two ends that were measured, which is close enough
            // when the private converter is not there.
            let warm = NSColor(calibratedRed: 1, green: 0.63, blue: 0.19, alpha: 1)
            let cool = NSColor(calibratedRed: 0.73, green: 0.82, blue: 1, alpha: 1)
            return warm.blended(withFraction: CGFloat(value), of: cool) ?? .white
        }
        return colour
    }

    private typealias Converter = @convention(c) (Float) -> Unmanaged<CGColor>?

    private static let converter: Converter? = {
        let path = "/System/Library/PrivateFrameworks/AVFCapture.framework/AVFCapture"
        guard let handle = dlopen(path, RTLD_LAZY),
              let symbol = dlsym(handle,
                  "AVControlCenterVideoEffectsModuleConvertNormalizedRingLightColorToRGBColor")
        else { return nil }
        return unsafeBitCast(symbol, to: Converter.self)
    }()

    static var ringLightColour: Float {
        guard let entry else { return whiteLight }
        return entry.ringColour(bundleID)
    }

    static func setRingLightColour(_ value: Float) {
        guard let entry else { return }
        // The system offers a colour of its own and would put ours back: the
        // advice is turned off first.
        entry.setColourAdvice(false, bundleID)
        entry.setRingColour(min(max(value, 0), 1), bundleID)
        reapply()
    }

    /// How much light, as far as it can be asked for.
    ///
    /// Two knobs, because which of them the light on screen actually follows is
    /// not something this side can see: the intensity the module keeps for the
    /// effect, and the width of the ring — measured at 1, which is as wide as
    /// it goes. The width keeps a floor: a ring thinned to nothing is a light
    /// turned off by another name, and the switch above already does that.
    ///
    /// No nudge afterwards: a change of these is what the light watches.
    static func setRingLightIntensity(_ value: Float) {
        guard let entry else { return }
        let wanted = min(max(value, 0), 1)
        entry.setIntensity(entry.ringLight, wanted, bundleID)
        entry.setRingWidth(widthFor(wanted), bundleID)
    }

    private static func widthFor(_ intensity: Float) -> Float { 0.35 + intensity * 0.65 }

    /// Makes the light look at its settings again, after a colour change that
    /// it would otherwise not notice.
    ///
    /// Switching it off and on does not do it — tried, with a pause between the
    /// two and without. What it does follow is the amount of light: move the
    /// intensity and it comes back the new colour. So the intensity is moved by
    /// a fortieth and put straight back, which is below what an eye catches and
    /// enough for the light to read the rest.
    private static func reapply() {
        guard let entry, entry.isRingActive(bundleID) else { return }
        let intensity = entry.intensity(entry.ringLight, bundleID)
        let nudge: Float = intensity > 0.5 ? -0.025 : 0.025
        entry.setIntensity(entry.ringLight, intensity + nudge, bundleID)
        entry.setRingWidth(widthFor(intensity + nudge), bundleID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            entry.setIntensity(entry.ringLight, intensity, bundleID)
            entry.setRingWidth(widthFor(intensity), bundleID)
        }
    }

    @discardableResult
    static func setStudioLight(_ on: Bool) -> Bool {
        guard let entry, isStudioLightSupported else { return false }
        entry.setEnabled(entry.studioLight, on, bundleID)
        return true
    }
}
