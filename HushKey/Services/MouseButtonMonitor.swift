import AppKit

/// Watches one extra mouse button (middle or side) system-wide and reports press and release.
/// It uses event monitors, not an event tap, so other apps still receive the click.
@MainActor
final class MouseButtonMonitor {
    private var monitors: [Any] = []
    private var button: Int?
    private var isDown = false

    var isInstalled: Bool { !monitors.isEmpty }

    func install(button: Int, action: @escaping (Bool) -> Void) {
        uninstall()
        self.button = button
        let handler: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.buttonNumber == self.button else { return }
                let pressed = event.type == .otherMouseDown
                guard pressed != self.isDown else { return }
                self.isDown = pressed
                action(pressed)
            }
        }
        let mask: NSEvent.EventTypeMask = [.otherMouseDown, .otherMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    func uninstall() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        button = nil
        isDown = false
    }
}
