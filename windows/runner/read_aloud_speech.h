#ifndef RUNNER_READ_ALOUD_SPEECH_H_
#define RUNNER_READ_ALOUD_SPEECH_H_

#include <windows.h>
#include <sapi.h>
#include <wrl/client.h>
#include <flutter/method_channel.h>

#include <map>
#include <memory>
#include <string>
#include <vector>

// SAPI notifications arrive on the runner's platform thread through this
// private window message, rather than invoking Flutter from a worker thread.
class ReadAloudSpeech {
 public:
  static constexpr UINT kSpeechMessage = WM_APP + 0x63b;
  ReadAloudSpeech(flutter::BinaryMessenger* messenger, HWND window);
  ~ReadAloudSpeech();
  void HandleSpeechEvents();

 private:
  struct Voice {
    std::string id;
    std::string language;
    Microsoft::WRL::ComPtr<ISpObjectToken> token;
  };

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Initialize(HWND window);
  void Stop();
  void Emit(const std::string& id, const char* type, int start = 0, int end = 0);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  Microsoft::WRL::ComPtr<ISpVoice> voice_;
  Microsoft::WRL::ComPtr<ISpObjectToken> default_voice_;
  std::vector<Voice> voices_;
  std::map<ULONG, std::string> utterances_;
};

#endif  // RUNNER_READ_ALOUD_SPEECH_H_
