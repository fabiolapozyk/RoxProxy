import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/breakpoint_rule.dart';

void main() {
  test('toMap serializes runtime fields for the native proxy', () {
    final rule = BreakpointRule(
      id: 'rule-1',
      name: 'API POST',
      hostPattern: '*.example.com',
      pathPattern: '/api/**',
      httpMethod: 'POST',
      target: BreakpointTarget.both,
      isEnabled: false,
    );
    final map = rule.toMap();
    expect(map['id'], 'rule-1');
    expect(map['hostPattern'], '*.example.com');
    expect(map['pathPattern'], '/api/**');
    expect(map['httpMethod'], 'POST');
    expect(map['target'], 'both');
    expect(map['isEnabled'], isFalse);
  });

  test('fromMap parses with defaults', () {
    final rule = BreakpointRule.fromMap({'id': 'r'});
    expect(rule.hostPattern, '*');
    expect(rule.pathPattern, '**');
    expect(rule.httpMethod, 'ANY');
    expect(rule.target, BreakpointTarget.request);
    expect(rule.isEnabled, isTrue);
  });

  test('json roundtrip preserves full state', () {
    final rule = BreakpointRule(
      name: 'x',
      hostPattern: 'api.example.com',
      pathPattern: '/a',
      httpMethod: 'DELETE',
      target: BreakpointTarget.response,
      isEnabled: false,
    );
    final restored = BreakpointRule.fromJson(rule.toJson());
    expect(restored.id, rule.id);
    expect(restored.name, 'x');
    expect(restored.hostPattern, 'api.example.com');
    expect(restored.pathPattern, '/a');
    expect(restored.httpMethod, 'DELETE');
    expect(restored.target, BreakpointTarget.response);
    expect(restored.isEnabled, isFalse);
  });

  test('duplicate creates a new id', () {
    final rule = BreakpointRule(hostPattern: 'h');
    final copy = rule.duplicate();
    expect(copy.id, isNot(rule.id));
    expect(copy.hostPattern, 'h');
  });
}
