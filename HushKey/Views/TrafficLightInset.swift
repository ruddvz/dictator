import AppKit
import SwiftUI

/// Moves the window's close, minimise and zoom buttons down and in, so they sit level with the
/// hub toolbar in a taller title strip (after Wispr Flow: centred 21 pt down, the first 23 pt in)
/// instead of crowding the top-left corner. AppKit puts them back on resize and full screen,
/// so they are placed again whenever the window lays out.
struct TrafficLightInset: NSViewRepresentable {
    var height: CGFloat
    var leading: CGFloat = 16
    var spacing: CGFloat = 20

    func makeNSView(context: Context) -> NSView { InsetView(height: height, leading: leading, spacing: spacing) }

    func updateNSView(_ view: NSView, context: Context) {
        guard let view = view as? InsetView else { return }
        view.height = height
        view.place()
    }

    final class InsetView: NSView {
        var height: CGFloat
        let leading: CGFloat
        let spacing: CGFloat
        private var observers: [NSObjectProtocol] = []

        init(height: CGFloat, leading: CGFloat, spacing: CGFloat) {
            self.height = height
            self.leading = leading
            self.spacing = spacing
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                         NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.place() }
                })
            }
            DispatchQueue.main.async { [weak self] in self?.place() }
        }

        override func layout() {
            super.layout()
            place()
        }

        func place() {
            guard let window, !window.styleMask.contains(.fullScreen),
                  let close = window.standardWindowButton(.closeButton),
                  let titlebar = close.superview?.superview else { return }
            // Grow the title bar container so the buttons aren't clipped once moved down.
            var frame = titlebar.frame
            if frame.height != height {
                frame.size.height = height
                frame.origin.y = window.frame.height - height
                titlebar.frame = frame
            }
            let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for (index, type) in buttons.enumerated() {
                guard let button = window.standardWindowButton(type) else { continue }
                let origin = CGPoint(x: leading + CGFloat(index) * spacing,
                                     y: (height - button.frame.height) / 2)
                if button.frame.origin != origin { button.setFrameOrigin(origin) }
            }
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
