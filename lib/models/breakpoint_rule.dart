import '../utils/uuid.dart';

/// Quale traffico intercetta una regola breakpoint.
enum BreakpointTarget { request, response, both }

/// Regola breakpoint configurabile da UI (RF1.3 — fase 2).
/// Host e path sono pattern glob, come Map Local.
class BreakpointRule {
  final String id;
  String? name;
  String hostPattern;
  String pathPattern;
  String httpMethod;
  BreakpointTarget target;
  bool isEnabled;
  final DateTime createdAt;
  DateTime updatedAt;

  BreakpointRule({
    String? id,
    this.name,
    this.hostPattern = '*',
    this.pathPattern = '**',
    this.httpMethod = 'ANY',
    this.target = BreakpointTarget.request,
    this.isEnabled = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? UUID.v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    return '$httpMethod $hostPattern$pathPattern';
  }

  /// Payload inviato al proxy nativo all'avvio (soli campi runtime).
  Map<String, dynamic> toMap() => {
    'id': id,
    'hostPattern': hostPattern,
    'pathPattern': pathPattern,
    'httpMethod': httpMethod,
    'target': target.name,
    'isEnabled': isEnabled,
  };

  factory BreakpointRule.fromMap(Map<String, dynamic> map) => BreakpointRule(
    id: map['id'] as String,
    name: map['name'] as String?,
    hostPattern: map['hostPattern'] as String? ?? '*',
    pathPattern: map['pathPattern'] as String? ?? '**',
    httpMethod: map['httpMethod'] as String? ?? 'ANY',
    target:
        BreakpointTarget.values.asNameMap()[map['target']] ??
        BreakpointTarget.request,
    isEnabled: map['isEnabled'] as bool? ?? true,
    createdAt:
        DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );

  /// Rappresentazione JSON completa per la persistenza.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'hostPattern': hostPattern,
    'pathPattern': pathPattern,
    'httpMethod': httpMethod,
    'target': target.name,
    'isEnabled': isEnabled,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory BreakpointRule.fromJson(Map<String, dynamic> json) => BreakpointRule(
    id: json['id'] as String,
    name: json['name'] as String?,
    hostPattern: json['hostPattern'] as String? ?? '*',
    pathPattern: json['pathPattern'] as String? ?? '**',
    httpMethod: json['httpMethod'] as String? ?? 'ANY',
    target:
        BreakpointTarget.values.asNameMap()[json['target']] ??
        BreakpointTarget.request,
    isEnabled: json['isEnabled'] as bool? ?? true,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );

  BreakpointRule copyWith({
    String? name,
    String? hostPattern,
    String? pathPattern,
    String? httpMethod,
    BreakpointTarget? target,
    bool? isEnabled,
    DateTime? updatedAt,
  }) => BreakpointRule(
    id: id,
    name: name ?? this.name,
    hostPattern: hostPattern ?? this.hostPattern,
    pathPattern: pathPattern ?? this.pathPattern,
    httpMethod: httpMethod ?? this.httpMethod,
    target: target ?? this.target,
    isEnabled: isEnabled ?? this.isEnabled,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  /// Copia profonda con id nuovo (azione Duplicate).
  BreakpointRule duplicate() => BreakpointRule(
    name: name == null ? '$displayName (copy)' : '${name!.trim()} (copy)',
    hostPattern: hostPattern,
    pathPattern: pathPattern,
    httpMethod: httpMethod,
    target: target,
    isEnabled: isEnabled,
  );
}

extension on Iterable<BreakpointTarget> {
  Map<String, BreakpointTarget> asNameMap() => {
    for (final t in this) t.name: t,
  };
}
