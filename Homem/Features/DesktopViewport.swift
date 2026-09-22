import SwiftUI

enum DesktopControlLayout {
    /// Use existing pillarbox space, without making the fitted desktop smaller.
    /// Base this on fit geometry, not the current zoom, to keep controls stationary.
    static func usesSideRail(viewport: CGSize, remote: CGSize, railWidth: CGFloat) -> Bool {
        guard viewport.width.isFinite, viewport.height.isFinite,
              remote.width.isFinite, remote.height.isFinite,
              viewport.height >= 240, remote.width > 0, remote.height > 0 else { return false }
        let fittedWidth = min(viewport.width, viewport.height * remote.width / remote.height)
        return (viewport.width - fittedWidth) / 2 >= railWidth + 8
    }
}

/// Local canvas gestures never become remote mouse events. UIKit keeps the
/// content beneath the pinch centroid and bounds panning to the enlarged image.
struct DesktopViewport: UIViewRepresentable {
    let model: DesktopModel
    let resetID: Int
    let onPointer: (CGPoint, Int) -> Void

    func makeUIView(context: Context) -> DesktopViewportView { DesktopViewportView() }
    func updateUIView(_ view: DesktopViewportView, context: Context) {
        view.onPointer = onPointer
        view.configure(surface: model.pictureInPicture.surface, remoteSize: model.videoSize,
                       canControl: !model.viewOnly && model.status == "Connected", resetID: resetID)
    }
    static func dismantleUIView(_ view: DesktopViewportView, coordinator: ()) { view.stop() }
}

final class DesktopViewportView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let scrollView = UIScrollView()
    private let canvas = UIView()
    private var videoSurface: DesktopVideoSurface?
    private var remoteSize = CGSize.zero
    private var layoutSize = CGSize.zero
    private var layoutRemoteSize = CGSize.zero
    private var resetID = 0
    private var canControl = false
    private var heldPoint: CGPoint?
    var onPointer: ((CGPoint, Int) -> Void)?
    private lazy var click = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
    private lazy var mouseDrag = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.bounces = false
        scrollView.bouncesZoom = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)
        scrollView.addSubview(canvas)
        // A second finger cancels the mouse drag; pinch and canvas pan remain local.
        mouseDrag.maximumNumberOfTouches = 1
        mouseDrag.delegate = self
        click.delegate = self
        mouseDrag.isEnabled = false
        click.isEnabled = false
        scrollView.addGestureRecognizer(click)
        scrollView.addGestureRecognizer(mouseDrag)
        scrollView.pinchGestureRecognizer?.addTarget(self, action: #selector(pinching(_:)))
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(panningCanvas(_:)))
        scrollView.accessibilityLabel = "Desktop".localized
        scrollView.accessibilityHint = "Pinch to zoom. Drag with two fingers to move the desktop.".localized
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(surface: DesktopVideoSurface? = nil, remoteSize: CGSize, canControl: Bool, resetID: Int) {
        if self.canControl != canControl {
            releasePointer()
            self.canControl = canControl
            mouseDrag.isEnabled = canControl
            click.isEnabled = canControl
        }
        scrollView.panGestureRecognizer.minimumNumberOfTouches = canControl ? 2 : 1
        if let surface, surface.superview !== canvas {
            videoSurface = surface
            canvas.addSubview(surface)
            surface.frame = canvas.bounds
        }
        self.remoteSize = remoteSize
        if self.resetID != resetID {
            self.resetID = resetID
            releasePointer()
            scrollView.setZoomScale(1, animated: false)
            centerCanvas()
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, remoteSize.width > 0, remoteSize.height > 0 else { return }
        guard bounds.size != layoutSize || remoteSize != layoutRemoteSize else { return }
        releasePointer()
        // Preserve the visible remote location through keyboard, pane and fold resizing.
        let oldCenter = canvas.convert(CGPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY), from: scrollView)
        let focus = CGPoint(x: canvas.bounds.width > 0 ? oldCenter.x / canvas.bounds.width : 0.5,
                            y: canvas.bounds.height > 0 ? oldCenter.y / canvas.bounds.height : 0.5)
        let zoom = scrollView.zoomScale
        scrollView.setZoomScale(1, animated: false)
        scrollView.frame = bounds
        let fit = min(bounds.width / remoteSize.width, bounds.height / remoteSize.height)
        canvas.frame = CGRect(origin: .zero, size: CGSize(width: remoteSize.width * fit, height: remoteSize.height * fit))
        if videoSurface?.superview === canvas { videoSurface?.frame = canvas.bounds }
        scrollView.contentSize = canvas.bounds.size
        layoutSize = bounds.size
        layoutRemoteSize = remoteSize
        scrollView.setZoomScale(zoom, animated: false)
        centerCanvas()
        let scaled = scrollView.contentSize
        scrollView.contentOffset = CGPoint(
            x: boundedOffset(focus.x * scaled.width - bounds.width / 2, content: scaled.width, viewport: bounds.width, inset: scrollView.contentInset.left),
            y: boundedOffset(focus.y * scaled.height - bounds.height / 2, content: scaled.height, viewport: bounds.height, inset: scrollView.contentInset.top))
    }
    private func boundedOffset(_ value: CGFloat, content: CGFloat, viewport: CGFloat, inset: CGFloat) -> CGFloat {
        min(max(value, -inset), max(-inset, content - viewport + inset))
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerCanvas() }
    private func centerCanvas() {
        scrollView.contentInset = UIEdgeInsets(
            top: max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2), left: max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2),
            bottom: max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2), right: max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2))
    }
    /// Convert through UIKit's zoom transform, including centering and scroll offset.
    func remotePoint(at location: CGPoint) -> CGPoint? {
        let point = canvas.convert(location, from: self)
        guard canvas.bounds.width > 0, canvas.bounds.height > 0, canvas.bounds.contains(point) else { return nil }
        return CGPoint(x: min(remoteSize.width - 1, point.x / canvas.bounds.width * remoteSize.width),
                       y: min(remoteSize.height - 1, point.y / canvas.bounds.height * remoteSize.height))
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard canControl, let point = remotePoint(at: gesture.location(in: self)) else { return }
        onPointer?(point, 1); onPointer?(point, 0)
    }
    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            guard canControl, gesture.numberOfTouches == 1,
                  scrollView.panGestureRecognizer.numberOfTouches < 2,
                  scrollView.pinchGestureRecognizer?.state != .began,
                  scrollView.pinchGestureRecognizer?.state != .changed,
                  let point = remotePoint(at: gesture.location(in: self)) else { releasePointer(); return }
            if gesture.state == .began {
                let location = gesture.location(in: self)
                let movement = gesture.translation(in: self)
                if let start = remotePoint(at: CGPoint(x: location.x - movement.x, y: location.y - movement.y)) {
                    onPointer?(start, 1)
                }
            }
            heldPoint = point; onPointer?(point, 1)
        default: releasePointer()
        }
    }
    @objc private func pinching(_ gesture: UIPinchGestureRecognizer) { releasePointer() }
    @objc private func panningCanvas(_ gesture: UIPanGestureRecognizer) {
        if gesture.numberOfTouches >= 2 { releasePointer() }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Let the scroll view's two-finger gestures take over and cancel a held mouse button.
        other === scrollView.panGestureRecognizer || other === scrollView.pinchGestureRecognizer
    }
    func releasePointer() {
        if let heldPoint { onPointer?(heldPoint, 0); self.heldPoint = nil }
    }
    func stop() { releasePointer() }
}
