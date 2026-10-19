import 'package:flutter/services.dart';

/// Bridge for commands originating from the native macOS menu bar.
///
/// The Swift side builds a "File" menu at startup (see `MainFlutterWindow`)
/// and invokes [channel] with [actionMethod] whenever an item is selected.
class MenuChannel {
  MenuChannel._();

  static const MethodChannel channel = MethodChannel('com.roxproxy/menu');

  /// Method name used by the native side to forward a menu command.
  static const String actionMethod = 'menuAction';

  /// Registers [handler] for native menu actions, replacing any previous one.
  static void setHandler(Future<void> Function(String action) handler) {
    channel.setMethodCallHandler((call) async {
      if (call.method == actionMethod && call.arguments is String) {
        await handler(call.arguments as String);
      }
    });
  }

  /// Removes the current handler (called when the main window is disposed).
  static void clearHandler() {
    channel.setMethodCallHandler(null);
  }
}
