import 'package:json_annotation/json_annotation.dart';

part 'breakpoint_request.g.dart';

@JsonSerializable()
class BreakpointRequest {
  final String id;
  final String exchangeId;
  final String type; // 'request' or 'response'
  final String method;
  final String url;
  final Map<String, String> headers;
  final String? body;
  final bool isRequest;
  final DateTime timestamp;

  BreakpointRequest({
    required this.id,
    required this.exchangeId,
    required this.type,
    required this.method,
    required this.url,
    required this.headers,
    this.body,
    required this.isRequest,
    required this.timestamp,
  });

  factory BreakpointRequest.fromJson(Map<String, dynamic> json) => 
      _$BreakpointRequestFromJson(json);

  Map<String, dynamic> toJson() => _$BreakpointRequestToJson(this);
}