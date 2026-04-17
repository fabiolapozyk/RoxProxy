import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/breakpoint_service.dart';
import '../services/proxy_channel.dart';
import '../models/breakpoint_request.dart';

// First, define the proxy channel provider
final proxyChannelProvider = Provider<ProxyChannel>((ref) {
  return ProxyChannel();
});

final breakpointServiceProvider = Provider<BreakpointService>((ref) {
  // Get the WebSocket port from the native side
  final proxyChannel = ref.watch(proxyChannelProvider);
  
  // Use a default port initially, then update when we get the real port
  var websocketUrl = 'ws://localhost:8081';
  
  // Try to get the actual WebSocket port
  proxyChannel.getWebSocketPort().then((port) {
    websocketUrl = 'ws://localhost:$port';
  }).catchError((error) {
    print('Failed to get WebSocket port, using default: $error');
  });
  
  return BreakpointService(websocketUrl: websocketUrl);
});

final breakpointRequestsProvider = StreamProvider.autoDispose<BreakpointRequest?>((ref) {
  final breakpointService = ref.watch(breakpointServiceProvider);
  return breakpointService.breakpointRequests;
});