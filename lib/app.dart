import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/breakpoint_service.dart';
import 'ui/main_window.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class RoxProxyApp extends StatelessWidget {
  const RoxProxyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rox Proxy',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AFF),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: '.AppleSystemUIFont',
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: '.AppleSystemUIFont',
      ),
      home: const MainWindow(),
    );
  }
}
