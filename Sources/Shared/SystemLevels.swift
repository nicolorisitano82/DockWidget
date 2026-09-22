import AppKit
import CoreAudio

/// Reading and changing the two levels that live either side of the notch:
/// output volume and display brightness.
///
/// Volume is public API. Brightness is not: there has never been a supported
/// way to set the built-in display's backlight, so the two private entry
/// points are looked up by name at run time and the widget goes read-only —
/// or disappears — when neither answers. Nothing here is required for the
/// rest of the app to work.
enum SystemLevels {

    // MARK: - Volume

    enum Volume {
        /// The device the Mac is playing through right now, re-read every time:
        /// headphones get plugged in.
        private static var outputDevice: AudioDeviceID? {
            var id = AudioDeviceID(0)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                    &address, 0, nil, &size, &id)
            return status == noErr && id != kAudioObjectUnknown ? id : nil
        }

        /// Main first, then the two channels: plenty of devices carry no main
        /// volume control and answer only per channel.
        private static let elements: [AudioObjectPropertyElement] = [
            kAudioObjectPropertyElementMain, 1, 2,
        ]

        private static func address(_ selector: AudioObjectPropertySelector,
                                    _ element: AudioObjectPropertyElement)
            -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: selector,
                                       mScope: kAudioDevicePropertyScopeOutput,
                                       mElement: element)
        }

        /// 0…1, or nil when the output device has no volume control at all —
        /// which is what an HDMI monitor or an optical output looks like.
        static var level: Float? {
            guard let device = outputDevice else { return nil }
            for element in elements {
                var address = address(kAudioDevicePropertyVolumeScalar, element)
                guard AudioObjectHasProperty(device, &address) else { continue }
                var value = Float(0)
                var size = UInt32(MemoryLayout<Float>.size)
                guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
                else { continue }
                return min(max(value, 0), 1)
            }
            return nil
        }

        @discardableResult
        static func set(_ level: Float) -> Bool {
            guard let device = outputDevice else { return false }
            var value = min(max(level, 0), 1)
            var changed = false
            for element in elements {
                var address = address(kAudioDevicePropertyVolumeScalar, element)
                guard AudioObjectHasProperty(device, &address) else { continue }
                var settable = DarwinBoolean(false)
                guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                      settable.boolValue else { continue }
                let status = AudioObjectSetPropertyData(
                    device, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &value)
                changed = changed || status == noErr
                // Stop after the main control: writing it and then the channels
                // as well would apply the change twice on devices that have both.
                if changed, element == kAudioObjectPropertyElementMain { break }
            }
            // Moving the slider off zero should also take the mute off, the way
            // the keyboard keys do.
            if changed, value > 0, isMuted == true { setMuted(false) }
            return changed
        }

        static var isMuted: Bool? {
            guard let device = outputDevice else { return nil }
            var address = address(kAudioDevicePropertyMute, kAudioObjectPropertyElementMain)
            guard AudioObjectHasProperty(device, &address) else { return nil }
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
            else { return nil }
            return value != 0
        }

        @discardableResult
        static func setMuted(_ muted: Bool) -> Bool {
            guard let device = outputDevice else { return false }
            var address = address(kAudioDevicePropertyMute, kAudioObjectPropertyElementMain)
            guard AudioObjectHasProperty(device, &address) else { return false }
            var value: UInt32 = muted ? 1 : 0
            return AudioObjectSetPropertyData(
                device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
        }
    }

    // MARK: - Brightness

    enum Brightness {
        private typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        private typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32
        private typealias CoreGetter = @convention(c) (CGDirectDisplayID) -> Double
        private typealias CoreSetter = @convention(c) (CGDirectDisplayID, Double) -> Void

        /// Two ways in, tried in order. DisplayServices is the one the system
        /// HUD itself goes through; CoreDisplay is older and still present.
        private struct Entry {
            var get: (CGDirectDisplayID) -> Float?
            var set: (CGDirectDisplayID, Float) -> Bool
        }

        private static let entry: Entry? = {
            let displayServices = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
            if let handle = dlopen(displayServices, RTLD_LAZY),
               let getSymbol = dlsym(handle, "DisplayServicesGetBrightness"),
               let setSymbol = dlsym(handle, "DisplayServicesSetBrightness") {
                let get = unsafeBitCast(getSymbol, to: Getter.self)
                let set = unsafeBitCast(setSymbol, to: Setter.self)
                return Entry(get: { display in
                    var value = Float(0)
                    return get(display, &value) == 0 ? value : nil
                }, set: { display, value in
                    set(display, value) == 0
                })
            }

            let coreDisplay = "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay"
            if let handle = dlopen(coreDisplay, RTLD_LAZY),
               let getSymbol = dlsym(handle, "CoreDisplay_Display_GetUserBrightness"),
               let setSymbol = dlsym(handle, "CoreDisplay_Display_SetUserBrightness") {
                let get = unsafeBitCast(getSymbol, to: CoreGetter.self)
                let set = unsafeBitCast(setSymbol, to: CoreSetter.self)
                return Entry(get: { Float(get($0)) }, set: { display, value in
                    set(display, Double(value))
                    return true
                })
            }

            Diagnostics.once("brightness-entry",
                             "nessuna via per la luminosità: né DisplayServices né CoreDisplay")
            return nil
        }()

        /// The built-in display, which is the only one whose backlight these
        /// calls reach. It is the one with a notch where there is one, and
        /// otherwise the main one — asked for here rather than through the
        /// notch's own geometry, which does not exist in every target this
        /// file is compiled into.
        private static var display: CGDirectDisplayID? {
            let builtIn = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
            guard let screen = builtIn,
                  let number = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            return CGDirectDisplayID(number.uint32Value)
        }

        /// 0…1, or nil on a Mac where neither entry point answers — an external
        /// display, mostly.
        static var level: Float? {
            guard let entry, let display, let value = entry.get(display) else { return nil }
            guard value.isFinite, value >= 0, value <= 1 else { return nil }
            return value
        }

        @discardableResult
        static func set(_ level: Float) -> Bool {
            guard let entry, let display else { return false }
            return entry.set(display, min(max(level, 0), 1))
        }

        static var isAvailable: Bool { level != nil }
    }
}
