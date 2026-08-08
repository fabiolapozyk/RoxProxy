import 'dart:convert';
import 'dart:io';

import '../models/map_local_rule.dart';
import '../utils/path_utils.dart';

/// Persists Map Local rules to `~/Library/Application Support/RoxProxy/map_local_rules.json`.
///
/// Auto-saves after every modification (via `MapLocalNotifier`) and keeps the
/// last 5 versions as `.backup.N` files.
class MapLocalService {
  static const _fileName = 'map_local_rules.json';
  static const _backupCount = 5;

  /// Overrides the storage directory (used by tests); when null the standard
  /// Application Support directory is used.
  final String? overrideDirectory;

  MapLocalService({this.overrideDirectory});

  String get _directory =>
      overrideDirectory ?? PathUtils.applicationSupportDirectory;

  String get _filePath => '$_directory/$_fileName';

  Future<List<MapLocalRule>> load() async {
    try {
      final file = File(_filePath);
      if (!file.existsSync()) return [];
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! List) return [];
      return decoded
          .map((e) => MapLocalRule.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<MapLocalRule> rules) async {
    try {
      final dir = Directory(_directory);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _rotateBackups();
      File(_filePath).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(
          rules.map((r) => r.toJson()).toList(),
        ),
      );
    } catch (_) {}
  }

  /// Shifts the previous file to `.backup.1`, previous backups to `.backup.N+1`,
  /// keeping at most `_backupCount` versions.
  void _rotateBackups() {
    for (var i = _backupCount - 1; i >= 1; i--) {
      final src = '$_filePath.backup.$i';
      final dst = '$_filePath.backup.${i + 1}';
      if (File(src).existsSync()) File(src).renameSync(dst);
    }
    if (File(_filePath).existsSync()) File(_filePath).renameSync('$_filePath.backup.1');
  }
}
