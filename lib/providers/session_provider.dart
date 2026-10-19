import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/captured_exchange.dart';
import '../services/har_importer.dart';
import 'exchange_provider.dart';
import 'proxy_channel_provider.dart';

/// A capture opened from a HAR file on its own read-only screen.
///
/// The live exchange list is never replaced: the proxy keeps running and the
/// live capture keeps accumulating in the background (issue #13).
class OfflineSessionState {
  final String path;
  final String fileName;
  final List<CapturedExchange> exchanges;

  /// Native BodyStore references created for the imported bodies, released one
  /// by one when the session is closed (live bodies must survive).
  final List<String> bodyRefs;
  final String filterText;
  final String? selectedId;

  const OfflineSessionState({
    required this.path,
    required this.fileName,
    required this.exchanges,
    required this.bodyRefs,
    this.filterText = '',
    this.selectedId,
  });

  List<CapturedExchange> get filtered => [
    for (final exchange in exchanges)
      if (matchesExchangeFilter(exchange, filterText)) exchange,
  ];

  CapturedExchange? get selected {
    final id = selectedId;
    if (id == null) return null;
    for (final exchange in exchanges) {
      if (exchange.id == id) return exchange;
    }
    return null;
  }

  OfflineSessionState withFilter(String text) => OfflineSessionState(
    path: path,
    fileName: fileName,
    exchanges: exchanges,
    bodyRefs: bodyRefs,
    filterText: text,
    selectedId: selectedId,
  );

  OfflineSessionState withSelection(String? id) => OfflineSessionState(
    path: path,
    fileName: fileName,
    exchanges: exchanges,
    bodyRefs: bodyRefs,
    filterText: filterText,
    selectedId: id,
  );
}

final harImporterProvider = Provider<HarImporter>((ref) => const HarImporter());

/// Non-null while the offline session screen is shown.
final offlineSessionProvider =
    StateNotifierProvider<OfflineSessionNotifier, OfflineSessionState?>(
      (ref) => OfflineSessionNotifier(ref),
    );

class OfflineSessionNotifier extends StateNotifier<OfflineSessionState?> {
  OfflineSessionNotifier(this._ref) : super(null);

  final Ref _ref;

  /// Loads [path] (HAR 1.2) and switches to the offline screen; returns how many
  /// exchanges were imported. The proxy is left untouched: live traffic keeps
  /// flowing and stays available when the session is closed.
  Future<int> open(String path) async {
    final contents = await _read(path);
    final imported = _ref.read(harImporterProvider).parse(contents);

    // Replace a previously opened session (releasing only its own bodies).
    await close();

    final channel = _ref.read(proxyChannelProvider);
    final refs = <String>[];
    try {
      for (final item in imported) {
        final requestBody = item.requestBody;
        if (requestBody != null) {
          final ref = await channel.storeBody(requestBody);
          item.exchange.requestBodyRef = ref;
          if (ref != null) refs.add(ref);
        }
        final responseBody = item.responseBody;
        if (responseBody != null) {
          final ref = await channel.storeBody(responseBody);
          item.exchange.responseBodyRef = ref;
          if (ref != null) refs.add(ref);
        }
      }
    } catch (_) {
      // No half-imported state: release what was stored and stay live.
      for (final ref in refs) {
        try {
          await channel.releaseBody(ref);
        } catch (_) {}
      }
      rethrow;
    }

    state = OfflineSessionState(
      path: path,
      fileName: fileNameOf(path),
      exchanges: [for (final item in imported) item.exchange],
      bodyRefs: refs,
    );
    return imported.length;
  }

  /// Closes the offline screen and releases the imported bodies.
  ///
  /// Only the session's own references are released: the live capture and its
  /// bodies are untouched.
  Future<void> close() async {
    final current = state;
    if (current == null) return;
    state = null;

    if (current.bodyRefs.isEmpty) return;
    final channel = _ref.read(proxyChannelProvider);
    for (final ref in current.bodyRefs) {
      try {
        await channel.releaseBody(ref);
      } catch (_) {}
    }
  }

  void setFilter(String text) {
    final current = state;
    if (current == null) return;
    state = current.withFilter(text);
  }

  void select(String? id) {
    final current = state;
    if (current == null) return;
    state = current.withSelection(id);
  }

  static String fileNameOf(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty || parts.last.isEmpty ? path : parts.last;
  }

  static Future<String> _read(String path) async {
    try {
      return await File(path).readAsString();
    } on FileSystemException catch (e) {
      throw HarFormatException('Cannot read file: ${e.message}');
    }
  }
}
