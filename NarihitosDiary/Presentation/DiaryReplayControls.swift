import SwiftUI
import UIKit

struct DiaryReplayControls: View {
  @ObservedObject var actions: DiaryActionsModel
  let handle: CatalogItemHandle

  private var replay: DiaryReplayCoordinator? { actions.replay }
  private var state: DiaryReplayState { replay?.state(for: handle) ?? .idle }
  private var playing: Bool { state == .playing }
  private var elapsed: Double { replay?.elapsed(for: handle) ?? 0 }
  private var duration: Double { replay?.duration(for: handle) ?? 0 }
  private var mediaTime: String { time(elapsed) + " of " + time(duration) }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Audio").font(.subheadline).foregroundStyle(.secondary)
      HStack(spacing: 16) {
        Button {
          if playing { replay?.pause(for: handle) } else { replay?.play(handle) }
        } label: {
          InterfaceIcon(playing ? .pause : .play).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(playing ? "Pause audio" : "Play audio")
        .accessibilityIdentifier("diary-audio-play-pause")
        .disabled(replay == nil || state == .loading)
        Button {
          replay?.seek(to: elapsed - 15, for: handle)
        } label: {
          InterfaceIcon(.seekBack).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Seek backward 15 seconds")
        .disabled(duration == 0)
        Button {
          replay?.seek(to: elapsed + 15, for: handle)
        } label: {
          InterfaceIcon(.seekForward).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Seek forward 15 seconds")
        .disabled(duration == 0)
      }
      DiaryPositionControl(elapsed: elapsed, duration: duration) { position in
        replay?.seek(to: position, for: handle)
      }
      .frame(minHeight: 44)
      Text(mediaTime).monospacedDigit().font(.caption).accessibilityHidden(true)
      if state == .loading { ProgressView("Loading audio") }
      if state == .unavailable {
        Text(
          "Audio is temporarily unavailable. Try again when recording or other audio work finishes."
        )
        .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .disabled(actions.isDeleting)
  }

  private func time(_ seconds: Double) -> String {
    Duration.seconds(max(seconds, 0)).formatted(.time(pattern: .minuteSecond))
  }
}

/// Keep touch seeking continuous while giving VoiceOver a fixed, meaningful interval.
private struct DiaryPositionControl: UIViewRepresentable {
  let elapsed: Double
  let duration: Double
  let seek: (Double) -> Void

  func makeUIView(context: Context) -> DiaryPositionSlider {
    DiaryPositionSlider()
  }

  func updateUIView(_ slider: DiaryPositionSlider, context: Context) {
    slider.seek = seek
    slider.maximumValue = Float(max(duration, 0.001))
    slider.isEnabled = duration > 0
    if !slider.isTracking { slider.value = Float(elapsed) }
    slider.updateSpokenPosition()
  }
}

private final class DiaryPositionSlider: UISlider {
  var seek: ((Double) -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    accessibilityLabel = "Audio position"
    accessibilityIdentifier = "diary-audio-position"
    addTarget(self, action: #selector(positionChanged), for: .valueChanged)
  }

  required init?(coder: NSCoder) { nil }

  override func accessibilityIncrement() { adjust(by: 15) }
  override func accessibilityDecrement() { adjust(by: -15) }

  func updateSpokenPosition() {
    let elapsed = Duration.seconds(Double(value)).formatted(.time(pattern: .minuteSecond))
    let total = Duration.seconds(Double(maximumValue)).formatted(.time(pattern: .minuteSecond))
    accessibilityValue = elapsed + " of " + total
  }

  private func adjust(by seconds: Float) {
    guard isEnabled else { return }
    value = min(max(value + seconds, minimumValue), maximumValue)
    positionChanged()
  }

  @objc private func positionChanged() {
    updateSpokenPosition()
    seek?(Double(value))
  }
}
