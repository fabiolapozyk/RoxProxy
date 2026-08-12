import 'dart:async';

import 'package:flutter/services.dart';

import '../models/breakpoint_notification.dart';
import '../models/breakpoint_request.dart';
import '../models/breakpoint_response.dart';
import '../models/response_breakpoint.dart';

/// Client dei canali per i breakpoint (RF6):
/// - notifiche in arrivo su EventChannel `com.roxproxy/breakpointEvents`
///   (richieste e risposte sospese)
/// - decisioni inviate sul MethodChannel esistente `com.roxproxy/control`
///   (metodo `breakpointDecision`).
///
/// Nessuna connessione da gestire: il bridge è in-process (RNF4).
class BreakpointService {
  static const _events = EventChannel('com.roxproxy/breakpointEvents');
  static const _control = MethodChannel('com.roxproxy/control');

  Stream<BreakpointNotification>? _stream;

  Stream<BreakpointNotification> get breakpointStream {
    _stream ??= _events.receiveBroadcastStream().map((raw) {
      final map = Map<Object?, Object?>.from(raw as Map);
      final type = map['type'] as String;
      if (type == 'response') {
        return ResponseBreakpointNotification(
          ResponseBreakpoint.fromMap(
            Map<Object?, Object?>.from(map['response'] as Map),
          ),
        );
      }
      return RequestBreakpointNotification(
        BreakpointRequest.fromMap(
          Map<Object?, Object?>.from(map['request'] as Map),
        ),
      );
    });
    return _stream!;
  }

  Future<void> sendDecision(BreakpointResponse response) async {
    await _control.invokeMethod('breakpointDecision', response.toMap());
  }
}
