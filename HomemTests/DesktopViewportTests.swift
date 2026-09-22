import XCTest
@testable import Homem

@MainActor final class DesktopViewportTests: XCTestCase {
    private func viewport(size: CGSize = CGSize(width: 400, height: 800), control: Bool = false) -> DesktopViewportView {
        let view = DesktopViewportView(frame: CGRect(origin: .zero, size: size))
        view.configure(image: nil, track: nil, remoteSize: CGSize(width: 1280, height: 720), canControl: control, resetID: 0)
        view.layoutIfNeeded()
        return view
    }
    func testFitRejectsLetterboxAndMapsDesktopCenter() throws {
        let view = viewport()
        XCTAssertNil(view.remotePoint(at: CGPoint(x: 200, y: 100)))
        let center = try XCTUnwrap(view.remotePoint(at: CGPoint(x: 200, y: 400)))
        XCTAssertEqual(center.x, 640, accuracy: 0.01)
        XCTAssertEqual(center.y, 360, accuracy: 1) // UIKit rounds centering insets to display pixels.
    }
    func testZoomAndPanMapToRemoteCoordinates() throws {
        let view = viewport(size: CGSize(width: 400, height: 300))
        view.scrollView.setZoomScale(3, animated: false)
        view.scrollView.contentOffset = CGPoint(x: 250, y: 100)
        let point = try XCTUnwrap(view.remotePoint(at: CGPoint(x: 200, y: 150)))
        XCTAssertEqual(point.x, 480, accuracy: 0.01)
        XCTAssertEqual(point.y, 250 / (3 * 400.0 / 1280), accuracy: 0.01)
    }
    func testResizePreservesZoomAndVisibleRemoteCenter() throws {
        let view = viewport(size: CGSize(width: 400, height: 300))
        view.scrollView.setZoomScale(3, animated: false)
        view.scrollView.contentOffset = CGPoint(x: 250, y: 100)
        let before = try XCTUnwrap(view.remotePoint(at: CGPoint(x: 200, y: 150)))
        view.frame.size = CGSize(width: 600, height: 400)
        view.setNeedsLayout(); view.layoutIfNeeded()
        let after = try XCTUnwrap(view.remotePoint(at: CGPoint(x: 300, y: 200)))
        XCTAssertEqual(view.scrollView.zoomScale, 3, accuracy: 0.01)
        XCTAssertEqual(after.x, before.x, accuracy: 0.01)
        XCTAssertEqual(after.y, before.y, accuracy: 0.01)
    }
    func testResetRestoresFitAndPanningUsesTwoFingersInControlMode() throws {
        let view = viewport(control: true)
        var mouseEvents = 0
        view.onPointer = { _, _ in mouseEvents += 1 }
        XCTAssertEqual(view.scrollView.panGestureRecognizer.minimumNumberOfTouches, 2)
        view.scrollView.setZoomScale(4, animated: false)
        view.configure(image: nil, track: nil, remoteSize: CGSize(width: 1280, height: 720), canControl: false, resetID: 1)
        XCTAssertEqual(view.scrollView.panGestureRecognizer.minimumNumberOfTouches, 1)
        XCTAssertEqual(view.scrollView.zoomScale, 1)
        XCTAssertNil(view.remotePoint(at: CGPoint(x: 200, y: 100)))
        let center = try XCTUnwrap(view.remotePoint(at: CGPoint(x: 200, y: 400)))
        XCTAssertEqual(center.x, 640, accuracy: 0.01)
        XCTAssertEqual(center.y, 360, accuracy: 1) // UIKit rounds centering insets to display pixels.
        XCTAssertEqual(mouseEvents, 0, "Local canvas zoom/reset must never click the remote desktop")
    }
}
