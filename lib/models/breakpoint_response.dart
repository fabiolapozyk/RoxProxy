import 'package:json_annotation/json_annotation.dart';

part 'breakpoint_response.g.dart';

@JsonSerializable()
class BreakpointResponse {
  final String breakpointId;
  final String action; // 'proceed' or 'cancel'
  final String? modifiedMethod;
  final String? modifiedUrl;
  final Map<String, String>? modifiedHeaders;
  final String? modifiedBody;
  final DateTime timestamp;

  BreakpointResponse({
    required this.breakpointId,
    required this.action,
    this.modifiedMethod,
    this.modifiedUrl,
    this.modifiedHeaders,
    this.modifiedBody,
    required this.timestamp,
  });

  factory BreakpointResponse.fromJson(Map<String, dynamic> json) => 
      _$BreakpointResponseFromJson(json);

  Map<String, dynamic> toJson() => _$BreakpointResponseToJson(this);
}