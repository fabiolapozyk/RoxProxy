import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/breakpoint_service.dart';
import '../services/proxy_channel.dart';

final proxyChannelProvider = Provider<ProxyChannel>((ref) {
  return ProxyChannel();
});

final breakpointServiceProvider = Provider<BreakpointService>((ref) {
  final channel = ref.read(proxyChannelProvider);
  // We'll need to provide the navigator key when the app starts
  // For now, we'll create a service that can be initialized later
  return BreakpointService(channel, GlobalKey<NavigatorState>());
});
