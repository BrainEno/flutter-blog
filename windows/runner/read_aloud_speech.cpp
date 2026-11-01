#include "read_aloud_speech.h"

#include <flutter/standard_method_codec.h>
#pragma warning(push)
#pragma warning(disable : 4996)
#include <sphelper.h>
#pragma warning(pop)

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cwchar>
#include <utility>
#include <variant>

#include "utils.h"

namespace {
using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

const EncodableValue* Field(const EncodableMap& args, const char* name) {
  auto it = args.find(EncodableValue(name));
  return it == args.end() ? nullptr : &it->second;
}

std::wstring Wide(const std::string& value) {
  if (value.empty()) return {};
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                         value.data(), static_cast<int>(value.size()),
                                         nullptr, 0);
  if (length <= 0) return {};
  std::wstring result(length, L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                          static_cast<int>(value.size()), result.data(), length) <= 0) {
    return {};
  }
  return result;
}
}  // namespace

ReadAloudSpeech::ReadAloudSpeech(flutter::BinaryMessenger* messenger, HWND window) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "belog/read_aloud", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
  Initialize(window);
}

void ReadAloudSpeech::Initialize(HWND window) {
  if (FAILED(CoCreateInstance(CLSID_SpVoice, nullptr, CLSCTX_ALL,
                              IID_PPV_ARGS(&voice_)))) {
    return;
  }
  const ULONGLONG interest = SPFEI(SPEI_START_INPUT_STREAM) |
                             SPFEI(SPEI_WORD_BOUNDARY) |
                             SPFEI(SPEI_END_INPUT_STREAM);
  if (FAILED(voice_->SetNotifyWindowMessage(window, kSpeechMessage, 0, 0)) ||
      FAILED(voice_->SetInterest(interest, interest))) {
    voice_.Reset();
    return;
  }
  voice_->GetVoice(&default_voice_);
  ComPtr<IEnumSpObjectTokens> enumerator;
  if (FAILED(SpEnumTokens(SPCAT_VOICES, nullptr, nullptr, &enumerator))) return;
  ComPtr<ISpObjectToken> token;
  while (enumerator->Next(1, &token, nullptr) == S_OK) {
    WCHAR* id = nullptr;
    WCHAR* language = nullptr;
    ComPtr<ISpDataKey> attributes;
    if (SUCCEEDED(token->GetId(&id)) &&
        SUCCEEDED(token->OpenKey(L"Attributes", &attributes)) &&
        SUCCEEDED(attributes->GetStringValue(L"Language", &language))) {
      // SAPI's Language attribute is a hexadecimal Windows LCID, sometimes
      // followed by additional semicolon-separated alternatives.
      wchar_t locale[LOCALE_NAME_MAX_LENGTH] = {};
      const LCID lcid = static_cast<LCID>(std::wcstoul(language, nullptr, 16));
      if (LCIDToLocaleName(lcid, locale, LOCALE_NAME_MAX_LENGTH, 0) > 0) {
        voices_.push_back({Utf8FromUtf16(id), Utf8FromUtf16(locale), token});
      }
    }
    CoTaskMemFree(id);
    CoTaskMemFree(language);
    token.Reset();
  }
}

ReadAloudSpeech::~ReadAloudSpeech() {
  Stop();
  channel_->SetMethodCallHandler(nullptr);
  voice_.Reset();
}

void ReadAloudSpeech::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (call.method_name() == "initialize") {
    EncodableList voices;
    for (const auto& voice : voices_) {
      voices.emplace_back(EncodableMap{{EncodableValue("id"), EncodableValue(voice.id)},
                                      {EncodableValue("language"), EncodableValue(voice.language)}});
    }
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("available"), EncodableValue(voice_ != nullptr)},
        {EncodableValue("voices"), EncodableValue(voices)}}));
  } else if (call.method_name() == "stop") {
    Stop();
    result->Success();
  } else if (call.method_name() == "speak") {
    const auto* args = call.arguments() ? std::get_if<EncodableMap>(call.arguments()) : nullptr;
    if (!voice_ || !args) {
      result->Success(EncodableValue(false));
      return;
    }
    const auto* id_value = Field(*args, "id");
    const auto* text_value = Field(*args, "text");
    const auto* rate_value = Field(*args, "rate");
    const auto* voice_value = Field(*args, "voice");
    const auto* id = id_value ? std::get_if<std::string>(id_value) : nullptr;
    const auto* text = text_value ? std::get_if<std::string>(text_value) : nullptr;
    const auto* rate = rate_value ? std::get_if<double>(rate_value) : nullptr;
    const auto* name = voice_value ? std::get_if<std::string>(voice_value) : nullptr;
    if (!id || !text || text->empty() || !rate || !std::isfinite(*rate)) {
      result->Success(EncodableValue(false));
      return;
    }
    auto selected = std::find_if(voices_.begin(), voices_.end(),
                                 [name](const Voice& item) { return name && item.id == *name; });
    if (selected != voices_.end()) voice_->SetVoice(selected->token.Get());
    else if (default_voice_) voice_->SetVoice(default_voice_.Get());
    const double normalized = std::clamp(*rate, 0.5, 2.0);
    voice_->SetRate(static_cast<long>(std::round(std::log2(normalized) * 6)));
    const auto wide = Wide(*text);
    if (wide.empty()) {
      result->Success(EncodableValue(false));
      return;
    }
    ULONG stream = 0;
    // SPF_IS_NOT_XML is important: user article text is never SAPI markup.
    HRESULT hr = voice_->Speak(wide.c_str(), SPF_ASYNC | SPF_IS_NOT_XML, &stream);
    if (SUCCEEDED(hr)) utterances_[stream] = *id;
    result->Success(EncodableValue(SUCCEEDED(hr)));
  } else {
    result->NotImplemented();
  }
}

void ReadAloudSpeech::Stop() {
  utterances_.clear();
  if (voice_) voice_->Speak(nullptr, SPF_ASYNC | SPF_PURGEBEFORESPEAK, nullptr);
}

void ReadAloudSpeech::HandleSpeechEvents() {
  if (!voice_) return;
  SPEVENT event = {};
  ULONG fetched = 0;
  while (voice_->GetEvents(1, &event, &fetched) == S_OK && fetched == 1) {
    auto it = utterances_.find(event.ulStreamNum);
    if (it != utterances_.end()) {
      switch (event.eEventId) {
        case SPEI_START_INPUT_STREAM:
          Emit(it->second, "started");
          break;
        case SPEI_WORD_BOUNDARY: {
          const int start = static_cast<int>(event.lParam);
          const int end = start + static_cast<int>(event.wParam);
          Emit(it->second, "range", start, end);
          break;
        }
        case SPEI_END_INPUT_STREAM:
          Emit(it->second, "completed");
          utterances_.erase(it);
          break;
      }
    }
    SpClearEvent(&event);
    event = {};
  }
}

void ReadAloudSpeech::Emit(const std::string& id, const char* type, int start, int end) {
  auto data = std::make_unique<EncodableValue>(EncodableMap{
      {EncodableValue("id"), EncodableValue(id)},
      {EncodableValue("type"), EncodableValue(type)},
      {EncodableValue("start"), EncodableValue(start)},
      {EncodableValue("end"), EncodableValue(end)}});
  channel_->InvokeMethod("event", std::move(data));
}
