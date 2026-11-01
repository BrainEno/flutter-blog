import AVFoundation
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var readAloud: PlatformReadAloud?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    readAloud = PlatformReadAloud(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
// Kept in sync with the other Apple runner. The channel owns no article text
// after an utterance finishes; callbacks are correlated by utterance identity.
private final class PlatformReadAloud: NSObject, AVSpeechSynthesizerDelegate {
  private let channel: FlutterMethodChannel
  private let synthesizer = AVSpeechSynthesizer()
  private var utterances: [ObjectIdentifier: String] = [:]

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
          .map { ["id": $0.identifier, "language": $0.language] }
        result(["available": true, "voices": voices])
      case "stop":
        self.utterances.removeAll()
        self.synthesizer.stopSpeaking(at: .immediate)
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
        self.utterances[ObjectIdentifier(utterance)] = id
        self.synthesizer.speak(utterance)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
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
      if terminal { self.utterances.removeValue(forKey: key) }
      self.channel.invokeMethod("event", arguments: event)
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
