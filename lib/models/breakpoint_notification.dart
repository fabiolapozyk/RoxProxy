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

/// The native side released a suspended breakpoint without a user decision
/// (feature disabled or proxy stopped). The UI must close the matching dialog.
class BreakpointResolvedNotification extends BreakpointNotification {
  final String breakpointId;
  const BreakpointResolvedNotification(this.breakpointId);

  @override
  String get id => breakpointId;

  @override
  String get host => '';
}
