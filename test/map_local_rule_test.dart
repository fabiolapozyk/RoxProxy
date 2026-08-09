import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/map_local_rule.dart';

void main() {
  group('MapLocalRule model', () {
    test('defaults', () {
      final rule = MapLocalRule();
      expect(rule.id, isNotEmpty);
      expect(rule.hostPattern, '*');
      expect(rule.pathPattern, '**');
      expect(rule.httpMethod, 'ANY');
      expect(rule.filePath, '');
      expect(rule.statusCode, 200);
      expect(rule.contentType, isNull);
      expect(rule.customHeaders, isEmpty);
      expect(rule.isEnabled, isTrue);
      expect(rule.isCaseSensitive, isTrue);
      expect(rule.useRegex, isFalse);
    });

    test('displayName falls back to pathPattern', () {
      expect(MapLocalRule().displayName, '**');
      expect(MapLocalRule(name: 'Users API').displayName, 'Users API');
      expect(MapLocalRule(name: '  ').displayName, '**');
    });

    test('toMap/fromMap round-trip', () {
      final rule = MapLocalRule(
        hostPattern: '*.example.com',
        pathPattern: '/api/*',
        httpMethod: 'POST',
        filePath: '/tmp/mock.json',
        statusCode: 201,
        contentType: 'application/json',
        customHeaders: {'X-Mock': 'yes'},
        isEnabled: false,
        isCaseSensitive: false,
        useRegex: true,
      );
      final restored = MapLocalRule.fromMap(rule.toMap());
      expect(restored.id, rule.id);
      expect(restored.hostPattern, '*.example.com');
      expect(restored.pathPattern, '/api/*');
      expect(restored.httpMethod, 'POST');
      expect(restored.filePath, '/tmp/mock.json');
      expect(restored.statusCode, 201);
      expect(restored.contentType, 'application/json');
      expect(restored.customHeaders, {'X-Mock': 'yes'});
      expect(restored.isEnabled, isFalse);
      expect(restored.isCaseSensitive, isFalse);
      expect(restored.useRegex, isTrue);
    });

    test('toMap only exposes runtime fields', () {
      final map = MapLocalRule(name: 'x', notes: 'n').toMap();
      expect(map.containsKey('name'), isFalse);
      expect(map.containsKey('notes'), isFalse);
      expect(map.containsKey('id'), isTrue);
      expect(map.containsKey('pathPattern'), isTrue);
    });

    test('toJson/fromJson round-trip with metadata', () {
      final rule = MapLocalRule(
        name: 'Mock',
        hostPattern: '*',
        pathPattern: '**.json',
        httpMethod: 'GET',
        filePath: '/tmp/a.json',
        statusCode: 200,
        customHeaders: {'X-A': '1'},
        notes: 'note',
        watchFile: true,
        cacheTTL: 60,
      );
      final restored = MapLocalRule.fromJson(rule.toJson());
      expect(restored.id, rule.id);
      expect(restored.name, 'Mock');
      expect(restored.pathPattern, '**.json');
      expect(restored.httpMethod, 'GET');
      expect(restored.filePath, '/tmp/a.json');
      expect(restored.customHeaders, {'X-A': '1'});
      expect(restored.notes, 'note');
      expect(restored.watchFile, isTrue);
      expect(restored.cacheTTL, 60);
      expect(restored.createdAt, rule.createdAt);
      expect(restored.updatedAt, rule.updatedAt);
    });

    test('fromJson tolerates missing fields', () {
      final rule = MapLocalRule.fromJson({'id': 'abc'});
      expect(rule.id, 'abc');
      expect(rule.hostPattern, '*');
      expect(rule.pathPattern, '**');
      expect(rule.httpMethod, 'ANY');
      expect(rule.statusCode, 200);
      expect(rule.isEnabled, isTrue);
    });

    test('copyWith keeps id and createdAt', () {
      final rule = MapLocalRule(pathPattern: '/old');
      final updated = rule.copyWith(pathPattern: '/new', statusCode: 404);
      expect(updated.id, rule.id);
      expect(updated.createdAt, rule.createdAt);
      expect(updated.pathPattern, '/new');
      expect(updated.statusCode, 404);
      expect(updated.hostPattern, rule.hostPattern);
    });

    test('duplicate creates a fresh rule with new id', () {
      final rule = MapLocalRule(name: 'X', pathPattern: '/api/*');
      final copy = rule.duplicate();
      expect(copy.id, isNot(rule.id));
      expect(copy.pathPattern, '/api/*');
      expect(copy.name, 'X (copy)');
    });
  });
}
