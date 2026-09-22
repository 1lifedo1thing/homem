import AVKit
import SwiftUI
import WebRTC
import Observation

final class DesktopVideoSurface: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
    override init(frame: CGRect) {
        super.init(frame: frame)
        displayLayer.videoGravity = .resizeAspect
        var timebase: CMTimebase?
        if CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase) == noErr,
           let timebase {
            CMTimebaseSetTime(timebase, time: CMClockGetTime(CMClockGetHostTimeClock()))
            CMTimebaseSetRate(timebase, rate: 1)
            displayLayer.controlTimebase = timebase
        }
        backgroundColor = .black
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// A live sample-buffer player, shared by the inline desktop and the system PiP window.
@MainActor @Observable final class DesktopPictureInPicture: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    private(set) var isActive = false
    private(set) var isStarting = false
    private(set) var duplicatesInline = false
    var error: String?
    var keepsConnectionAlive: Bool { isActive || isStarting }
    var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }
    @ObservationIgnored let surface = DesktopVideoSurface()
    @ObservationIgnored let duplicateSurface = DesktopVideoSurface()
    @ObservationIgnored private weak var model: DesktopModel?
    @ObservationIgnored private var retainedModel: DesktopModel?
    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private var possibility: NSKeyValueObservation?
    @ObservationIgnored private var startTimeout: Task<Void, Never>?
    @ObservationIgnored private var startRequested = false
    @ObservationIgnored private var restoringViewer = false
    @ObservationIgnored private var renderer: DesktopPiPRenderer?
    @ObservationIgnored private var track: RTCVideoTrack?
    @ObservationIgnored private var viewers = 0
    nonisolated private let playback = DesktopPlaybackState()
    private var paused: Bool { get { playback.paused } set { playback.paused = newValue } }
    @ObservationIgnored private var lastBuffer: CVPixelBuffer?
    @ObservationIgnored private static var active: DesktopPictureInPicture?

    init(model: DesktopModel) {
        self.model = model
        super.init()
        guard isSupported else { return }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: surface.displayLayer, playbackDelegate: self)
        controller = AVPictureInPictureController(contentSource: source)
        controller?.delegate = self
        controller?.requiresLinearPlayback = true
        controller?.canStartPictureInPictureAutomaticallyFromInline = false
        possibility = controller?.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.startWhenReady() }
        }
    }
    func viewerAppeared() { viewers += 1 }
    func viewerDisappeared(allowDisconnect: Bool = true) {
        viewers = max(0, viewers - 1)
        guard allowDisconnect else { return }
        // Fullscreen transitions attach the replacement viewer in the same UI update.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.viewers == 0, !self.keepsConnectionAlive else { return }
            self.model?.disconnect()
        }
    }
    func updateTrack(_ track: RTCVideoTrack?) {
        guard self.track !== track else { return }
        if let renderer { self.track?.remove(renderer) }
        self.track = track
        if let track {
            let renderer = DesktopPiPRenderer(owner: self)
            self.renderer = renderer
            track.add(renderer)
        } else { renderer = nil }
    }
    func display(_ image: CGImage) {
        guard let buffer = DesktopVideoSamples.pixelBuffer(image: image) else { return }
        display(buffer)
    }
    func display(_ buffer: CVPixelBuffer) {
        lastBuffer = buffer
        // PiP owns its playback state. An interactive duplicate keeps receiving
        // live frames even when the user pauses the floating video player.
        if duplicatesInline { enqueue(buffer, on: duplicateSurface.displayLayer) }
        guard !paused else { return }
        enqueue(buffer, on: surface.displayLayer)
    }
    private func enqueue(_ buffer: CVPixelBuffer, on layer: AVSampleBufferDisplayLayer) {
        if layer.status == .failed { layer.flush() }
        guard layer.isReadyForMoreMediaData, let sample = DesktopVideoSamples.sample(buffer) else { return }
        layer.enqueue(sample)
    }
    func showInBoth() {
        guard isActive else { return }
        duplicatesInline = true
        if let lastBuffer { enqueue(lastBuffer, on: duplicateSurface.displayLayer) }
    }
    func received(_ frame: RTCVideoFrame, from renderer: DesktopPiPRenderer) {
        guard self.renderer === renderer, let buffer = DesktopVideoSamples.pixelBuffer(frame: frame) else { return }
        model?.videoSize = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        model?.hasVideo = true
        display(buffer)
    }
    func start() {
        guard isSupported, !keepsConnectionAlive, let model, model.hasVideo else { return }
        Self.stopActive()
        error = nil
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try audio.setActive(true)
        } catch { self.error = "Picture in Picture could not start. Try again.".localized; return }
        Self.active = self
        retainedModel = model
        isStarting = true
        duplicatesInline = false
        startRequested = false
        paused = false
        controller?.invalidatePlaybackState()
        if let lastBuffer { display(lastBuffer) }
        startWhenReady()
        startTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled, self.isStarting else { return }
            self.error = "Picture in Picture could not start. Try again.".localized
            self.finish()
        }
    }
    private func startWhenReady() {
        guard isStarting, !startRequested, controller?.isPictureInPicturePossible == true else { return }
        startRequested = true
        controller?.startPictureInPicture()
    }
    func stop() {
        startTimeout?.cancel()
        controller?.stopPictureInPicture()
        if !isActive { finish() }
    }
    static func stopActive(disconnect: Bool = false) {
        guard let current = active else { return }
        current.controller?.stopPictureInPicture()
        current.finish()
        if disconnect {
            current.model?.disconnect()
            current.lastBuffer = nil
            current.surface.displayLayer.flushAndRemoveImage()
            current.duplicateSurface.displayLayer.flushAndRemoveImage()
        }
    }
    private func finish() {
        startTimeout?.cancel(); startTimeout = nil
        isActive = false; isStarting = false; startRequested = false; paused = false
        duplicatesInline = false
        duplicateSurface.displayLayer.flushAndRemoveImage()
        if Self.active === self {
            Self.active = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        // Restore can complete while the scene is still transitioning to foreground.
        if !restoringViewer, viewers == 0 || UIApplication.shared.applicationState == .background { model?.disconnect() }
        restoringViewer = false
        retainedModel = nil
        if let lastBuffer { display(lastBuffer) }
    }
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            guard Self.active === self else { pictureInPictureController.stopPictureInPicture(); return }
            self.isActive = true; self.isStarting = false; self.startTimeout?.cancel()
        }
    }
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.finish() }
    }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in
            self.error = "Picture in Picture could not start. Try again.".localized
            self.finish()
        }
    }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in self.restoreViewer(completionHandler) }
    }
    private func restoreViewer(_ completion: @escaping (Bool) -> Void) {
        guard let model else { completion(false); return }
        if viewers > 0 { restoringViewer = true; completion(true); return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { completion(false); return }
        while let presented = presenter.presentedViewController { presenter = presented }
        let viewer = UIHostingController(rootView: DesktopContent(model: model, isFullscreen: true))
        viewer.modalPresentationStyle = .fullScreen
        restoringViewer = true
        presenter.present(viewer, animated: true) { completion(true) }
    }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        playback.paused = !playing
        Task { @MainActor in
            if playing, let lastBuffer = self.lastBuffer { self.display(lastBuffer) }
            self.controller?.invalidatePlaybackState()
        }
    }
    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }
    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool { playback.paused }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) { completionHandler() }

}

