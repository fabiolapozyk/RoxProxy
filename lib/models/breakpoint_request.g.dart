// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'breakpoint_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BreakpointRequest _$BreakpointRequestFromJson(Map<String, dynamic> json) =>
    BreakpointRequest(
      id: json['id'] as String,
      exchangeId: json['exchangeId'] as String,
      type: json['type'] as String,
      method: json['method'] as String,
      url: json['url'] as String,
      headers: Map<String, String>.from(json['headers'] as Map),
      body: json['body'] as String?,
      isRequest: json['isRequest'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$BreakpointRequestToJson(BreakpointRequest instance) =>
    <String, dynamic>{
      'id': instance.id,
      'exchangeId': instance.exchangeId,
      'type': instance.type,
      'method': instance.method,
      'url': instance.url,
      'headers': instance.headers,
      'body': instance.body,
      'isRequest': instance.isRequest,
      'timestamp': instance.timestamp.toIso8601String(),
    };
