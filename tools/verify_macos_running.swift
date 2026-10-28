import AppKit
import CoreGraphics
import Foundation

let pid = pid_t(Int32(CommandLine.arguments[1])!)
guard let app = NSRunningApplication(processIdentifier: pid),
      app.localizedName == "CrispChess",
      app.bundleIdentifier == "com.crispstrobe.crispchess",
      app.isFinishedLaunching else {
  fatalError("Installed app did not finish launching with the expected identity")
}
app.activate(options: [.activateIgnoringOtherApps])
var visibleWindow: [String: Any]?
for _ in 0..<40 {
  let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
  visibleWindow = windows.first { window in
    guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
          (window[kCGWindowLayer as String] as? Int) == 0,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
    return rect.width >= 200 && rect.height >= 200
  }
  if visibleWindow != nil { break }
  Thread.sleep(forTimeInterval: 0.25)
}
guard let window = visibleWindow,
      let number = window[kCGWindowNumber as String] as? UInt32 else {
  fatalError("CrispChess did not present a visible application window")
}
try String(number).write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
print("Running app: \(app.localizedName!), bundle ID: \(app.bundleIdentifier!), window: \(number)")
