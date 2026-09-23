import AppKit
import SwiftUI

@MainActor protocol NotchPanelDelegate: AnyObject {
    func notchDidConfirm()
    func notchDidCancel()
    func notchDidDismiss()
    func notchDidQuit()
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchPanelController: NSWindowController {
    weak var delegate: NotchPanelDelegate?
    private let model = NotchViewModel()

    init() {
        let panel = NotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 390),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        let hosting = NSHostingView(rootView: NotchRootView(model: model))
        hosting.frame = panel.contentRect(forFrameRect: panel.frame)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false

        model.onConfirm = { [weak self] in self?.delegate?.notchDidConfirm() }
        model.onCancel = { [weak self] in self?.delegate?.notchDidCancel() }
        model.onDismiss = { [weak self] in self?.delegate?.notchDidDismiss() }
        model.onQuit = { [weak self] in self?.delegate?.notchDidQuit() }
        position()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        position()
        window?.orderFrontRegardless()
    }

    func update(_ state: UIState) {
        model.state = state
        window?.ignoresMouseEvents = !state.expanded
        if state.needsConfirmation {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
    }

    private func position() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first, let window else { return }
        let frame = screen.frame
        window.setFrameOrigin(NSPoint(x: frame.midX - window.frame.width / 2, y: frame.maxY - window.frame.height))
    }
}
