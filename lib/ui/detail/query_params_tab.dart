import 'package:flutter/material.dart';

import '../../utils/query_params.dart';

/// Shows the query-string parameters of a request URL.
///
/// Used in place of the Body tab for body-less methods (GET/HEAD), where the
/// interesting request content is the query string rather than a body.
class QueryParamsTab extends StatelessWidget {
  final String url;

  const QueryParamsTab({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    final params = parseQueryParameters(queryStringOf(url));
    if (params.isEmpty) {
      return const Center(
        child: Text(
          'No query parameters',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return SelectionArea(
      child: ListView.builder(
        itemCount: params.length,
        itemExtent: 24,
        itemBuilder: (context, index) {
          final p = params[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 200,
                  child: Text(
                    p.name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Color(0xFF8E8E93),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.value,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
