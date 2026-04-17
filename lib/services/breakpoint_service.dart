import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/breakpoint_request.dart';
import '../models/breakpoint_response.dart';

class BreakpointService {
  final String _websocketUrl;
  WebSocketChannel? _channel;
  final StreamController<BreakpointRequest> _breakpointRequests = StreamController.broadcast();
  
  BreakpointService({required String websocketUrl}) : _websocketUrl = websocketUrl;
  
  Stream<BreakpointRequest> get breakpointRequests => _breakpointRequests.stream;
  
  Future<void> connect() async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_websocketUrl));
      
      _channel?.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String);
            final request = BreakpointRequest.fromJson(data);
            _breakpointRequests.add(request);
          } catch (e) {
            print('Error decoding breakpoint request: $e');
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
          _breakpointRequests.addError(error);
        },
        onDone: () {
          print('WebSocket connection closed');
          _breakpointRequests.close();
        },
      );
      
      print('Connected to WebSocket server at $_websocketUrl');
    } catch (e) {
      print('Failed to connect to WebSocket server: $e');
      rethrow;
    }
  }
  
  Future<void> disconnect() async {
    await _channel?.sink.close();
    _channel = null;
    await _breakpointRequests.close();
    print('Disconnected from WebSocket server');
  }
  
  Future<void> sendBreakpointResponse(BreakpointResponse response) async {
    if (_channel == null || _channel?.closeCode != null) {
      throw Exception('WebSocket not connected');
    }
    
    try {
      final jsonData = jsonEncode(response.toJson());
      _channel?.sink.add(jsonData);
      print('Sent breakpoint response: ${response.breakpointId}');
    } catch (e) {
      print('Error sending breakpoint response: $e');
      rethrow;
    }
  }
  
  bool get isConnected => _channel != null && _channel?.closeCode == null;
}