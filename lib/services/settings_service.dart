import 'dart:convert';
import 'dart:io';

import '../models/proxy_settings.dart';
import '../utils/path_utils.dart';

class SettingsService {
  static const _fileName = 'settings.json';

  Future<File> _settingsFile() async {
    final filePath = PathUtils.getFilePath(_fileName);
    return File(filePath);
  }

  Future<ProxySettings> load() async {
    try {
      final file = await _settingsFile();
      if (!file.existsSync()) return ProxySettings();
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return ProxySettings.fromJson(json);
    } catch (_) {
      return ProxySettings();
    }
  }

  Future<void> save(ProxySettings settings) async {
    try {
      final file = await _settingsFile();
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      );
    } catch (_) {}
  }
}
