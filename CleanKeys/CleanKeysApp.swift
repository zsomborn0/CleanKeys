import AppKit
import SwiftUI

@main
struct CleanKeysApp: App {
    @NSApplicationDelegateAdaptor(CleanKeysAppDelegate.self) private var appDelegate
    @StateObject private var model = CleanKeysModel()

    var body: some Scene {
        Window("CleanKeys", id: "main") {
            CleanKeysWindowView(model: model)
                .frame(width: 400)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
