import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TailscaleBridge {
  static const channel = MethodChannel('mimo/tailscale');
  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static Future<bool> installed() async =>
      isAndroid && (await channel.invokeMethod<bool>('isInstalled') ?? false);
  static Future<void> open() async {
    await channel.invokeMethod<void>('openTailscale');
  }

  static Future<void> installPage() async {
    await channel.invokeMethod<void>('installPage');
  }
}
