import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SecureWindowService {
  static const _channel = MethodChannel('asiimov/secure_window');

  static Future<void> enable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod('enable');
  }

  static Future<void> disable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod('disable');
  }
}
