import 'breakpoint_request.dart';
import 'response_breakpoint.dart';

/// Notifica unificata dal canale breakpoint: richiesta o risposta sospesa.
sealed class BreakpointNotification {
  const BreakpointNotification();

  /// Id del breakpoint (correla notifica e decisione).
  String get id;

  /// Host estratto dal payload, per i titoli dei dialog.
  String get host;
}

class RequestBreakpointNotification extends BreakpointNotification {
  final BreakpointRequest request;
  const RequestBreakpointNotification(this.request);

  @override
  String get id => request.id;

  @override
  String get host => request.host;
}

class ResponseBreakpointNotification extends BreakpointNotification {
  final ResponseBreakpoint response;
  const ResponseBreakpointNotification(this.response);

  @override
  String get id => response.id;

  @override
  String get host => response.host;
}
