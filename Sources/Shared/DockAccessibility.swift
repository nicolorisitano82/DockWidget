import AppKit
import ApplicationServices

/// Where the Dock's items are on screen, read over Accessibility.
///
/// The Dock reports *magnified* frames, live: an item under the pointer is
/// bigger than the same item at rest. Reading position and size costs about
/// 0.04 ms, so following the magnification at 60 Hz is affordable.
enum DockAccessibility {
    struct Item {
        let element: AXUIElement
        let subrole: String?
        let title: String?

        var isSpacer: Bool { subrole == "AXSpacerDockItem" }
        var isApplication: Bool { subrole == "AXApplicationDockItem" }
        var frame: CGRect? { DockAccessibility.frame(of: element) }
    }

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestTrust() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// The Dock's item list, in the order the Dock lays it out.
    static func items() -> [Item] {
        guard let dock = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock"
        ).first else { return [] }

        let application = AXUIElementCreateApplication(dock.processIdentifier)
        guard let lists = copy(application, kAXChildrenAttribute) as? [AXUIElement] else { return [] }

        for list in lists {
            guard string(list, kAXRoleAttribute) == "AXList",
                  let children = copy(list, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            return children.map {
                Item(element: $0,
                     subrole: string($0, kAXSubroleAttribute),
                     title: string($0, kAXTitleAttribute))
            }
        }
        return []
    }

    /// The run of spacers that follows `anchorTitle`, plus the anchor itself.
    ///
    /// Anchoring to our own app tile is what makes this unambiguous: every
    /// spacer looks alike, but only ours sit right after that tile.
    static func barElements(anchorTitle: String, spacerCount: Int) -> [Item] {
        let items = items()
        guard let anchorIndex = items.firstIndex(where: { $0.isApplication && $0.title == anchorTitle }) else {
            return []
        }
        var run = [items[anchorIndex]]
        var index = anchorIndex + 1
        while index < items.count, items[index].isSpacer, run.count <= spacerCount {
            run.append(items[index])
            index += 1
        }
        return run
    }

    /// Union of the elements' frames, in Cocoa screen coordinates.
    static func barFrame(anchorTitle: String, spacerCount: Int) -> CGRect? {
        let frames = barElements(anchorTitle: anchorTitle, spacerCount: spacerCount).compactMap(\.frame)
        guard let first = frames.first else { return nil }
        let union = frames.dropFirst().reduce(first) { $0.union($1) }
        return flipped(union)
    }

    /// Accessibility measures from the top-left of the primary display; AppKit
    /// measures from the bottom-left of the same origin.
    static func flipped(_ rect: CGRect) -> CGRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        return CGRect(x: rect.origin.x,
                      y: primary.frame.maxY - rect.origin.y - rect.height,
                      width: rect.width,
                      height: rect.height)
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = copy(element, kAXPositionAttribute),
              let sizeValue = copy(element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID(),
              AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }
}

/// What a bar-shaped widget needs from the Dock.
///
/// A bar is drawn over a run of empty tiles, so its width is measured in tiles.
/// Below its minimum a widget stops being readable — the now-playing bar has to
/// fit a cover, two lines of text and three controls — so the minimum is part of
/// the widget's definition, not a preference.
enum BarLayout {
    struct Spec {
        let id: String
        /// The Dock titles its items after the bundle's file name, not after
        /// CFBundleName, so this must match the bundle the build script makes.
        let anchorTitle: String
        let minimumSpacers: Int
        let defaultSpacers: Int
        let maximumSpacers: Int

        var spacerCountKey: String { "\(id).barSpacers" }

        /// The stored width, never below what the widget needs to work.
        var spacerCount: Int {
            let stored = Int(SettingsStore.shared.double(spacerCountKey, or: Double(defaultSpacers)))
            return min(max(stored, minimumSpacers), maximumSpacers)
        }
    }

    static let nowPlaying = Spec(
        id: "nowPlaying",
        anchorTitle: "NowPlaying",
        minimumSpacers: 3,
        defaultSpacers: 3,
        maximumSpacers: 8
    )

    /// One tile per mounted volume.
    static let disks = Spec(
        id: "disks",
        anchorTitle: "Dischi",
        minimumSpacers: 0,
        defaultSpacers: 2,
        maximumSpacers: 5
    )

    /// One tile per sensor. A single-tile bar is legitimate here, so the
    /// minimum is no spacers at all.
    static let sensors = Spec(
        id: "sensors",
        anchorTitle: "Sensori",
        minimumSpacers: 0,
        defaultSpacers: 2,
        maximumSpacers: 5
    )

    /// Three tiles. Four square cells fit two tiles only by shrinking to a
    /// third of a tile each, which reads as a row of specks next to the Dock's
    /// icons; at three they are about six tenths of a tile.
    static let actions = Spec(
        id: "actions",
        anchorTitle: "Azioni",
        minimumSpacers: 2,
        defaultSpacers: 2,
        maximumSpacers: 5
    )
}