/// WebRTC calls renderFrame on its own thread. Only the current track may publish frames.
final class DesktopPiPRenderer: NSObject, RTCVideoRenderer {
    private weak var owner: DesktopPictureInPicture?
    private let lock = NSLock()
    private var pending = false
    init(owner: DesktopPictureInPicture) { self.owner = owner }
    func setSize(_ size: CGSize) {}
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        lock.lock()
        if pending { lock.unlock(); return }
        pending = true; lock.unlock()
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.owner?.received(frame, from: self)
            self.lock.withLock { self.pending = false }
        }
    }
}

/// Frames use the host clock and immediate presentation because this is a live desktop.
enum DesktopVideoSamples {
    static func sample(_ buffer: CVPixelBuffer) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
            attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        return sample
    }
    static func pixelBuffer(image: CGImage) -> CVPixelBuffer? {
        guard let buffer = allocate(width: image.width, height: image.height, format: kCVPixelFormatType_32BGRA) else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }
    static func pixelBuffer(frame: RTCVideoFrame) -> CVPixelBuffer? {
        let buffer: CVPixelBuffer
        if let native = frame.buffer as? RTCCVPixelBuffer { buffer = native.pixelBuffer }
        else {
            let source = frame.buffer.toI420()
            guard let target = allocate(width: Int(source.width), height: Int(source.height), format: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) else { return nil }
            CVPixelBufferLockBaseAddress(target, [])
            defer { CVPixelBufferUnlockBaseAddress(target, []) }
            guard let y = CVPixelBufferGetBaseAddressOfPlane(target, 0), let uv = CVPixelBufferGetBaseAddressOfPlane(target, 1) else { return nil }
            for row in 0..<Int(source.height) {
                memcpy(y.advanced(by: row * CVPixelBufferGetBytesPerRowOfPlane(target, 0)), source.dataY.advanced(by: row * Int(source.strideY)), Int(source.width))
            }
            for row in 0..<Int(source.chromaHeight) {
                let dest = uv.advanced(by: row * CVPixelBufferGetBytesPerRowOfPlane(target, 1)).assumingMemoryBound(to: UInt8.self)
                for col in 0..<Int(source.chromaWidth) {
                    dest[2 * col] = source.dataU[row * Int(source.strideU) + col]
                    dest[2 * col + 1] = source.dataV[row * Int(source.strideV) + col]
                }
            }
            buffer = target
        }
        guard frame.rotation != ._0 else { return buffer }
        let orientation: CGImagePropertyOrientation = frame.rotation == ._90 ? .right : frame.rotation == ._180 ? .down : .left
        let image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        guard let rotated = allocate(width: Int(image.extent.width), height: Int(image.extent.height), format: kCVPixelFormatType_32BGRA) else { return nil }
        CIContext().render(image, to: rotated)
        return rotated
    }
    private static func allocate(width: Int, height: Int, format: OSType) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, attributes, &buffer) == kCVReturnSuccess else { return nil }
        return buffer
    }
}

private final class DesktopPlaybackState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var paused: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
