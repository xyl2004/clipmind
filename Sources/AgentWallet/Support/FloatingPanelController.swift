import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    static let shared = FloatingPanelController()

    private var panel: FloatingChatPanel?
    private var hostingView: NSHostingView<FloatingContextPanelView>?
    private var lastReportedSize = CGSize(width: 836, height: 244)
    private var pendingAnchor: CGRect?

    private override init() {}

    func show(store: AppStore, near sourceRect: CGRect?) {
        let contentView = FloatingContextPanelView(store: store) { [weak self] in
            self?.panel?.orderOut(nil)
        } onSizeChange: { [weak self] size in
            self?.handleContentSizeChange(size)
        }
        pendingAnchor = sourceRect

        if let panel {
            hostingView?.rootView = contentView
            position(panel: panel, size: lastReportedSize, near: sourceRect)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            fadeIn(panel)
            return
        }

        let panel = FloatingChatPanel(
            contentRect: NSRect(x: 0, y: 0, width: lastReportedSize.width, height: lastReportedSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.becomesKeyOnlyIfNeeded = false

        if let content = panel.contentView {
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: content.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
            ])
        }

        self.panel = panel
        self.hostingView = hostingView

        position(panel: panel, size: lastReportedSize, near: sourceRect)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        fadeIn(panel)
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        hostingView = nil
    }

    private func handleContentSizeChange(_ size: CGSize) {
        guard let panel, size.width > 1, size.height > 1 else {
            return
        }

        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 900) * 0.72
        let newSize = CGSize(width: size.width, height: min(size.height, maxHeight))
        lastReportedSize = newSize

        if !panel.isVisible {
            position(panel: panel, size: newSize, near: pendingAnchor)
            return
        }

        var frame = panel.frame
        let delta = newSize.height - frame.height
        guard abs(delta) > 0.5 || abs(newSize.width - frame.width) > 0.5 else {
            return
        }

        frame.origin.y -= delta
        frame.size = newSize
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func position(panel: NSPanel, size: NSSize, near sourceRect: CGRect?) {
        let anchor = sourceRect.flatMap { rect -> CGPoint? in
            guard rect.width.isFinite, rect.height.isFinite, !rect.isEmpty else {
                return nil
            }
            return CGPoint(x: rect.midX, y: rect.minY)
        } ?? NSEvent.mouseLocation

        let screen = ScreenGeometry.screen(containing: anchor) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let margin: CGFloat = 12

        var origin = CGPoint(
            x: anchor.x - size.width / 2,
            y: anchor.y - size.height - 10
        )

        if origin.y < visible.minY + margin {
            let topAnchor = sourceRect?.maxY ?? anchor.y
            origin.y = topAnchor + 10
        }

        origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - size.width - margin)
        origin.y = min(max(origin.y, visible.minY + margin), visible.maxY - size.height - margin)

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func fadeIn(_ panel: NSPanel) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }
}

private final class FloatingChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
