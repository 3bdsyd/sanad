import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// App-owned iOS features. Other platforms can keep their Flutter equivalents.
abstract final class NativeBridge {
  static const _channel = MethodChannel('app.fursa/native');
  static final _symbols = <String, Future<Uint8List?>>{};

  static bool get available =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Returns a transparent Retina PNG of an SF Symbol, or null if unavailable.
  static Future<Uint8List?> symbol(
    String name, {
    double size = 24,
    Color? color,
  }) {
    if (!available) return SynchronousFuture(null);
    final argb = (color ?? const Color(0xFF20508A)).toARGB32();
    final key = '$name/$size/$argb';
    return _symbols.putIfAbsent(key, () async {
      try {
        return await _channel.invokeMethod<Uint8List>('symbol', {
          'name': name,
          'size': size,
          'color': argb,
        });
      } on MissingPluginException {
        return null;
      } on PlatformException {
        return null;
      }
    });
  }

  static Future<void> selectionHaptic() async {
    try {
      if (available) {
        await _channel.invokeMethod<void>('selectionHaptic');
      } else {
        await HapticFeedback.selectionClick();
      }
    } on MissingPluginException {
      // A preview or unsupported host can omit native features.
    } on PlatformException {
      // Haptics are optional, including on devices without a Taptic Engine.
    }
  }
}
