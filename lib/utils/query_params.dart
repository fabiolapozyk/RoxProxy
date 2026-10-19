/// A single query-string parameter (name/value pair) as it appears in a URL.
class QueryParam {
  final String name;
  final String value;

  const QueryParam(this.name, this.value);

  @override
  String toString() => '$name=$value';
}

/// Returns the raw query string of [url] (the part after the first `?`,
/// excluding any `#fragment`), or `null` when there is none.
String? queryStringOf(String url) {
  final start = url.indexOf('?');
  if (start < 0) return null;
  var query = url.substring(start + 1);
  final fragment = query.indexOf('#');
  if (fragment >= 0) query = query.substring(0, fragment);
  return query;
}

/// Parses a raw query string into an ordered list of [QueryParam].
///
/// Unlike `Uri.queryParameters`, order and repeated keys are preserved (e.g.
/// `a=1&a=2` yields two entries). `+` and percent-encoding are decoded.
List<QueryParam> parseQueryParameters(String? query) {
  if (query == null || query.isEmpty) return const [];
  final params = <QueryParam>[];
  for (final pair in query.split('&')) {
    if (pair.isEmpty) continue;
    final eq = pair.indexOf('=');
    final rawName = eq < 0 ? pair : pair.substring(0, eq);
    final rawValue = eq < 0 ? '' : pair.substring(eq + 1);
    params.add(QueryParam(_decode(rawName), _decode(rawValue)));
  }
  return params;
}

String _decode(String value) {
  try {
    // Handles percent escapes and turns '+' into a space.
    return Uri.decodeQueryComponent(value);
  } catch (_) {
    return value;
  }
}
