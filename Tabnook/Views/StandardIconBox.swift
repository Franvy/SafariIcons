import SwiftUI
import AppKit

struct ClickOutsideResigner: NSViewRepresentable {
    let isActive: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.updateActive(isActive)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateActive(isActive)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var monitor: Any?

        func updateActive(_ active: Bool) {
            if active, monitor == nil {
                install()
            } else if !active, monitor != nil {
                uninstall()
            }
        }

        fileprivate func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
                guard let window = event.window else { return event }
                let location = event.locationInWindow
                let hit = window.contentView?.hitTest(location)
                var node: NSView? = hit
                while let view = node {
                    if view is NSTextView || view is NSTextField {
                        return event
                    }
                    node = view.superview
                }
                DispatchQueue.main.async { [weak window] in
                    window?.makeFirstResponder(nil)
                }
                return event
            }
        }

        fileprivate func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            uninstall()
        }
    }
}

struct StandardIconBox<Content: View>: View {
    let size: CGFloat
    let backgroundColor: Color
    let content: Content

    init(size: CGFloat, backgroundColor: Color = .clear, @ViewBuilder content: () -> Content) {
        self.size = size
        self.backgroundColor = backgroundColor
        self.content = content()
    }

    private var cornerRadius: CGFloat {
        IconBoxGeometry.cornerRadius(for: size)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(backgroundColor)

            content
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }
}
