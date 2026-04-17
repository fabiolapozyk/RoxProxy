import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/proxy_settings.dart';

class SettingsService {
  static const _fileName = 'settings.json';
  static const _appSupportDir = 'RoxProxy';

  Future<File> _settingsFile() async {
    final appSupport = await getApplicationSupportDirectory();
    final dir = Directory('${appSupport.path}/$_appSupportDir');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/$_fileName');
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

  // Additional methods for breakpoint service
  Future<dynamic> getValue(String key) async {
    try {
      final file = await _settingsFile();
      if (!file.existsSync()) return null;
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return json[key];
    } catch (_) {
      return null;
    }
  }

  Future<void> setValue(String key, dynamic value) async {
    try {
      final file = await _settingsFile();
      final Map<String, dynamic> json;
      
      if (file.existsSync()) {
        json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      } else {
        json = {};
      }
      
      json[key] = value;
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(json),
      );
    } catch (_) {}
  }
}
