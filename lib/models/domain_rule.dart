import '../utils/uuid.dart';

class DomainRule {
  final String id;
  String domain;
  bool isEnabled;

  DomainRule({String? id, required this.domain, this.isEnabled = true})
    : id = id ?? UUID.v4();

  bool matches(String host) {
    if (!isEnabled) return false;
    if (domain.startsWith('*.')) {
      final suffix = domain.substring(2);
      return host == suffix || host.endsWith('.$suffix');
    }
    return host == domain;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'domain': domain,
    'isEnabled': isEnabled,
  };

  factory DomainRule.fromMap(Map<String, dynamic> map) => DomainRule(
    id: map['id'] as String?,
    domain: map['domain'] as String,
    isEnabled: map['isEnabled'] as bool? ?? true,
  );
}
