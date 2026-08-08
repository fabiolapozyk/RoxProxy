import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rox_proxy/app.dart';

void main() {
  testWidgets('App builds and shows the main window', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RoxProxyApp()));

    expect(find.text('Rox Proxy'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
