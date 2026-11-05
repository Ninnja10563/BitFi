import AppKit
import UserNotifications

@MainActor
enum DockIconVisibility {
    static func showForWindow() {
        NSApp.setActivationPolicy(.regular)
    }

    static func synchronizeWithVisibleDocumentWindows() {
        let hasVisibleDocumentWindow = NSApp.windows.contains { window in
            window.isVisible && window.canBecomeMain
        }
        NSApp.setActivationPolicy(hasVisibleDocumentWindow ? .regular : .accessory)
    }

    static func synchronizeOnNextRunLoop() {
        DispatchQueue.main.async {
            synchronizeWithVisibleDocumentWindows()
        }
    }

}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObservers: [NSObjectProtocol] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Start as a normal app so a Finder launch creates its initial window.
        // Closing every document window later returns us to menu-bar-only mode.
        DockIconVisibility.showForWindow()
        observeWindowLifecycle()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        DockIconVisibility.synchronizeOnNextRunLoop()
    }

    func applicationWillTerminate(_ notification: Notification) {
        let center = NotificationCenter.default
        windowObservers.forEach(center.removeObserver)
        windowObservers.removeAll()
    }

    private func observeWindowLifecycle() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.willCloseNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification
        ]

        windowObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    DockIconVisibility.synchronizeOnNextRunLoop()
                }
            }
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
