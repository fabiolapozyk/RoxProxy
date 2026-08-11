import 'captured_exchange.dart';

/// User decision for a suspended request (UI → core), RF3.2.
enum BreakpointAction { proceed, cancel }

class BreakpointResponse {
  final String breakpointId;
  final BreakpointAction action;
  final String? modifiedMethod;
  final String? modifiedUrl;
  final List<HttpHeader>? modifiedHeaders;
  final String? modifiedBody;
  final DateTime timestamp;

  const BreakpointResponse({
    required this.breakpointId,
    required this.action,
    this.modifiedMethod,
    this.modifiedUrl,
    this.modifiedHeaders,
    this.modifiedBody,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
    'breakpointId': breakpointId,
    'action': action.name,
    'modifiedMethod': modifiedMethod,
    'modifiedUrl': modifiedUrl,
    'modifiedHeaders': modifiedHeaders
        ?.map((h) => {'name': h.name, 'value': h.value})
        .toList(),
    'modifiedBody': modifiedBody,
    'timestamp': timestamp.toIso8601String(),
  };
}
