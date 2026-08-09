import 'dart:math';

/// Custom UUID v4 generator to avoid external dependency.
///
/// UUID version 4 uses random bytes with specific bit patterns:
/// - Version bits (4): 0100 (binary) = 4 (decimal)
/// - Variant bits (2): 10 (binary) = 2 (decimal, RFC 4122)
///
/// Format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
/// where x is any random hex digit, and y is one of 8, 9, A, or B
class UUID {
  /// Generates a random UUID v4 string.
  ///
  /// Example: "f47ac10b-58cc-4372-a567-0e02b2c3d479"
  static String v4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));

    // Set version (4) in bits 6-7 of byte 6 (0-based index)
    bytes[6] = (bytes[6] & 0x0F) | 0x40;

    // Set variant (RFC 4122) in bits 6-7 of byte 8
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    // Convert to hex string with dashes
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
