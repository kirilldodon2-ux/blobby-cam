import AppKit

@MainActor
final class FeaturePanel: NSPanel, NSWindowDelegate {
    private(set) var windowID: WindowInstanceID
    var featureID: FeatureID { windowID.featureID }
    private(set) var isUserResizing = false
    var onUserResize: ((WindowInstanceID, NSSize) -> Void)?
    var onUserClose: ((WindowInstanceID) -> Void)?

    convenience init(featureID: FeatureID, frame: NSRect) {
        self.init(windowID: WindowInstanceID(featureID: featureID, serial: 1), frame: frame)
    }

    init(windowID: WindowInstanceID, frame: NSRect) {
        self.windowID = windowID
        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        title = windowID.featureID.windowTitle
        appearance = NSAppearance(named: .darkAqua)
        titleVisibility = .visible
        titlebarAppearsTransparent = false
        isFloatingPanel = true
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        level = .floating
        isOpaque = true
        backgroundColor = .black
        hidesOnDeactivate = false
        // Keep native titlebar controls available. The nonactivating panel style and key-window
        // overrides below keep those clicks from transferring keyboard focus to a feature panel.
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let content = TransparentPanelContentView(frame: NSRect(origin: .zero, size: frame.size))
        content.autoresizingMask = [.width, .height]
        contentView = content
        contentMinSize = NSSize(width: 80, height: 60)
        contentMaxSize = NSSize(width: 960, height: 720)
        delegate = self
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func installRenderView(_ view: NSView) {
        contentView = view
    }

    func prepareForReuse(as windowID: WindowInstanceID) {
        precondition(windowID.featureID == self.windowID.featureID)
        self.windowID = windowID
        let contentSize = contentView?.frame.size ?? frame.size
        let placeholder = TransparentPanelContentView(frame: NSRect(origin: .zero, size: contentSize))
        placeholder.autoresizingMask = [.width, .height]
        contentView = placeholder
        delegate = self
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        isUserResizing = true
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        isUserResizing = false
        if let size = contentView?.frame.size {
            onUserResize?(windowID, size)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // AppState removes this exact ID, or turns off the final retained instance.
        onUserClose?(windowID)
        orderOut(nil)
        return false
    }

    required init?(coder: NSCoder) {
        fatalError("FeaturePanel does not support coder initialization")
    }
}

@MainActor
private final class TransparentPanelContentView: NSView {
    override var isOpaque: Bool { false }
}
