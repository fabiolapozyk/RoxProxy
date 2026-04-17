import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../models/captured_exchange.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/breakpoint_rule.dart';
import '../providers/breakpoint_provider.dart';
import '../providers/proxy_channel_provider.dart';
import '../services/proxy_channel.dart';
import '../ui/breakpoint_dialog.dart';

/// Temporary interceptor to test breakpoint functionality
/// This will be replaced by native implementation
final breakpointInterceptorProvider = Provider<BreakpointInterceptor>((ref) {
  return BreakpointInterceptor(ref);
});

class BreakpointInterceptor {
  final Ref _ref;
  late final ProxyChannel _proxyChannel;
  final Set<String> _shownDialogs = {}; // Track which exchanges have shown dialogs

  BreakpointInterceptor(this._ref) {
    _proxyChannel = _ref.read(proxyChannelProvider);
  }

  void checkExchange(CapturedExchange exchange) {
    debugPrint('[Breakpoint] Checking exchange: ${exchange.url}');
    
    // Prevent duplicate dialogs for the same exchange
    if (_shownDialogs.contains(exchange.id)) {
      debugPrint('[Breakpoint] Already shown dialog for this exchange, skipping');
      return;
    }
    
    final rules = _ref.read(breakpointProvider);
    debugPrint('[Breakpoint] Active rules: ${rules.length}');
    
    final context = _ref.read(navigationServiceProvider).context;
    
    if (context == null) {
      debugPrint('[Breakpoint] No context available');
      return;
    }
    
    for (final rule in rules) {
      debugPrint('[Breakpoint] Checking rule: ${rule.urlPattern} (enabled: ${rule.isEnabled})');
      
      if (!rule.isEnabled) continue;
      
      // Check if URL matches
      if (rule.matches(exchange.url)) {
        debugPrint('[Breakpoint] MATCH! URL: ${exchange.url}');
        
        // For testing purposes, show dialog on first sight of matching exchange
        // In production, this will be handled by native layer pausing the exchange
        if (rule.interceptRequest || rule.interceptResponse) {
          debugPrint('[Breakpoint] Showing dialog for ${rule.interceptRequest ? 'request' : 'response'}');
          _shownDialogs.add(exchange.id); // Mark as shown
          _showBreakpointDialog(context, exchange, rule.interceptRequest);
          return;
        }
      }
    }
    
    debugPrint('[Breakpoint] No match found');
  }

  void _showBreakpointDialog(
    BuildContext context,
    CapturedExchange exchange,
    bool isRequest,
  ) {
    // Bring window to front before showing dialog
    _proxyChannel.bringWindowToFront();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BreakpointDialog(
        exchange: exchange,
        isRequest: isRequest,
      ),
    ).then((result) {
      if (result == 'resumed') {
        print('[Breakpoint] Exchange ${exchange.id} was resumed with modifications');
      } else if (result == 'cancelled') {
        print('[Breakpoint] Exchange ${exchange.id} was cancelled');
      }
    });
  }
}

/// Temporary navigation service to access context
final navigationServiceProvider = Provider<NavigationService>((ref) {
  return NavigationService();
});

class NavigationService {
  BuildContext? context;
}