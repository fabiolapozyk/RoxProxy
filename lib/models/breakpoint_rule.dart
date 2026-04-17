import 'package:uuid/uuid.dart';

class BreakpointRule {
  final String id;
  String urlPattern;
  bool isEnabled;
  bool interceptRequest;
  bool interceptResponse;

  BreakpointRule({
    String? id,
    required this.urlPattern,
    this.isEnabled = true,
    this.interceptRequest = true,
    this.interceptResponse = true,
  }) : id = id ?? const Uuid().v4();

  bool matches(String url) {
    if (!isEnabled) return false;
    
    // Normalize URL for comparison
    final normalizedUrl = url.toLowerCase();
    final pattern = urlPattern.toLowerCase();
    
    // Remove protocol for comparison
    final cleanUrl = normalizedUrl.replaceFirst(RegExp(r'^[a-z]+://'), '');
    final cleanPattern = pattern.replaceFirst(RegExp(r'^[a-z]+://'), '');
    
    // Exact match (including trailing slash)
    if (cleanPattern == cleanUrl) return true;
    
    // Match root path only (httpforever.com matches httpforever.com/ but not httpforever.com/js/...)
    if (!cleanPattern.contains('/') && cleanUrl == '$cleanPattern/') return true;
    
    // Wildcard match (*.example.com)
    if (cleanPattern.startsWith('*.')) {
      final suffix = cleanPattern.substring(2);
      return cleanUrl == suffix || cleanUrl.startsWith('$suffix/') || cleanUrl == '$suffix';
    }
    
    // Path wildcard (example.com/*)
    if (cleanPattern.endsWith('/*')) {
      final base = cleanPattern.substring(0, cleanPattern.length - 2);
      return cleanUrl.startsWith('$base/');
    }
    
    return false;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'urlPattern': urlPattern,
    'isEnabled': isEnabled,
    'interceptRequest': interceptRequest,
    'interceptResponse': interceptResponse,
  };

  factory BreakpointRule.fromMap(Map<String, dynamic> map) => BreakpointRule(
    id: map['id'] as String?,
    urlPattern: map['urlPattern'] as String,
    isEnabled: map['isEnabled'] as bool? ?? true,
    interceptRequest: map['interceptRequest'] as bool? ?? true,
    interceptResponse: map['interceptResponse'] as bool? ?? true,
  );

  BreakpointRule copyWith({
    String? urlPattern,
    bool? isEnabled,
    bool? interceptRequest,
    bool? interceptResponse,
  }) => BreakpointRule(
    id: id,
    urlPattern: urlPattern ?? this.urlPattern,
    isEnabled: isEnabled ?? this.isEnabled,
    interceptRequest: interceptRequest ?? this.interceptRequest,
    interceptResponse: interceptResponse ?? this.interceptResponse,
  );

  /// Create a breakpoint rule from an exchange URL
  static BreakpointRule fromExchangeUrl(String url) {
    // Extract just the path part for exact matching
    try {
      final uri = Uri.parse(url);
      final path = uri.path.isEmpty ? '/' : uri.path;
      final hostWithPath = '${uri.host}$path';
      return BreakpointRule(
        urlPattern: hostWithPath,
        interceptRequest: true,
        interceptResponse: true,
      );
    } catch (e) {
      // Fallback to full URL if parsing fails
      return BreakpointRule(
        urlPattern: url,
        interceptRequest: true,
        interceptResponse: true,
      );
    }
  }
}