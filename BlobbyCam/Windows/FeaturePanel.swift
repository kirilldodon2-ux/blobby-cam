import AppKit

@MainActor
final class FeaturePanel: NSPanel, NSWindowDelegate {
    let featureID: FeatureID
    private(set) var isUserResizing = false
    var onUserResize: ((FeatureID, NSSize) -> Void)?
    var onUserClose: ((FeatureID) -> Void)?

    init(featureID: FeatureID, frame: NSRect) {
        self.featureID = featureID
        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        title = featureID.windowTitle
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

    func windowWillStartLiveResize(_ notification: Notification) {
        isUserResizing = true
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        isUserResizing = false
        if let size = contentView?.frame.size {
            onUserResize?(featureID, size)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // The red control changes feature state; the persistent native panel is reused on ON.
        onUserClose?(featureID)
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
