import SwiftUI
import AppKit

@main
struct DisplayFocusApp: App {
    @StateObject private var model = Model()
    init() { NSApplication.shared.setActivationPolicy(.accessory) } // 仅菜单栏，无 Dock 图标
    private static func menuIcon(_ image: NSImage) -> NSImage {
        image.size = NSSize(width: 22, height: 22)
        image.isTemplate = true
        return image
    }
    var body: some Scene {
        MenuBarExtra { MenuView(m: model) } label: {
            if let url = Bundle.main.url(forResource: "MenuIcon", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: Self.menuIcon(image))
            } else {
                Image(systemName: "display").accessibilityLabel("DisplayFocus")
            }
        }
            .menuBarExtraStyle(.window)
    }
}
