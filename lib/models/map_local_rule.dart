import '../utils/uuid.dart';

/// A "Map Local" rule: intercept matching HTTP(S) requests and respond
/// with the contents of a local file instead of forwarding them upstream.
class MapLocalRule {
  final String id;
  String? name;
  String hostPattern;
  String pathPattern;
  String httpMethod;
  String filePath;
  int statusCode;
  String? contentType;
  Map<String, String> customHeaders;
  bool isEnabled;
  bool isCaseSensitive;
  bool useRegex;
  bool watchFile;
  int? cacheTTL;
  String? notes;
  final DateTime createdAt;
  DateTime updatedAt;

  MapLocalRule({
    String? id,
    this.name,
    this.hostPattern = '*',
    this.pathPattern = '**',
    this.httpMethod = 'ANY',
    this.filePath = '',
    this.statusCode = 200,
    this.contentType,
    Map<String, String>? customHeaders,
    this.isEnabled = true,
    this.isCaseSensitive = true,
    this.useRegex = false,
    this.watchFile = false,
    this.cacheTTL,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? UUID.v4(),
        customHeaders = customHeaders ?? {},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  String get displayName =>
      (name != null && name!.trim().isNotEmpty) ? name!.trim() : pathPattern;

  /// Payload sent to the native proxy at start time (runtime fields only).
  Map<String, dynamic> toMap() => {
        'id': id,
        'hostPattern': hostPattern,
        'pathPattern': pathPattern,
        'httpMethod': httpMethod,
        'filePath': filePath,
        'statusCode': statusCode,
        'contentType': contentType,
        'customHeaders': customHeaders,
        'isEnabled': isEnabled,
        'isCaseSensitive': isCaseSensitive,
        'useRegex': useRegex,
      };

  factory MapLocalRule.fromMap(Map<String, dynamic> map) => MapLocalRule(
        id: map['id'] as String,
        hostPattern: map['hostPattern'] as String? ?? '*',
        pathPattern: map['pathPattern'] as String? ?? '**',
        httpMethod: map['httpMethod'] as String? ?? 'ANY',
        filePath: map['filePath'] as String? ?? '',
        statusCode: map['statusCode'] as int? ?? 200,
        contentType: map['contentType'] as String?,
        customHeaders: (map['customHeaders'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ) ??
            {},
        isEnabled: map['isEnabled'] as bool? ?? true,
        isCaseSensitive: map['isCaseSensitive'] as bool? ?? true,
        useRegex: map['useRegex'] as bool? ?? false,
      );

  /// Full JSON representation for persistence / import / export.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hostPattern': hostPattern,
        'pathPattern': pathPattern,
        'httpMethod': httpMethod,
        'filePath': filePath,
        'statusCode': statusCode,
        'contentType': contentType,
        'customHeaders': customHeaders,
        'isEnabled': isEnabled,
        'isCaseSensitive': isCaseSensitive,
        'useRegex': useRegex,
        'watchFile': watchFile,
        'cacheTTL': cacheTTL,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory MapLocalRule.fromJson(Map<String, dynamic> json) => MapLocalRule(
        id: json['id'] as String,
        name: json['name'] as String?,
        hostPattern: json['hostPattern'] as String? ?? '*',
        pathPattern: json['pathPattern'] as String? ?? '**',
        httpMethod: json['httpMethod'] as String? ?? 'ANY',
        filePath: json['filePath'] as String? ?? '',
        statusCode: json['statusCode'] as int? ?? 200,
        contentType: json['contentType'] as String?,
        customHeaders: (json['customHeaders'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ) ??
            {},
        isEnabled: json['isEnabled'] as bool? ?? true,
        isCaseSensitive: json['isCaseSensitive'] as bool? ?? true,
        useRegex: json['useRegex'] as bool? ?? false,
        watchFile: json['watchFile'] as bool? ?? false,
        cacheTTL: json['cacheTTL'] as int?,
        notes: json['notes'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  MapLocalRule copyWith({
    String? name,
    String? hostPattern,
    String? pathPattern,
    String? httpMethod,
    String? filePath,
    int? statusCode,
    String? contentType,
    Map<String, String>? customHeaders,
    bool? isEnabled,
    bool? isCaseSensitive,
    bool? useRegex,
    bool? watchFile,
    int? cacheTTL,
    String? notes,
    DateTime? updatedAt,
  }) =>
      MapLocalRule(
        id: id,
        name: name ?? this.name,
        hostPattern: hostPattern ?? this.hostPattern,
        pathPattern: pathPattern ?? this.pathPattern,
        httpMethod: httpMethod ?? this.httpMethod,
        filePath: filePath ?? this.filePath,
        statusCode: statusCode ?? this.statusCode,
        contentType: contentType ?? this.contentType,
        customHeaders: customHeaders ?? Map.of(this.customHeaders),
        isEnabled: isEnabled ?? this.isEnabled,
        isCaseSensitive: isCaseSensitive ?? this.isCaseSensitive,
        useRegex: useRegex ?? this.useRegex,
        watchFile: watchFile ?? this.watchFile,
        cacheTTL: cacheTTL ?? this.cacheTTL,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  /// Returns a deep copy with a fresh id (used by the Duplicate action).
  MapLocalRule duplicate() => MapLocalRule(
        name: name == null ? '$displayName (copy)' : '${name!.trim()} (copy)',
        hostPattern: hostPattern,
        pathPattern: pathPattern,
        httpMethod: httpMethod,
        filePath: filePath,
        statusCode: statusCode,
        contentType: contentType,
        customHeaders: Map.of(customHeaders),
        isEnabled: isEnabled,
        isCaseSensitive: isCaseSensitive,
        useRegex: useRegex,
        watchFile: watchFile,
        cacheTTL: cacheTTL,
        notes: notes,
      );
}
