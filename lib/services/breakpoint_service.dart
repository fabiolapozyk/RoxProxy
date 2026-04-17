import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import '../models/breakpoint.dart';
import '../models/captured_exchange.dart';
import '../providers/settings_provider.dart';
import '../ui/breakpoint_dialog.dart';
import 'proxy_channel.dart';

class BreakpointService {
  final ProxyChannel _channel;
  final GlobalKey<NavigatorState> _navigatorKey;
  
  // Map to store pending breakpoint resolutions
  final Map<String, Completer<Map<String, dynamic>>> _pendingResolutions = {};

  BreakpointService(this._channel, this._navigatorKey) {
    print('DEBUG: BreakpointService constructor called');
    print('DEBUG: Navigator key: $_navigatorKey');
    print('DEBUG: Setting up breakpoint stream listener...');
    // Start listening for breakpoint events
    _channel.breakpointStream.listen(_handleBreakpointEvent);
    print('DEBUG: BreakpointService initialized and listening for events');
  }

  /// Handle breakpoint events from native code
  void _handleBreakpointEvent(BreakpointEvent event) {
    print('DEBUG: Dart BreakpointService received event: ${event.url} (${event.isRequest ? 'Request' : 'Response'})');
    print('DEBUG: Exchange ID: ${event.exchangeId}');
    print('DEBUG: Event data: ${event.exchangeData}');
    
    // Create a completer for this breakpoint
    final completer = Completer<Map<String, dynamic>>();
    _pendingResolutions[event.exchangeId] = completer;
    
    try {
      // Create exchange from event data
      final exchange = CapturedExchange.fromMap(event.exchangeData);
      print('DEBUG: Successfully created exchange from event data');
      
      // Find the matching breakpoint (we'll pass this from the caller)
      final breakpoint = Breakpoint(urlPattern: exchange.url, trigger: BreakpointTrigger.both);
      print('DEBUG: Created breakpoint for URL: ${breakpoint.urlPattern}');
      
      // Show the breakpoint dialog
      print('DEBUG: About to show breakpoint dialog...');
      _showBreakpointDialog(exchange, breakpoint, event.isRequest, event.exchangeId);
    } catch (e, stackTrace) {
      print('DEBUG: ERROR in _handleBreakpointEvent: $e');
      print('DEBUG: Stack trace: $stackTrace');
      completer.complete({'shouldContinue': false});
      _pendingResolutions.remove(event.exchangeId);
    }
  }

  /// Show the breakpoint dialog and handle user input
  Future<void> _showBreakpointDialog(
    CapturedExchange exchange,
    Breakpoint breakpoint,
    bool isRequest,
    String exchangeId,
  ) async {
    try {
      print('DEBUG: Checking navigator context...');
      if (_navigatorKey.currentContext == null) {
        print('DEBUG: ERROR: Navigator context is null! Cannot show dialog.');
        if (_pendingResolutions.containsKey(exchangeId)) {
          _pendingResolutions[exchangeId]!.complete({'shouldContinue': false});
          _pendingResolutions.remove(exchangeId);
        }
        return;
      }
      
      print('DEBUG: Showing breakpoint dialog...');
      final result = await showDialog<Map<String, dynamic>>(
        context: _navigatorKey.currentContext!,
        barrierDismissible: false,
        builder: (context) => BreakpointDialog(
          exchange: exchange,
          breakpoint: breakpoint,
          isRequest: isRequest,
        ),
      );

      print('DEBUG: Dialog closed with result: $result');
      final resolution = result ?? {
        'shouldContinue': false,
      };

      // Complete the pending resolution
      if (_pendingResolutions.containsKey(exchangeId)) {
        print('DEBUG: Completing pending resolution for exchange $exchangeId');
        _pendingResolutions[exchangeId]!.complete(resolution);
        _pendingResolutions.remove(exchangeId);
      }

      // Notify native code of the resolution
      print('DEBUG: Notifying native code of resolution...');
      await _channel.resolveBreakpoint(
        exchangeId: exchangeId,
        shouldContinue: resolution['shouldContinue'] as bool,
        modifications: resolution['modifications'] as Map<String, dynamic>?,
      );
      print('DEBUG: Native code notified successfully');
    } catch (e, stackTrace) {
      print('DEBUG: ERROR in _showBreakpointDialog: $e');
      print('DEBUG: Stack trace: $stackTrace');
      if (_pendingResolutions.containsKey(exchangeId)) {
        _pendingResolutions[exchangeId]!.complete({'shouldContinue': false});
        _pendingResolutions.remove(exchangeId);
      }
    }
  }

  /// Wait for breakpoint resolution from native code
  Future<Map<String, dynamic>?> waitForBreakpointResolution(String exchangeId) async {
    // Check if there's already a pending resolution
    if (_pendingResolutions.containsKey(exchangeId)) {
      return await _pendingResolutions[exchangeId]!.future;
    }
    
    // If not, create a new completer and wait
    final completer = Completer<Map<String, dynamic>>();
    _pendingResolutions[exchangeId] = completer;
    
    return await completer.future;
  }

  /// Resolve a breakpoint and continue execution
  Future<void> resolveBreakpoint({
    required String exchangeId,
    required bool shouldContinue,
    Map<String, dynamic>? modifications,
  }) async {
    await _channel.resolveBreakpoint(
      exchangeId: exchangeId,
      shouldContinue: shouldContinue,
      modifications: modifications,
    );
  }

  void dispose() {
    _pendingResolutions.clear();
  }
}