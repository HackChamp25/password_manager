import 'dart:async';

import 'package:flutter/services.dart';

class SecureClipboard {
  SecureClipboard._();

  static Timer? _clearTimer;

  static Future<void> copyAndScheduleClear(
    String text, {
    Duration clearAfter = const Duration(seconds: 45),
  }) async {
    await Clipboard.setData(ClipboardData(text: text));
    _clearTimer?.cancel();
    _clearTimer = Timer(clearAfter, () async {
      final current = await Clipboard.getData('text/plain');
      if (current?.text == text) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    });
  }
}
