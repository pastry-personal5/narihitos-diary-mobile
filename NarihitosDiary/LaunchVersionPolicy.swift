import Foundation

enum LaunchVersionPolicy {
  static let minimum = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1)

  static func isSupported(_ version: OperatingSystemVersion) -> Bool {
    if version.majorVersion != minimum.majorVersion {
      return version.majorVersion > minimum.majorVersion
    }
    if version.minorVersion != minimum.minorVersion {
      return version.minorVersion > minimum.minorVersion
    }
    return version.patchVersion >= minimum.patchVersion
  }
}
