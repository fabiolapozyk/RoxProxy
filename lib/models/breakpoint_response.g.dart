// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'breakpoint_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BreakpointResponse _$BreakpointResponseFromJson(Map<String, dynamic> json) =>
    BreakpointResponse(
      breakpointId: json['breakpointId'] as String,
      action: json['action'] as String,
      modifiedMethod: json['modifiedMethod'] as String?,
      modifiedUrl: json['modifiedUrl'] as String?,
      modifiedHeaders: (json['modifiedHeaders'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ),
      modifiedBody: json['modifiedBody'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$BreakpointResponseToJson(BreakpointResponse instance) =>
    <String, dynamic>{
      'breakpointId': instance.breakpointId,
      'action': instance.action,
      'modifiedMethod': instance.modifiedMethod,
      'modifiedUrl': instance.modifiedUrl,
      'modifiedHeaders': instance.modifiedHeaders,
      'modifiedBody': instance.modifiedBody,
      'timestamp': instance.timestamp.toIso8601String(),
    };
