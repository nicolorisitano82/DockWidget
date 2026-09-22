import AVFoundation
import AppKit
import CoreImage

/// Taking a photograph with the mirror's camera, using the screen as the flash.
///
/// The flash is a white window over the screen with the brightness pushed up
/// for as long as it is there: a Mac has no lamp, and the display is the only
/// thing on it that makes light. Both are put back afterwards, whether the
/// picture arrived or not.
final class MirrorShot: NSObject, AVCapturePhotoCaptureDelegate {
    /// Held for the length of the capture: the delegate is not retained by the
    /// output, and a shot whose delegate has gone never calls back.
    private static var inFlight: MirrorShot?

    private let mirrored: Bool
    private let done: (URL?, String?) -> Void
    private var flash: NSWindow?
    private var brightnessWas: Float?

    private init(mirrored: Bool, done: @escaping (URL?, String?) -> Void) {
        self.mirrored = mirrored
        self.done = done
    }

    /// Flashes, waits for the screen to actually be white, and takes one frame.
    static func take(with output: AVCapturePhotoOutput, on screen: NSScreen,
                     mirrored: Bool, done: @escaping (URL?, String?) -> Void) {
        let shot = MirrorShot(mirrored: mirrored, done: done)
        inFlight = shot
        shot.raiseFlash(on: screen)
        // Long enough for the panel to be drawn and the exposure to settle on
        // it: firing with the flash half up gives a picture of the room as it
        // was, which is the whole thing this is trying not to do.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: shot)
        }
    }

    // MARK: The flash

    private func raiseFlash(on screen: NSScreen) {
        brightnessWas = SystemLevels.Brightness.level
        SystemLevels.Brightness.set(1)

        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .white
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            window.animator().alphaValue = 1
        }
        flash = window
    }

    private func lowerFlash() {
        if let was = brightnessWas {
            SystemLevels.Brightness.set(was)
            brightnessWas = nil
        }
        guard let window = flash else { return }
        flash = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        } completionHandler: {
            window.orderOut(nil)
        }
    }

    // MARK: The picture

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { Self.inFlight = nil }
        lowerFlash()

        if let error {
            done(nil, error.localizedDescription)
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = CIImage(data: data) else {
            done(nil, T("La fotocamera non ha restituito niente.",
                        "The camera returned nothing."))
            return
        }
        do {
            done(try write(image), nil)
        } catch {
            done(nil, error.localizedDescription)
        }
    }

    /// On the Desktop, named for the moment it was taken.
    ///
    /// Mirrored to match what was on screen when the button was pressed: the
    /// picture people mean to keep is the one they were looking at, not the one
    /// the camera sends.
    private func write(_ image: CIImage) throws -> URL {
        var picture = image
        if mirrored {
            picture = picture
                .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
                .transformed(by: CGAffineTransform(translationX: picture.extent.width, y: 0))
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'alle' HH.mm.ss"
        let name = T("Specchio \(formatter.string(from: Date())).jpg",
                     "Mirror \(formatter.string(from: Date())).jpg")
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let url = desktop.appendingPathComponent(name)

        let context = CIContext()
        guard let space = picture.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
            throw NSError(domain: "dev.nicolo.underdock.mirror", code: 1, userInfo: [
                NSLocalizedDescriptionKey: T("Spazio colore sconosciuto.", "Unknown colour space."),
            ])
        }
        try context.writeJPEGRepresentation(of: picture, to: url, colorSpace: space,
                                            options: [kCGImageDestinationLossyCompressionQuality
                                                as CIImageRepresentationOption: 0.92])
        return url
    }
}
