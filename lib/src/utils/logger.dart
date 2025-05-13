import 'dart:developer' as develop;
import 'package:flutter/foundation.dart';

class Logger {
  static void d(Object? message) {
    if (kDebugMode) {
      develop.log('[DEBUG] $message', name: '🔍');
    }
  }

  static void e(String message) {
    if (kDebugMode) {
      develop.log('[ERROR] $message', name: '❌');
    }
  }
}
