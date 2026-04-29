#include "biometric_channel.h"

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Security.Credentials.UI.h>

#include <memory>
#include <string>
#include <thread>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;
using flutter::MethodChannel;
using flutter::StandardMethodCodec;

constexpr const char* kChannelName = "cipher_nest/biometric";

std::wstring Utf8ToUtf16(const std::string& s) {
  if (s.empty()) return L"";
  int len = ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(),
                                  static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(len, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()),
                        out.data(), len);
  return out;
}

// Block synchronously while pumping messages so the system Windows Hello UI
// stays responsive while we wait. This runs on a worker thread so the main
// platform thread stays unblocked.
template <typename T>
T WaitForAsync(winrt::Windows::Foundation::IAsyncOperation<T> op) {
  using winrt::Windows::Foundation::AsyncStatus;
  while (op.Status() == AsyncStatus::Started) {
    ::Sleep(20);
  }
  return op.GetResults();
}

void HandleIsAvailable(std::unique_ptr<MethodResult<EncodableValue>> result) {
  std::thread([res = std::shared_ptr<MethodResult<EncodableValue>>(
                   std::move(result))]() {
    try {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
      auto status = WaitForAsync(
          winrt::Windows::Security::Credentials::UI::UserConsentVerifier::
              CheckAvailabilityAsync());
      const bool available =
          status == winrt::Windows::Security::Credentials::UI::
                        UserConsentVerifierAvailability::Available;
      res->Success(EncodableValue(available));
    } catch (...) {
      res->Success(EncodableValue(false));
    }
  }).detach();
}

void HandleAuthenticate(const MethodCall<EncodableValue>& call,
                        std::unique_ptr<MethodResult<EncodableValue>> result) {
  std::wstring reason = L"Unlock Cipher Nest";
  const auto* args = std::get_if<EncodableMap>(call.arguments());
  if (args) {
    auto it = args->find(EncodableValue("reason"));
    if (it != args->end()) {
      const auto* s = std::get_if<std::string>(&it->second);
      if (s) reason = Utf8ToUtf16(*s);
    }
  }

  std::thread([reason = std::move(reason),
               res = std::shared_ptr<MethodResult<EncodableValue>>(
                   std::move(result))]() {
    try {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);

      auto availability = WaitForAsync(
          winrt::Windows::Security::Credentials::UI::UserConsentVerifier::
              CheckAvailabilityAsync());
      if (availability !=
          winrt::Windows::Security::Credentials::UI::
              UserConsentVerifierAvailability::Available) {
        res->Success(EncodableValue(false));
        return;
      }

      auto verResult = WaitForAsync(
          winrt::Windows::Security::Credentials::UI::UserConsentVerifier::
              RequestVerificationAsync(reason));
      const bool ok =
          verResult == winrt::Windows::Security::Credentials::UI::
                           UserConsentVerificationResult::Verified;
      res->Success(EncodableValue(ok));
    } catch (...) {
      res->Success(EncodableValue(false));
    }
  }).detach();
}

}  // namespace

void BiometricChannel::Register(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<MethodChannel<EncodableValue>>(
      messenger, kChannelName, &StandardMethodCodec::GetInstance());
  auto* raw = channel.release();  // Channel must outlive the lambda.

  raw->SetMethodCallHandler(
      [](const MethodCall<EncodableValue>& call,
         std::unique_ptr<MethodResult<EncodableValue>> result) {
        const auto& method = call.method_name();
        if (method == "isAvailable") {
          HandleIsAvailable(std::move(result));
        } else if (method == "authenticate") {
          HandleAuthenticate(call, std::move(result));
        } else {
          result->NotImplemented();
        }
      });
}
