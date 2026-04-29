#ifndef RUNNER_BIOMETRIC_CHANNEL_H_
#define RUNNER_BIOMETRIC_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

// Registers a method channel named "cipher_nest/biometric" that exposes
// Windows Hello biometric / PIN authentication to the Flutter side.
//
//   isAvailable() -> bool
//   authenticate({reason: String}) -> bool
//
// Implemented natively in this app's runner so we don't need a third-party
// Flutter plugin (which would require Windows Developer Mode for symlinks).
class BiometricChannel {
 public:
  static void Register(flutter::BinaryMessenger* messenger);
};

#endif  // RUNNER_BIOMETRIC_CHANNEL_H_
