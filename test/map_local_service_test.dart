import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/models/map_local_rule.dart';
import 'package:rox_proxy/services/map_local_service.dart';

void main() {
  late Directory tempDir;
  late MapLocalService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('map_local_test');
    service = MapLocalService(overrideDirectory: tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  MapLocalRule rule(String path) => MapLocalRule(pathPattern: path);

  test('load returns empty list when no file exists', () async {
    expect(await service.load(), isEmpty);
  });

  test('save and load round-trip', () async {
    await service.save([rule('/api/a'), rule('/api/b')]);
    final loaded = await service.load();
    expect(loaded.length, 2);
    expect(loaded[0].pathPattern, '/api/a');
    expect(loaded[1].pathPattern, '/api/b');
    expect(loaded[0].id, isNotEmpty);
  });

  test('load tolerates corrupt JSON', () async {
    File(
      '${tempDir.path}/map_local_rules.json',
    ).writeAsStringSync('{not valid json');
    expect(await service.load(), isEmpty);
  });

  test('load tolerates non-list JSON', () async {
    File(
      '${tempDir.path}/map_local_rules.json',
    ).writeAsStringSync('{"foo": 1}');
    expect(await service.load(), isEmpty);
  });

  test('saved file uses indented JSON', () async {
    await service.save([rule('/api/a')]);
    final raw = File('${tempDir.path}/map_local_rules.json').readAsStringSync();
    final decoded = jsonDecode(raw) as List;
    expect(decoded.length, 1);
    expect(raw, contains('\n    "pathPattern"'));
  });

  test('backup rotation keeps last 5 versions', () async {
    for (var i = 1; i <= 7; i++) {
      await service.save([rule('/api/v$i')]);
    }
    final dir = tempDir.path;
    expect(File('$dir/map_local_rules.json').existsSync(), isTrue);
    for (var i = 1; i <= 5; i++) {
      expect(
        File('$dir/map_local_rules.json.backup.$i').existsSync(),
        isTrue,
        reason: 'backup $i should exist',
      );
    }
    expect(File('$dir/map_local_rules.json.backup.6').existsSync(), isFalse);

    // Main file holds the newest version, backup.5 the oldest kept.
    final newest = await service.load();
    expect(newest.single.pathPattern, '/api/v7');
    final backup5 =
        jsonDecode(
              File('$dir/map_local_rules.json.backup.5').readAsStringSync(),
            )
            as List;
    expect((backup5.single as Map)['pathPattern'], '/api/v2');
  });
}
