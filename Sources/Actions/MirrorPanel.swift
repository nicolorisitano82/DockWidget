import AVFoundation
import AppKit

/// A borderless window with the camera in it.
///
/// It is a mirror, so by default it is flipped: a camera sends what it sees,
/// and what it sees is the other way round from what you expect of a mirror.
/// A click anywhere else puts it away, and so does a click on it.
final class MirrorPanel: NSObject {
    private var panel: NSPanel?
    private var session: AVCaptureSession?
    /// What the lights were before the mirror touched them, so they can be put
    /// back: leaving the screen shining after the window has gone would be a
    /// thing nobody asked for and nobody could find the switch to.
    private var studioLightWas: Bool?
    private var ringLightWas: Bool?
    /// The still output, when the session took one, and the screen the mirror
    /// is on — which is the one that flashes.
    private var photo: AVCapturePhotoOutput?
    private var screen: NSScreen?

    func toggle() {
        panel == nil ? show() : close()
    }

    private func show() {
        let settings = MirrorSettings.current
        guard let screen = NSScreen.main else {
            Diagnostics.write("specchio: nessuno schermo")
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        Diagnostics.write("specchio: permesso fotocamera = \(status.rawValue)")
        switch status {
        case .authorized:
            open(settings, on: screen)
        case .notDetermined:
            // The prompt belongs to an application with a face: this agent has
            // none, so it asks and reports whatever comes back.
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    Diagnostics.write("specchio: risposta al permesso = \(granted)")
                    guard granted else { return }
                    self?.open(settings, on: screen)
                }
            }
        default:
            Diagnostics.write("specchio: fotocamera negata, va concessa in Impostazioni di Sistema")
        }
    }

    private func open(_ settings: MirrorSettings, on screen: NSScreen) {
        guard panel == nil else {
            Diagnostics.write("specchio: già aperto")
            return
        }
        guard let camera = AVCaptureDevice.default(for: .video) else {
            Diagnostics.write("specchio: nessuna fotocamera trovata")
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: camera) else {
            Diagnostics.write("specchio: la fotocamera \(camera.localizedName) non si apre")
            return
        }

        let session = AVCaptureSession()
        session.sessionPreset = .high
        guard session.canAddInput(input) else {
            Diagnostics.write("specchio: la sessione rifiuta l'ingresso")
            return
        }
        session.addInput(input)

        // The still output rides along with the preview: asking for a frame
        // out of the preview layer gives what the screen has, which is a
        // smaller picture than the camera can take.
        let photo = AVCapturePhotoOutput()
        if session.canAddOutput(photo) {
            session.addOutput(photo)
            self.photo = photo
        } else {
            self.photo = nil
            Diagnostics.write("specchio: la sessione rifiuta l'uscita foto")
        }

        let side = settings.side
        let frame = NSRect(x: screen.visibleFrame.midX - side / 2,
                           y: screen.visibleFrame.midY - side / 2,
                           width: side, height: side)
        let panel = MirrorWindow(contentRect: frame,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = settings.floats ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = MirrorView(frame: NSRect(origin: .zero, size: frame.size))
        view.onDismiss = { [weak self] in self?.close() }
        view.wantsLayer = true
        view.layer?.cornerRadius = settings.effectiveRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true

        // The picture in a view of its own: a layer added to the container
        // would draw over anything the container itself painted, and the
        // controls have to sit on top.
        let picture = NSView(frame: view.bounds)
        picture.wantsLayer = true
        picture.autoresizingMask = [.width, .height]
        view.addSubview(picture)

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = picture.bounds
        picture.layer?.addSublayer(preview)
        view.preview = preview

        ringLightWas = VideoEffects.isRingLightOn

        let controls = MirrorControlsView(frame: view.bounds)
        controls.autoresizingMask = [.width, .height]
        controls.onClose = { [weak self] in self?.close() }
        controls.onShoot = { [weak self] in self?.shoot() }
        view.addSubview(controls)
        view.controls = controls
        // Mirrored across the middle, which is what a mirror does and a camera
        // does not. The zoom rides on the same transform.
        view.isFlipped_ = settings.isFlipped
        preview.transform = CATransform3DMakeScale(settings.isFlipped ? -1 : 1, 1, 1)

        panel.contentView = view
        // Shown empty, then faded up once the camera is actually filming:
        // ordering it front straight away meant the buttons arrived first and
        // the picture caught up afterwards.
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        // Key, and the application forward with it. A borderless panel of an
        // accessory application is never key by itself, and gestures — the
        // pinch, the wheel — are delivered to whichever window is: they were
        // going to whatever happened to be in front, which is why the zoom did
        // nothing while the buttons worked. Clicks route by where they land;
        // gestures do not.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            session.startRunning()
            DispatchQueue.main.async {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    panel.animator().alphaValue = 1
                }
                // The lights go on once there is a picture: before that there
                // is no client for the effect and the switch is ignored.
                if settings.ringLight {
                    VideoEffects.setRingLightColour(Float(settings.ringColour))
                    VideoEffects.setRingLight(true)
                    controls.refresh()
                }
            }
            guard settings.studioLight else { return }
            // Asked for once the camera is actually filming: before that there
            // is no client for the effect to attach to, and the switch is
            // quietly ignored.
            DispatchQueue.main.async {
                guard let self else { return }
                guard VideoEffects.isStudioLightSupported else {
                    Diagnostics.write("luce studio non supportata")
                    return
                }
                self.studioLightWas = VideoEffects.isStudioLightOn
                VideoEffects.setStudioLight(true)
                Diagnostics.write("luce studio: era \(self.studioLightWas == true), "
                    + "ora \(VideoEffects.isStudioLightOn)")
            }
        }

        self.panel = panel
        self.session = session
        self.screen = screen
        Diagnostics.write("specchio aperto: \(Int(frame.width))x\(Int(frame.height)) "
            + "a \(Int(frame.minX)),\(Int(frame.minY))")
    }

    /// One picture, with the screen for a flash.
    func shoot() {
        guard let photo, let screen else {
            Diagnostics.write("specchio: niente uscita foto, scatto saltato")
            return
        }
        MirrorShot.take(with: photo, on: screen,
                        mirrored: MirrorSettings.current.isFlipped) { url, problem in
            if let url {
                Diagnostics.write("specchio: foto in \(url.lastPathComponent)")
                // Shown where it landed, which is the whole of the feedback a
                // shutter needs: the file is on the Desktop, in plain sight.
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                Diagnostics.write("specchio: la foto non è riuscita — \(problem ?? "")")
            }
        }
    }

    func close() {
        if let was = ringLightWas {
            VideoEffects.setRingLight(was)
            ringLightWas = nil
        }
        if let was = studioLightWas {
            VideoEffects.setStudioLight(was)
            studioLightWas = nil
        }
        session?.stopRunning()
        session = nil
        photo = nil
        screen = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

/// A panel that can take the keyboard, which a borderless one will not do of
/// its own accord — and without it there are no gestures either.
final class MirrorWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The window's content: the camera layer, and a click that puts it away.
final class MirrorView: NSView {
    var onDismiss: (() -> Void)?
    var preview: AVCaptureVideoPreviewLayer?
    weak var controls: MirrorControlsView?
    var isFlipped_ = true

    /// How far in the view is zoomed: one is the whole frame, four is close
    /// enough to check your teeth.
    private var zoom: CGFloat = 1 {
        didSet { zoom = min(max(zoom, 1), 4) }
    }

    /// How far the picture has been slid, relative to the middle of the view.
    ///
    /// Kept as a running offset rather than recomputed from an anchor: what is
    /// under the pointer depends on where the picture already is, so zooming
    /// again after moving the mouse has to start from the current state, not
    /// from the untouched frame.
    private var offset = NSPoint.zero

    /// Moves the picture so that whatever sits under `point` stays there while
    /// the zoom goes from `from` to the current one.
    private func keep(_ point: NSPoint, from previous: CGFloat) {
        guard previous > 0 else { return }
        let px = point.x - bounds.midX
        let py = point.y - bounds.midY
        let ratio = zoom / previous
        offset = NSPoint(x: px - (px - offset.x) * ratio,
                         y: py - (py - offset.y) * ratio)
        clampOffset()
    }

    /// Never so far that the frame shows past the edge of the picture.
    private func clampOffset() {
        let room = NSPoint(x: bounds.width * (zoom - 1) / 2,
                           y: bounds.height * (zoom - 1) / 2)
        offset = NSPoint(x: min(max(offset.x, -room.x), room.x),
                         y: min(max(offset.y, -room.y), room.y))
    }

    private func applyTransform() {
        guard let preview else { return }
        let scale = CATransform3DMakeScale(isFlipped_ ? -zoom : zoom, zoom, 1)
        let slide = CATransform3DMakeTranslation(offset.x, offset.y, 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.transform = CATransform3DConcat(scale, slide)
        CATransaction.commit()
    }

    /// And the wheel moves the picture about, which is what it reads as once
    /// there is more picture than frame.
    override func scrollWheel(with event: NSEvent) {
        guard zoom > 1 else { return }
        offset = NSPoint(x: offset.x + event.scrollingDeltaX,
                         y: offset.y + event.scrollingDeltaY)
        clampOffset()
        applyTransform()
    }

    /// Pinch, not the wheel: a wheel over a picture reads as scrolling it, and
    /// the trackpad already has the gesture everybody means by "zoom".
    override func magnify(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let previous = zoom
        zoom += event.magnification * 2
        keep(point, from: previous)
        applyTransform()
    }

    /// Double-click puts it back to the whole frame.
    override func mouseUp(with event: NSEvent) {
        if event.clickCount >= 2 {
            offset = .zero
            zoom = 1
            applyTransform()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        preview?.frame = bounds
    }

    /// The window is dragged by its background; closing is the cross's job.
    ///
    /// The click also takes the focus back, so the pinch keeps working after a
    /// detour through another window.
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }

    private func finishClick() {}
}


/// What sits on top of the picture: the cross that closes it and the light.
///
/// Translucent on purpose — they are there when you look for them and out of
/// the way when you are looking at yourself.
final class MirrorControlsView: NSView {
    var onClose: (() -> Void)?
    var onShoot: (() -> Void)?

    private var ringOn = VideoEffects.isRingLightOn
    private var intensity = VideoEffects.ringLightIntensity

    /// Called when something outside changed the light — the mirror turning it
    /// on by itself, for one.
    func refresh() {
        ringOn = VideoEffects.isRingLightOn
        intensity = VideoEffects.ringLightIntensity
        colour = Float(MirrorSettings.current.ringColour)
        needsDisplay = true
    }
    private var hovered: Target?
    private var scrubbing = false

    private enum Target { case close, shutter, light, colour, track }

    private var colour = Float(MirrorSettings.current.ringColour)

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// The window is movable by its background, and AppKit will happily drag it
    /// out from under a slider unless the view says the drag is its own.
    override var mouseDownCanMoveWindow: Bool { false }

    /// Top left, where macOS has kept the button that closes a window since
    /// there were windows.
    private var closeRect: NSRect {
        NSRect(x: bounds.minX + 10, y: bounds.maxY - 34, width: 24, height: 24)
    }

    /// The row along the bottom, laid out as one thing and then centred: the
    /// shutter, the light, and — only while the light is on — its colour and
    /// how much of it. Placing each piece from the middle instead leaves the
    /// row leaning to one side the moment a piece comes or goes.
    private var row: (shutter: NSRect, light: NSRect, colour: NSRect, track: NSRect) {
        let gap: CGFloat = 8
        let shutterSide: CGFloat = 28
        let lightWidth: CGFloat = ringOn ? 24 : 28
        var total = shutterSide + gap + lightWidth
        if ringOn { total += gap + 18 + gap + 74 }

        var x = bounds.midX - total / 2
        let shutter = NSRect(x: x, y: 10, width: shutterSide, height: shutterSide)
        x += shutterSide + gap
        let light = NSRect(x: x, y: 12, width: lightWidth, height: 24)
        x += lightWidth + gap
        let colour = NSRect(x: x, y: light.midY - 9, width: 18, height: 18)
        x += 18 + gap
        let track = NSRect(x: x, y: light.midY - 3, width: 74, height: 6)
        return (shutter, light, colour, track)
    }

    private var shutterRect: NSRect { row.shutter }
    private var lightRect: NSRect { row.light }
    private var colourRect: NSRect { row.colour }
    private var trackRect: NSRect { row.track }

    override func draw(_ dirtyRect: NSRect) {
        draw(chip: closeRect, symbol: "xmark", lit: false,
             emphasised: hovered == .close)
        draw(chip: shutterRect, symbol: "camera.fill", lit: false,
             emphasised: hovered == .shutter)
        draw(chip: lightRect, symbol: ringOn ? "sun.max.fill" : "sun.max",
             lit: ringOn, emphasised: hovered == .light)

        guard ringOn else { return }

        let dot = colourRect
        let dotLit = hovered == .colour
        NSColor(calibratedWhite: 0, alpha: dotLit ? Self.plateLit : Self.plate).setFill()
        NSBezierPath(ovalIn: dot).fill()
        // The colour as the system will actually shine it.
        VideoEffects.lightColour(colour)
            .withAlphaComponent(dotLit ? 1 : Self.ink).setFill()
        NSBezierPath(ovalIn: dot.insetBy(dx: 5, dy: 5)).fill()

        let track = trackRect
        let radius = track.height / 2
        let trackLit = hovered == .track || scrubbing
        NSColor(calibratedWhite: 1, alpha: trackLit ? 0.3 : 0.10).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
        let filled = NSRect(x: track.minX, y: track.minY,
                            width: max(track.width * CGFloat(intensity), track.height),
                            height: track.height)
        NSColor(calibratedWhite: 1, alpha: trackLit ? 1 : Self.ink).setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }

    /// How much of the controls shows through at rest. They sit on top of the
    /// picture, which is the thing worth looking at: at rest they are a hint,
    /// and the pointer is what brings them out.
    private static let plate: CGFloat = 0.10
    private static let plateLit: CGFloat = 0.95
    private static let ink: CGFloat = 0.32

    private func draw(chip rect: NSRect, symbol: String, lit: Bool, emphasised: Bool) {
        NSColor(calibratedWhite: 0, alpha: emphasised ? Self.plateLit : Self.plate).setFill()
        NSBezierPath(ovalIn: rect).fill()
        let inset = rect.width * 0.28
        let tint: NSColor = lit ? .systemYellow : .white
        Gauge.symbol(symbol, in: rect.insetBy(dx: inset, dy: inset),
                     color: tint.withAlphaComponent(emphasised ? 1 : Self.ink))
    }

    // MARK: Input

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let next: Target? = closeRect.insetBy(dx: -4, dy: -4).contains(point) ? .close
            : shutterRect.insetBy(dx: -4, dy: -4).contains(point) ? .shutter
            : lightRect.insetBy(dx: -4, dy: -4).contains(point) ? .light
            : (ringOn && colourRect.insetBy(dx: -4, dy: -4).contains(point)) ? .colour
            : (ringOn && trackRect.insetBy(dx: -6, dy: -10).contains(point)) ? .track : nil
        guard next != hovered else { return }
        hovered = next
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
    }

    /// Only the controls answer the mouse; everywhere else the window is
    /// dragged, which is the view underneath's business.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let live = closeRect.insetBy(dx: -4, dy: -4).contains(local)
            || shutterRect.insetBy(dx: -4, dy: -4).contains(local)
            || lightRect.insetBy(dx: -4, dy: -4).contains(local)
            || (ringOn && colourRect.insetBy(dx: -4, dy: -4).contains(local))
            || (ringOn && trackRect.insetBy(dx: -6, dy: -10).contains(local))
        return live ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if closeRect.insetBy(dx: -4, dy: -4).contains(point) {
            onClose?()
            return
        }
        if shutterRect.insetBy(dx: -4, dy: -4).contains(point) {
            onShoot?()
            return
        }
        if lightRect.insetBy(dx: -4, dy: -4).contains(point) {
            ringOn.toggle()
            VideoEffects.setRingLight(ringOn)
            Diagnostics.write("ring light: \(ringOn), intensità \(intensity)")
            needsDisplay = true
            return
        }
        if ringOn, colourRect.insetBy(dx: -4, dy: -4).contains(point) {
            // Round the five stops, one tap at a time.
            let stops = VideoEffects.lightStops
            let next = stops.firstIndex { $0 > colour + 0.01 } ?? 0
            colour = stops[next]
            VideoEffects.setRingLightColour(colour)
            // Remembered, so the next mirror opens the way this one was left.
            var settings = MirrorSettings.current
            settings.ringColour = Double(colour)
            settings.save()
            needsDisplay = true
            return
        }
        if ringOn, trackRect.insetBy(dx: -6, dy: -10).contains(point) {
            scrubbing = true
            scrub(to: point)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard scrubbing else { return }
        scrub(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) { scrubbing = false }

    private func scrub(to point: NSPoint) {
        let track = trackRect
        intensity = Float(min(max((point.x - track.minX) / track.width, 0), 1))
        VideoEffects.setRingLightIntensity(intensity)
        needsDisplay = true
    }
}
