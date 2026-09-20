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

    /// No inout array here: the closure that builds a view registers its own
    /// listeners, and writing into an array that is being passed inout is an
    /// overlapping access — which Swift detects and aborts on.
    func controllers() -> [OverlayBarController] {
        var built: [OverlayBarController] = []
        for instance in WidgetInstances.all(of: template.id) {
            let anchor = WidgetInstance.anchorTitle(base: base,
                                                    copy: WidgetInstance.copy(of: instance))
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
