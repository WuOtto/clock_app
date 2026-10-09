import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    
    // 注册平台通道
    registerPlatformChannel()
  }
  
  private func registerPlatformChannel() {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }
    
    let channel = FlutterMethodChannel(
      name: "countdown/status_bar",
      binaryMessenger: controller.engine.binaryMessenger
    )
    
    channel.setMethodCallHandler { (call, result) in
      if call.method == "activateApp" {
        NSApp.activate(ignoringOtherApps: true)
        self.mainFlutterWindow?.makeKeyAndOrderFront(nil)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // 前台时也显示通知横幅
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.alert, .badge, .sound])
  }
}
