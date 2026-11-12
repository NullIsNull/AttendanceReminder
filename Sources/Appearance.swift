// SPDX-License-Identifier: GPL-3.0-only
import AppKit

/// A single glass surface keeps the form readable without stacking refractive layers.
final class GlassSurface: NSView {
    let content = NSView()
    private let radius: CGFloat
    private var material: NSView?
    private var accessibilityObserver: NSObjectProtocol?

    init(frame: NSRect = .zero, radius: CGFloat = 28) {
        self.radius = radius
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.masksToBounds = true
        updateMaterial()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.updateMaterial() }
    }

    required init?(coder: NSCoder) { fatalError("GlassSurface does not support archives") }

    deinit {
        if let observer = accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    private func updateMaterial() {
        content.removeFromSuperview()
        material?.removeFromSuperview()
        let surface: NSView
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            surface = NSView()
            surface.addSubview(content)
            Appearance.pin(content, to: surface)
        } else if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = radius
            glass.contentView = content
            surface = glass
        } else {
            let frost = NSVisualEffectView()
            frost.material = .hudWindow
            frost.blendingMode = .behindWindow
            frost.state = .active
            frost.addSubview(content)
            Appearance.pin(content, to: frost)
            surface = frost
        }
        addSubview(surface)
        Appearance.pin(surface, to: self)
        material = surface
        updateContrast()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateContrast()
    }

    private func updateContrast() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            layer?.backgroundColor = (opaque ? NSColor.windowBackgroundColor : NSColor.clear).cgColor
            let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            layer?.borderColor = (highContrast ? NSColor.labelColor.withAlphaComponent(0.6) : NSColor.separatorColor.withAlphaComponent(0.35)).cgColor
            layer?.borderWidth = highContrast ? 1.5 : 0.5
        }
    }
}

final class FormDocumentView: NSView {
    override var isFlipped: Bool { true }
}

enum Appearance {
    static func pin(_ view: NSView, to parent: NSView, inset: CGFloat = 0) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            view.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            view.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
        ])
    }

    static func symbol(_ name: String, size: CGFloat, color: NSColor = .controlAccentColor) -> NSImageView {
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium))
        image.contentTintColor = color
        image.imageScaling = .scaleProportionallyDown
        image.translatesAutoresizingMaskIntoConstraints = false
        image.widthAnchor.constraint(equalToConstant: size + 6).isActive = true
        image.heightAnchor.constraint(equalToConstant: size + 6).isActive = true
        image.setAccessibilityElement(false)
        return image
    }

    static func button(_ button: NSButton, primary: Bool = false, symbol: String? = nil, large: Bool = false) {
        button.bezelStyle = .rounded
        button.controlSize = large ? .large : .regular
        if #available(macOS 26.0, *) {
            button.borderShape = .capsule
            button.tintProminence = primary ? .primary : .none
            if primary { button.bezelStyle = .glass }
        }
        if primary { button.bezelColor = .controlAccentColor }
        if let symbol = symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
        }
    }

    static func alert(title: String, message: String, symbol: String = "clock.badge.checkmark") -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 44, weight: .regular))
        return alert
    }

    static func menuIcon(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        image?.size = NSSize(width: 16, height: 16)
        return image
    }
}
