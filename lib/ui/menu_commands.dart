import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/captured_exchange.dart';
import '../providers/exchange_provider.dart';
import '../providers/har_export_provider.dart';
import '../providers/session_provider.dart';
import '../services/har_importer.dart';
import 'export_har_dialog.dart';

/// Actions triggered from the native macOS "File" menu.
class MenuCommands {
  MenuCommands._();

  /// Opens a HAR capture on the read-only offline screen.
  ///
  /// The proxy keeps running and the live capture is never replaced, so the
  /// network keeps working while the file is inspected.
  static Future<void> openCapture(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open Capture',
      allowMultiple: false,
      type: FileType.any,
    );
    final path = result?.files.single.path;
    if (path == null) return;

    try {
      final count = await ref.read(offlineSessionProvider.notifier).open(path);
      _snack(messenger, errorColor, 'Opened $count requests (offline)');
    } on HarFormatException catch (e) {
      _snack(messenger, errorColor, 'Open failed: ${e.message}', error: true);
    } catch (e) {
      _snack(messenger, errorColor, 'Open failed: $e', error: true);
    }
  }

  /// Exports the active capture to HAR 1.2, letting the user pick between all
  /// requests and the filtered subset (issue #10).
  ///
  /// When the offline screen is open, it exports that session; otherwise it
  /// exports the live capture.
  static Future<void> exportHar(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    final offline = ref.read(offlineSessionProvider);
    final List<CapturedExchange> all =
        offline?.exchanges ?? ref.read(exchangeListProvider);
    final List<CapturedExchange> filtered =
        offline?.filtered ?? ref.read(filteredExchangesProvider);
    final String activeFilter =
        offline?.filterText ?? ref.read(filterTextProvider);

    if (all.isEmpty) {
      _snack(messenger, errorColor, 'Nothing to export', error: true);
      return;
    }

    final scope = await showHarExportDialog(
      context,
      total: all.length,
      filtered: filtered.length,
      filterActive: activeFilter.trim().isNotEmpty,
    );
    if (scope == null) return;

    final picked = await FilePicker.platform.saveFile(
      dialogTitle: 'Export HAR',
      fileName: 'roxproxy_${_timestamp()}.har',
      type: FileType.any,
    );
    if (picked == null) return;
    final path = _withExtension(picked, '.har');

    final exchanges = harExportSelection(
      scope: scope,
      all: all,
      filtered: filtered,
    );
    try {
      final count = await ref
          .read(harExportControllerProvider)
          .export(path: path, exchanges: exchanges);
      _snack(messenger, errorColor, 'Exported $count requests to $path');
    } catch (e) {
      _snack(messenger, errorColor, 'Export failed: $e', error: true);
    }
  }

  static String _withExtension(String path, String extension) =>
      path.toLowerCase().endsWith(extension) ? path : '$path$extension';

  static String _timestamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  static void _snack(
    ScaffoldMessengerState messenger,
    Color errorColor,
    String message, {
    bool error = false,
  }) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13)),
        backgroundColor: error ? errorColor : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
