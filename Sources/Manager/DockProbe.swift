import AppKit
import ApplicationServices

/// Diagnostics for the overlay widget: what the Dock exposes over Accessibility
/// and how fast it answers. Run with `--probe-dock`; writes a report next to
/// the temporary directory and exits.
enum DockProbe {
    static func run(reportPath: String) {
        var lines: [String] = []
        func say(_ text: String) {
            lines.append(text)
            print(text)
        }

        let trusted = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )
        say("accessibility trusted: \(trusted)")
        guard trusted else {
            say("→ concedi l'accesso in Impostazioni di Sistema e rilancia")
            write(lines, to: reportPath)
            return
        }

        guard let dock = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock"
        ).first else {
            say("Dock non trovato")
            write(lines, to: reportPath)
            return
        }

        let application = AXUIElementCreateApplication(dock.processIdentifier)
        say("dock pid: \(dock.processIdentifier)")

        var spacers: [AXUIElement] = []
        walk(application, depth: 0, say: say, spacers: &spacers)

        say("")
        say("spacer trovati: \(spacers.count)")
        if let spacer = spacers.first {
            let start = Date()
            var samples = 0
            for _ in 0..<200 {
                if frame(of: spacer) != nil { samples += 1 }
            }
            let elapsed = Date().timeIntervalSince(start)
            say(String(format: "200 letture di posizione+dimensione: %.1f ms totali, %.2f ms l'una (%d valide)",
                       elapsed * 1000, elapsed * 1000 / 200, samples))
        }
        write(lines, to: reportPath)
    }

    private static func walk(_ element: AXUIElement, depth: Int,
                             say: (String) -> Void, spacers: inout [AXUIElement]) {
        guard depth < 4 else { return }
        let role = string(element, kAXRoleAttribute as CFString) ?? "?"
        let subrole = string(element, kAXSubroleAttribute as CFString)
        let title = string(element, kAXTitleAttribute as CFString)
        let description = string(element, kAXDescriptionAttribute as CFString)

        let isSpacer = [subrole, description, title, role]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains("spacer") }
        if isSpacer { spacers.append(element) }

        if depth > 0 {
            let box = frame(of: element).map {
                String(format: " frame=(%.0f,%.0f %.0fx%.0f)", $0.origin.x, $0.origin.y, $0.width, $0.height)
            } ?? ""
            let labels = [subrole, title, description].compactMap { $0 }.filter { !$0.isEmpty }
            say("\(String(repeating: "  ", count: depth))\(role) \(labels.joined(separator: " | "))\(box)\(isSpacer ? "   ← SPACER" : "")")
        }

        guard let children = copy(element, kAXChildrenAttribute as CFString) as? [AXUIElement] else { return }
        for child in children.prefix(60) {
            walk(child, depth: depth + 1, say: say, spacers: &spacers)
        }
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = copy(element, kAXPositionAttribute as CFString),
              let sizeValue = copy(element, kAXSizeAttribute as CFString) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func copy(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ attribute: CFString) -> String? {
        copy(element, attribute) as? String
    }

    private static func write(_ lines: [String], to path: String) {
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}
