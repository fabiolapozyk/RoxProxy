import 'package:uuid/uuid.dart';

enum BreakpointTrigger {
  request,  // Pause before sending request to server
  response, // Pause before sending response to client
  both      // Pause for both request and response
}

class Breakpoint {
  final String id;
  String urlPattern;  // URL pattern to match (can include query params)
  BreakpointTrigger trigger;
  bool isEnabled;

  Breakpoint({
    String? id,
    required this.urlPattern,
    this.trigger = BreakpointTrigger.both,
    this.isEnabled = true,
  }) : id = id ?? const Uuid().v4();

  /// Check if this breakpoint matches the given URL
  bool matches(String url) {
    if (!isEnabled) return false;
    
    // Simple exact match for now
    // Could be enhanced with pattern matching (wildcards, regex)
    return url == urlPattern;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'urlPattern': urlPattern,
    'trigger': trigger.name,
    'isEnabled': isEnabled,
  };

  factory Breakpoint.fromMap(Map<String, dynamic> map) => Breakpoint(
    id: map['id'] as String?,
    urlPattern: map['urlPattern'] as String,
    trigger: BreakpointTrigger.values.firstWhere(
      (e) => e.name == map['trigger'],
      orElse: () => BreakpointTrigger.both,
    ),
    isEnabled: map['isEnabled'] as bool? ?? true,
  );

  Breakpoint copyWith({
    String? urlPattern,
    BreakpointTrigger? trigger,
    bool? isEnabled,
  }) => Breakpoint(
    id: id,
    urlPattern: urlPattern ?? this.urlPattern,
    trigger: trigger ?? this.trigger,
    isEnabled: isEnabled ?? this.isEnabled,
  );
}