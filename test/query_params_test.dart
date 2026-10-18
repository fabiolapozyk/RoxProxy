import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/utils/query_params.dart';

void main() {
  group('queryStringOf', () {
    test('returns null when there is no query string', () {
      expect(queryStringOf('https://api.example.com/users'), isNull);
      expect(queryStringOf('/users'), isNull);
      expect(queryStringOf('https://api.example.com/users#frag'), isNull);
    });

    test('extracts the raw query string', () {
      expect(queryStringOf('https://api.example.com/users?a=1&b=2'), 'a=1&b=2');
      expect(queryStringOf('/users?a=1'), 'a=1');
    });

    test('strips the fragment', () {
      expect(queryStringOf('https://api.example.com/users?a=1#frag'), 'a=1');
    });

    test('handles an empty query string', () {
      expect(queryStringOf('https://api.example.com/users?'), '');
    });
  });

  group('parseQueryParameters', () {
    test('returns empty for null or empty input', () {
      expect(parseQueryParameters(null), isEmpty);
      expect(parseQueryParameters(''), isEmpty);
    });

    test('parses pairs preserving order', () {
      final params = parseQueryParameters('a=1&b=2&c=3');
      expect(params.map((p) => p.name), ['a', 'b', 'c']);
      expect(params.map((p) => p.value), ['1', '2', '3']);
    });

    test('preserves repeated keys', () {
      final params = parseQueryParameters('tag=a&tag=b');
      expect(params.length, 2);
      expect(params[0].value, 'a');
      expect(params[1].value, 'b');
    });

    test('decodes percent-encoding and plus as space', () {
      final params = parseQueryParameters('q=hello+world&path=%2Fapi%2Fv1');
      expect(params[0].value, 'hello world');
      expect(params[1].value, '/api/v1');
    });

    test('supports flags without a value', () {
      final params = parseQueryParameters('debug');
      expect(params.single.name, 'debug');
      expect(params.single.value, '');
    });

    test('supports empty values', () {
      expect(parseQueryParameters('a=').single.value, '');
    });

    test('keeps malformed escapes as-is instead of throwing', () {
      expect(parseQueryParameters('a=%ZZ').single.value, '%ZZ');
    });

    test('ignores empty segments', () {
      expect(parseQueryParameters('a=1&&b=2&').length, 2);
    });
  });
}
