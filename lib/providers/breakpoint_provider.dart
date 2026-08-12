import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/breakpoint_notification.dart';
import '../models/breakpoint_response.dart';
import '../models/captured_exchange.dart';
import '../services/breakpoint_service.dart';

final breakpointServiceProvider = Provider<BreakpointService>((ref) {
  return BreakpointService();
});

/// Stato del provider: notifica attiva (dialog), coda, tempo residuo.
class BreakpointState {
  final BreakpointNotification? active;
  final List<BreakpointNotification> queue;
  final int remainingSeconds;

  const BreakpointState({
    this.active,
    this.queue = const [],
    this.remainingSeconds = 0,
  });

  bool get hasQueued => queue.isNotEmpty;
}

final breakpointProvider =
    StateNotifierProvider<BreakpointNotifier, BreakpointState>((ref) {
      return BreakpointNotifier(ref.read(breakpointServiceProvider));
    });

/// Gestisce lo stream delle notifiche (richieste e risposte), la coda dei
/// dialog (RF7.1) e il countdown del timeout (RF7.2). Il core applica comunque
/// il timeout lato Swift: il countdown qui è solo indicativo.
class BreakpointNotifier extends StateNotifier<BreakpointState> {
  static const timeoutSeconds = 30;

  final BreakpointService _service;
  StreamSubscription? _subscription;
  Timer? _timer;
  final List<BreakpointNotification> _queue = [];

  BreakpointNotifier(this._service) : super(const BreakpointState()) {
    _subscription = _service.breakpointStream.listen(_onNotification);
  }

  void _onNotification(BreakpointNotification notification) {
    if (state.active == null) {
      _activate(notification);
    } else {
      _queue.add(notification);
      state = state.copyWith(queue: List.of(_queue));
    }
  }

  void _activate(BreakpointNotification notification) {
    state = BreakpointState(
      active: notification,
      queue: List.of(_queue),
      remainingSeconds: timeoutSeconds,
    );
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = state.remainingSeconds - 1;
      if (remaining <= 0) {
        _timer?.cancel();
        _timer = null;
        _advance(); // il core ha già fatto auto-proceed (RF5)
      } else {
        state = state.copyWith(remainingSeconds: remaining);
      }
    });
  }

  void _advance() {
    _timer?.cancel();
    _timer = null;
    if (_queue.isNotEmpty) {
      _activate(_queue.removeAt(0));
    } else {
      state = const BreakpointState();
    }
  }

  /// Proceed per una richiesta sospesa con le modifiche scelte (RF4).
  Future<void> proceed({
    required String method,
    required String url,
    required List<HttpHeader> headers,
    String? body,
  }) async {
    final active = state.active;
    if (active is! RequestBreakpointNotification) return;
    final response = BreakpointResponse(
      breakpointId: active.id,
      action: BreakpointAction.proceed,
      modifiedMethod: method,
      modifiedUrl: url,
      modifiedHeaders: headers,
      modifiedBody: body,
      timestamp: DateTime.now(),
    );
    await _service.sendDecision(response);
    _advance();
  }

  /// Proceed per una risposta sospesa: inoltro così com'è.
  Future<void> proceedResponse() async {
    final active = state.active;
    if (active is! ResponseBreakpointNotification) return;
    await _service.sendDecision(
      BreakpointResponse(
        breakpointId: active.id,
        action: BreakpointAction.proceed,
        timestamp: DateTime.now(),
      ),
    );
    _advance();
  }

  /// Cancel: il core risponde 400 al client (richieste) o chiude la
  /// connessione (risposte).
  Future<void> cancel() async {
    final active = state.active;
    if (active == null) return;
    await _service.sendDecision(
      BreakpointResponse(
        breakpointId: active.id,
        action: BreakpointAction.cancel,
        timestamp: DateTime.now(),
      ),
    );
    _advance();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}

extension on BreakpointState {
  BreakpointState copyWith({
    BreakpointNotification? active,
    List<BreakpointNotification>? queue,
    int? remainingSeconds,
  }) => BreakpointState(
    active: active ?? this.active,
    queue: queue ?? this.queue,
    remainingSeconds: remainingSeconds ?? this.remainingSeconds,
  );
}
