import AppKit

/// The bar-shaped widgets the agent can draw, and how to build one.
///
/// Every widget exists in several copies, each with its own anchor tile and its
/// own settings, so the agent builds a controller per copy and lets the ones
/// that are not in the Dock hide themselves.
struct BarWidgetKind {
    let base: String
    let template: BarLayout.Spec
    let makeView: (String) -> BarContentView
    let isEnabled: (String) -> Bool

    func controllers(playback: inout [UUID]) -> [OverlayBarController] {
        var built: [OverlayBarController] = []
        for copy in 1...WidgetInstance.maximumCopies {
            let instance = WidgetInstance.id(kind: template.id, copy: copy)
            let anchor = WidgetInstance.anchorTitle(base: base, copy: copy)
            let view = makeView(instance)
            view.instance = instance
            built.append(OverlayBarController(
                spec: template.forInstance(instance, anchorTitle: anchor),
                content: view,
                isEnabled: { isEnabled(instance) }
            ))
        }
        return built
    }
}
