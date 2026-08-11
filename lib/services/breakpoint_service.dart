import 'dart:async';

import 'package:flutter/services.dart';

import '../models/breakpoint_request.dart';
import '../models/breakpoint_response.dart';

/// Client dei canali per i breakpoint (RF6):
/// - notifiche in arrivo su EventChannel `com.roxproxy/breakpointEvents`
/// - decisioni inviate sul MethodChannel esistente `com.roxproxy/control`
///   (metodo `breakpointDecision`).
///
/// Nessuna connessione da gestire: il bridge è in-process (RNF4).
class BreakpointService {
  static const _events = EventChannel('com.roxproxy/breakpointEvents');
  static const _control = MethodChannel('com.roxproxy/control');

  Stream<BreakpointRequest>? _stream;

  Stream<BreakpointRequest> get breakpointStream {
    _stream ??= _events.receiveBroadcastStream().map((raw) {
      final map = Map<Object?, Object?>.from(raw as Map);
      final request = Map<Object?, Object?>.from(map['request'] as Map);
      return BreakpointRequest.fromMap(request);
    });
    return _stream!;
  }

  Future<void> sendDecision(BreakpointResponse response) async {
    await _control.invokeMethod('breakpointDecision', response.toMap());
  }
}
