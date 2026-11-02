enum AppleReadinessPresentation {
  static func label(_ state: AppleTranscriptionAssetState?) -> String {
    switch state {
    case .ready: "Ready"
    case .downloadable: "Model not installed"
    case .reservationRequired: "Setup required"
    case .downloading: "Downloading"
    case .unavailable: "Unavailable on this device"
    case .unsupported: "Language not supported"
    case .temporarilyUnavailable: "Temporarily unavailable"
    case nil: "Checking"
    }
  }
}
