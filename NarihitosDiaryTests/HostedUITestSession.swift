import Darwin
import Foundation
import Testing

/// Hosted suites share one application and key window, even when each suite is serialized.
@MainActor
enum HostedUITestSession {
  private static var occupied = false
  private static var waiters: [CheckedContinuation<Void, Never>] = []
  private static var automation: AccessibilityAutomation?

  static func acquire() async throws {
    if occupied {
      await withCheckedContinuation { waiters.append($0) }
    } else {
      occupied = true
    }
    do {
      automation = try AccessibilityAutomation()
    } catch {
      release()
      throw error
    }
  }

  static func release() {
    automation?.restore()
    automation = nil
    if waiters.isEmpty {
      occupied = false
    } else {
      waiters.removeFirst().resume()
    }
  }
}

/// Test-only activation of UIKit's lazy accessibility support, with its prior setting restored.
/// These private automation symbols must never be linked into the app target.
/// Uses the automation seam also used by cashapp/AccessibilitySnapshot.
@MainActor
private struct AccessibilityAutomation {
  private let library: UnsafeMutableRawPointer
  private let previous: Int32
  private let setEnabled: @convention(c) (Int32) -> Void

  init() throws {
    let root = ProcessInfo.processInfo.environment["IPHONE_SIMULATOR_ROOT"] ?? ""
    library = try #require(dlopen(root + "/usr/lib/libAccessibility.dylib", RTLD_NOW))
    do {
      let getter = try #require(dlsym(library, "_AXSAutomationEnabled"))
      let setter = try #require(dlsym(library, "_AXSSetAutomationEnabled"))
      previous = unsafeBitCast(getter, to: (@convention(c) () -> Int32).self)()
      setEnabled = unsafeBitCast(setter, to: (@convention(c) (Int32) -> Void).self)
      setEnabled(1)
    } catch {
      dlclose(library)
      throw error
    }
  }

  func restore() {
    setEnabled(previous)
    dlclose(library)
  }
}
