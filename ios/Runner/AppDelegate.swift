import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var readAloud: PlatformReadAloud?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      readAloud = PlatformReadAloud(messenger: controller.binaryMessenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// Kept in sync with the other Apple runner. The channel owns no article text
// after an utterance finishes; callbacks are correlated by utterance identity.
// On iPhone/iPad we explicitly use playback/spoken-audio so the reader is not
// muted by the silent switch. `.duckOthers` lowers, rather than stops, music or
// a podcast and `notifyOthersOnDeactivation` lets it recover after narration.
private final class PlatformReadAloud: NSObject, AVSpeechSynthesizerDelegate {
  private let channel: FlutterMethodChannel
  private let synthesizer = AVSpeechSynthesizer()
  private let audioSession = AVAudioSession.sharedInstance()
  private var utterances: [ObjectIdentifier: String] = [:]
  private var audioSessionActive = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "belog/read_aloud", binaryMessenger: messenger)
    super.init()
    synthesizer.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "initialize":
        let voices = AVSpeechSynthesisVoice.speechVoices()
          .sorted { $0.identifier < $1.identifier }
          .map { ["id": $0.identifier, "language": $0.language, "name": $0.name] }
        result(["available": true, "voices": voices])
      case "stop":
        // Keep every mapping until AVSpeechSynthesizer calls didCancel. The
        // Dart controller needs that correlated terminal event to ignore stale
        // speech safely; clearing here used to drop it completely.
        self.synthesizer.stopSpeaking(at: .immediate)
        self.deactivateAudioSessionIfIdle()
        result(nil)
      case "speak":
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? String,
              let text = args["text"] as? String, !text.isEmpty,
              let language = args["language"] as? String,
              let rate = args["rate"] as? Double else {
          result(false)
          return
        }
        let utterance = AVSpeechUtterance(string: text)
        if let voiceID = args["voice"] as? String,
           let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
          utterance.voice = voice
        } else {
          utterance.voice = AVSpeechSynthesisVoice(language: language)
        }
        utterance.rate = min(
          AVSpeechUtteranceMaximumSpeechRate,
          max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(rate))
        )
        guard self.activateAudioSession() else {
          result(false)
          return
        }
        self.utterances[ObjectIdentifier(utterance)] = id
        self.synthesizer.speak(utterance)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func activateAudioSession() -> Bool {
    do {
      try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
      try audioSession.setActive(true)
      audioSessionActive = true
      return true
    } catch {
      // The Dart side converts a rejected request into its existing localized,
      // retryable error state. Do not start visual progress without audio.
      return false
    }
  }

  private func deactivateAudioSessionIfIdle() {
    guard audioSessionActive, utterances.isEmpty, !synthesizer.isSpeaking else { return }
    do {
      try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      // Losing focus is best-effort. There is no user content to recover and
      // another process may have made the session inactive already.
    }
    audioSessionActive = false
  }

  private func emit(_ utterance: AVSpeechUtterance, type: String,
                    range: NSRange? = nil, terminal: Bool = false) {
    let key = ObjectIdentifier(utterance)
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let id = self.utterances[key] else { return }
      var event: [String: Any] = ["id": id, "type": type]
      if let range = range, range.location != NSNotFound {
        event["start"] = range.location
        event["end"] = range.location + range.length
      }
      // Invoke before retiring the correlation. A later utterance can already
      // be queued, so deactivation also waits for every tracked callback.
      self.channel.invokeMethod("event", arguments: event)
      if terminal {
        self.utterances.removeValue(forKey: key)
        self.deactivateAudioSessionIfIdle()
      }
    }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
    emit(utterance, type: "started")
  }
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    emit(utterance, type: "completed", terminal: true)
  }
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    emit(utterance, type: "cancelled", terminal: true)
  }
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                         willSpeakRangeOfSpeechString characterRange: NSRange,
                         utterance: AVSpeechUtterance) {
    emit(utterance, type: "range", range: characterRange)
  }
}
