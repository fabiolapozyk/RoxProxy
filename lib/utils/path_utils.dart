import 'dart:io';

/// Custom implementation to get macOS Application Support directory without path_provider.
/// 
/// On macOS, the Application Support directory is typically:
/// ~/Library/Application Support/
/// 
/// This implementation uses the HOME environment variable which is reliable on macOS.
class PathUtils {
  /// Returns the path to the Application Support directory for RoxProxy.
  /// 
  /// Creates the directory if it doesn't exist.
  /// 
  /// Example: "/Users/username/Library/Application Support/RoxProxy"
  static String get applicationSupportDirectory {
    final home = Platform.environment['HOME'];
    if (home == null) {
      throw Exception('HOME environment variable not set');
    }
    return '$home/Library/Application Support/RoxProxy';
  }

  /// Returns the path to a file in the Application Support directory.
  /// 
  /// Creates the directory if it doesn't exist.
  static String getFilePath(String fileName) {
    final dirPath = applicationSupportDirectory;
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return '$dirPath/$fileName';
  }
}
