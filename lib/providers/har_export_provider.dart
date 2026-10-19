import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/captured_exchange.dart';
import '../services/har_exporter.dart';
import 'proxy_channel_provider.dart';

/// Which part of the capture a HAR export should include (issue #10).
enum HarExportScope {
  /// Every exchange of the active capture, regardless of the filter.
  all,

  /// Only the exchanges currently matching the filter.
  filtered,
}

/// Picks the exchanges to export for [scope]. Pure helper so the all-vs-filtered
/// choice is unit-testable independently of the file dialogs.
List<CapturedExchange> harExportSelection({
  required HarExportScope scope,
  required List<CapturedExchange> all,
  required List<CapturedExchange> filtered,
}) => scope == HarExportScope.filtered ? filtered : all;

final harExporterProvider = Provider<HarExporter>((ref) => const HarExporter());

final harExportControllerProvider = Provider<HarExportController>(
  (ref) => HarExportController(ref),
);

/// Exports a list of exchanges (live or offline) to a HAR 1.2 file.
class HarExportController {
  HarExportController(this._ref);

  final Ref _ref;

  /// Builds and writes the HAR file for [exchanges]; returns the entry count.
  Future<int> export({
    required String path,
    required List<CapturedExchange> exchanges,
  }) async {
    final channel = _ref.read(proxyChannelProvider);

    final har = await _ref
        .read(harExporterProvider)
        .build(
          exchanges: exchanges,
          // Always read raw bytes from the native BodyStore: Dart's cache holds
          // display (already decompressed) bytes, which would be decompressed a
          // second time here and produce wrong content/metadata.
          readBody: (ref) => channel.fetchBody(ref),
          decompress: (data, encoding) async {
            final lower = encoding.toLowerCase();
            if (!lower.contains('gzip') &&
                !lower.contains('deflate') &&
                !lower.contains('br')) {
              return null;
            }
            return channel.decompressBody(data, encoding);
          },
          creatorVersion: await channel.getAppVersion() ?? '0.0.0',
        );

    final contents = const JsonEncoder.withIndent('  ').convert(har);
    await File(path).writeAsString(contents, flush: true);
    return exchanges.length;
  }
}
