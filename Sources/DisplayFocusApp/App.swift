import SwiftUI
import AppKit

@main
struct DisplayFocusApp: App {
    @StateObject private var model = Model()
    init() { NSApplication.shared.setActivationPolicy(.accessory) } // 仅菜单栏，无 Dock 图标
    var body: some Scene {
        MenuBarExtra("DisplayFocus", systemImage: "display.2") { MenuView(m: model) }
            .menuBarExtraStyle(.window)
    }
}
