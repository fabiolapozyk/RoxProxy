import 'domain_rule.dart';

class ProxySettings {
  int port;
  List<DomainRule> domainRules;
  bool isRecording;
  int maxExchanges;
  bool autoStartProxy;
  int connectionTimeoutSeconds;
  bool setSystemProxy;
  bool httpsInterceptionEnabled;
  bool breakpointEnabled;

  ProxySettings({
    this.port = 8080,
    List<DomainRule>? domainRules,
    this.isRecording = true,
    this.maxExchanges = 10000,
    this.autoStartProxy = true,
    this.connectionTimeoutSeconds = 30,
    this.setSystemProxy = false,
    this.httpsInterceptionEnabled = true,
    this.breakpointEnabled = false,
  }) : domainRules = domainRules ?? [];

  Map<String, dynamic> toJson() => {
    'port': port,
    'domainRules': domainRules.map((r) => r.toMap()).toList(),
    'isRecording': isRecording,
    'maxExchanges': maxExchanges,
    'autoStartProxy': autoStartProxy,
    'connectionTimeoutSeconds': connectionTimeoutSeconds,
    'setSystemProxy': setSystemProxy,
    'httpsInterceptionEnabled': httpsInterceptionEnabled,
    'breakpointEnabled': breakpointEnabled,
  };

  factory ProxySettings.fromJson(Map<String, dynamic> json) => ProxySettings(
    port: json['port'] as int? ?? 8080,
    domainRules:
        (json['domainRules'] as List<dynamic>?)
            ?.map(
              (e) => DomainRule.fromMap(Map<String, dynamic>.from(e as Map)),
            )
            .toList() ??
        [],
    isRecording: json['isRecording'] as bool? ?? true,
    maxExchanges: json['maxExchanges'] as int? ?? 10000,
    autoStartProxy: json['autoStartProxy'] as bool? ?? true,
    connectionTimeoutSeconds: json['connectionTimeoutSeconds'] as int? ?? 30,
    setSystemProxy: json['setSystemProxy'] as bool? ?? false,
    httpsInterceptionEnabled: json['httpsInterceptionEnabled'] as bool? ?? true,
    breakpointEnabled: json['breakpointEnabled'] as bool? ?? false,
  );

  ProxySettings copyWith({
    int? port,
    List<DomainRule>? domainRules,
    bool? isRecording,
    int? maxExchanges,
    bool? autoStartProxy,
    int? connectionTimeoutSeconds,
    bool? setSystemProxy,
    bool? httpsInterceptionEnabled,
    bool? breakpointEnabled,
  }) => ProxySettings(
    port: port ?? this.port,
    domainRules: domainRules ?? this.domainRules,
    isRecording: isRecording ?? this.isRecording,
    maxExchanges: maxExchanges ?? this.maxExchanges,
    autoStartProxy: autoStartProxy ?? this.autoStartProxy,
    connectionTimeoutSeconds:
        connectionTimeoutSeconds ?? this.connectionTimeoutSeconds,
    setSystemProxy: setSystemProxy ?? this.setSystemProxy,
    httpsInterceptionEnabled:
        httpsInterceptionEnabled ?? this.httpsInterceptionEnabled,
    breakpointEnabled: breakpointEnabled ?? this.breakpointEnabled,
  );
}
