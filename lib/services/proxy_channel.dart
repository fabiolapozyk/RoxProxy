import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../models/breakpoint.dart';
import '../models/captured_exchange.dart';
import '../models/domain_rule.dart';

class ExchangeEvent {
  final String type; // 'new' or 'update'
  final CapturedExchange exchange;
  ExchangeEvent(this.type, this.exchange);
}

class BreakpointEvent {
  final String exchangeId;
  final String url;
  final bool isRequest;
  final Map<String, dynamic> exchangeData;

  BreakpointEvent({
    required this.exchangeId,
    required this.url,
    required this.isRequest,
    required this.exchangeData,
  });

  factory BreakpointEvent.fromMap(Map<Object?, Object?> map) {
    final data = Map<String, dynamic>.from(map);
    return BreakpointEvent(
      exchangeId: data['exchangeId'] as String,
      url: data['url'] as String,
      isRequest: data['isRequest'] as bool,
      exchangeData: Map<String, dynamic>.from(data['exchangeData'] as Map),
    );
  }

  Map<String, dynamic> toMap() => {
    'exchangeId': exchangeId,
    'url': url,
    'isRequest': isRequest,
    'exchangeData': exchangeData,
  };
}

class CaStatus {
  final bool initialized;
  final bool trusted;
  CaStatus({required this.initialized, required this.trusted});
}

class ProxyChannel {
  static const _method = MethodChannel('com.roxproxy/control');
  static const _events = EventChannel('com.roxproxy/exchanges');
  static const _breakpointEvents = EventChannel('com.roxproxy/breakpoints');

  Stream<ExchangeEvent>? _exchangeStream;
  Stream<BreakpointEvent>? _breakpointStream;

  Stream<ExchangeEvent> get exchangeStream {
    _exchangeStream ??= _events
        .receiveBroadcastStream()
        .map((raw) {
          final map = Map<Object?, Object?>.from(raw as Map);
          final type = map['type'] as String;
          final exchangeRaw = Map<Object?, Object?>.from(map['exchange'] as Map);
          return ExchangeEvent(type, CapturedExchange.fromMap(exchangeRaw));
        });
    return _exchangeStream!;
  }

  Stream<BreakpointEvent> get breakpointStream {
    print('DEBUG: ProxyChannel.breakpointStream called - setting up stream');
    _breakpointStream ??= _breakpointEvents
        .receiveBroadcastStream()
        .map((raw) {
          print('DEBUG: ProxyChannel received raw breakpoint event: $raw');
          final map = Map<Object?, Object?>.from(raw as Map);
          final event = BreakpointEvent.fromMap(map);
          print('DEBUG: ProxyChannel converted to BreakpointEvent: ${event.url}');
          return event;
        });
    return _breakpointStream!;
  }

  // MARK: - Proxy control

  Future<int> startProxy({
    required int port,
    required List<DomainRule> domainRules,
    required List<Breakpoint> breakpoints,
    required int connectionTimeoutSeconds,
    required bool setSystemProxy,
    required bool httpsInterceptionEnabled,
  }) async {
    final result = await _method.invokeMethod<Map>('startProxy', {
      'port': port,
      'domainRules': domainRules.map((r) => r.toMap()).toList(),
      'breakpoints': breakpoints.map((b) => b.toMap()).toList(),
      'connectionTimeoutSeconds': connectionTimeoutSeconds,
      'setSystemProxy': setSystemProxy,
      'httpsInterceptionEnabled': httpsInterceptionEnabled,
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
    final result = await _method.invokeMethod<Uint8List>('fetchBody', {'ref': ref});
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

  // MARK: - Breakpoint

  Future<Map<String, dynamic>?> waitForBreakpointResolution(String exchangeId) async {
    final result = await _method.invokeMethod('waitForBreakpointResolution', {
      'exchangeId': exchangeId,
    });
    return result as Map<String, dynamic>?;
  }

  Future<void> resolveBreakpoint({
    required String exchangeId,
    required bool shouldContinue,
    Map<String, dynamic>? modifications,
  }) async {
    await _method.invokeMethod('resolveBreakpoint', {
      'exchangeId': exchangeId,
      'shouldContinue': shouldContinue,
      'modifications': modifications ?? {},
    });
  }
}
