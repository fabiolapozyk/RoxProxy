import 'dart:async';

import 'package:flutter/services.dart';

import '../models/captured_exchange.dart';
import '../models/domain_rule.dart';
import '../models/map_local_rule.dart';

class ExchangeEvent {
  final String type; // 'new' or 'update'
  final CapturedExchange exchange;
  ExchangeEvent(this.type, this.exchange);
}

class CaStatus {
  final bool initialized;
  final bool trusted;
  CaStatus({required this.initialized, required this.trusted});
}

class ProxyChannel {
  static const _method = MethodChannel('com.roxproxy/control');
  static const _events = EventChannel('com.roxproxy/exchanges');

  Stream<ExchangeEvent>? _exchangeStream;

  Stream<ExchangeEvent> get exchangeStream {
    _exchangeStream ??= _events.receiveBroadcastStream().map((raw) {
      final map = Map<Object?, Object?>.from(raw as Map);
      final type = map['type'] as String;
      final exchangeRaw = Map<Object?, Object?>.from(map['exchange'] as Map);
      return ExchangeEvent(type, CapturedExchange.fromMap(exchangeRaw));
    });
    return _exchangeStream!;
  }

  // MARK: - Proxy control

  Future<int> startProxy({
    required int port,
    required List<DomainRule> domainRules,
    required int connectionTimeoutSeconds,
    required bool setSystemProxy,
    required bool httpsInterceptionEnabled,
    List<MapLocalRule> mapLocalRules = const [],
    bool breakpointEnabled = false,
  }) async {
    final result = await _method.invokeMethod<Map>('startProxy', {
      'port': port,
      'domainRules': domainRules.map((r) => r.toMap()).toList(),
      'mapLocalRules': mapLocalRules.map((r) => r.toMap()).toList(),
      'connectionTimeoutSeconds': connectionTimeoutSeconds,
      'setSystemProxy': setSystemProxy,
      'httpsInterceptionEnabled': httpsInterceptionEnabled,
      'breakpointEnabled': breakpointEnabled,
    });
    return (result?['port'] as int?) ?? port;
  }

  Future<void> stopProxy() async {
    await _method.invokeMethod('stopProxy');
  }

  Future<void> configureSystemProxy({
    required bool enabled,
    required int port,
  }) async {
    await _method.invokeMethod('configureSystemProxy', {
      'enabled': enabled,
      'port': port,
    });
  }

  Future<String> getProxyState() async {
    final result = await _method.invokeMethod<Map>('getProxyState');
    return result?['state'] as String? ?? 'stopped';
  }

  // MARK: - Certificate

  Future<bool> installCACertificate() async {
    final result = await _method.invokeMethod<Map>('installCACertificate');
    return result?['trusted'] as bool? ?? false;
  }

  Future<bool> checkCATrust() async {
    final result = await _method.invokeMethod<Map>('checkCATrust');
    return result?['trusted'] as bool? ?? false;
  }

  Future<CaStatus> getCAStatus() async {
    final result = await _method.invokeMethod<Map>('getCAStatus');
    return CaStatus(
      initialized: result?['initialized'] as bool? ?? false,
      trusted: result?['trusted'] as bool? ?? false,
    );
  }

  // MARK: - Body management

  Future<Uint8List?> fetchBody(String ref) async {
    final result = await _method.invokeMethod<Uint8List>('fetchBody', {
      'ref': ref,
    });
    return result;
  }

  Future<void> releaseBody(String ref) async {
    await _method.invokeMethod('releaseBody', {'ref': ref});
  }

  Future<void> releaseAllBodies() async {
    await _method.invokeMethod('releaseAllBodies');
  }

  // MARK: - Decompression

  Future<Uint8List?> decompressBody(Uint8List data, String encoding) async {
    return _method.invokeMethod<Uint8List>('decompressBody', {
      'data': data,
      'encoding': encoding,
    });
  }

  // MARK: - Replay

  Future<String> replayRequest(Map<String, dynamic> request) async {
    final result = await _method.invokeMethod<Map>('replayRequest', request);
    return result?['exchangeId'] as String? ?? '';
  }
}
