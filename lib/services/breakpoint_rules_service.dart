import 'dart:convert';
import 'dart:io';

import '../models/breakpoint_rule.dart';
import '../utils/path_utils.dart';

/// Persiste le regole breakpoint in
/// `~/Library/Application Support/RoxProxy/breakpoint_rules.json`.
///
/// Auto-save dopo ogni modifica, con rotazione delle ultime 5 versioni come
/// `.backup.N` (pattern `MapLocalService`).
class BreakpointRulesService {
  static const _fileName = 'breakpoint_rules.json';
  static const _backupCount = 5;

  /// Override della directory di storage (usata dai test); quando null usa la
  /// directory Application Support standard.
  final String? overrideDirectory;

  BreakpointRulesService({this.overrideDirectory});

  String get _directory =>
      overrideDirectory ?? PathUtils.applicationSupportDirectory;

  String get _filePath => '$_directory/$_fileName';

  Future<List<BreakpointRule>> load() async {
    try {
      final file = File(_filePath);
      if (!file.existsSync()) return [];
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! List) return [];
      return decoded
          .map((e) => BreakpointRule.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<BreakpointRule> rules) async {
    try {
      final dir = Directory(_directory);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _rotateBackups();
      File(_filePath).writeAsStringSync(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(rules.map((r) => r.toJson()).toList()),
      );
    } catch (_) {}
  }

  void _rotateBackups() {
    for (var i = _backupCount - 1; i >= 1; i--) {
      final src = '$_filePath.backup.$i';
      final dst = '$_filePath.backup.${i + 1}';
      if (File(src).existsSync()) File(src).renameSync(dst);
    }
    if (File(_filePath).existsSync()) {
      File(_filePath).renameSync('$_filePath.backup.1');
    }
  }
}
