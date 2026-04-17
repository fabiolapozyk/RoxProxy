// Simple test to verify breakpoint models work
import 'package:rox_proxy/models/breakpoint_request.dart';
import 'package:rox_proxy/models/breakpoint_response.dart';

void main() {
  // Test BreakpointRequest
  final request = BreakpointRequest(
    id: 'test-id',
    exchangeId: 'exchange-id',
    type: 'request',
    method: 'GET',
    url: 'https://example.com',
    headers: {'Content-Type': 'application/json'},
    body: '{"test": "data"}',
    isRequest: true,
    timestamp: DateTime.now(),
  );
  
  print('BreakpointRequest created: ${request.id}');
  print('Method: ${request.method}');
  print('URL: ${request.url}');
  
  // Test JSON serialization
  final json = request.toJson();
  print('JSON serialization: $json');
  
  // Test BreakpointResponse
  final response = BreakpointResponse(
    breakpointId: 'test-id',
    action: 'proceed',
    modifiedMethod: 'POST',
    modifiedUrl: 'https://example.com/api',
    modifiedHeaders: {'Content-Type': 'application/json', 'Authorization': 'Bearer token'},
    modifiedBody: '{"modified": "data"}',
    timestamp: DateTime.now(),
  );
  
  print('BreakpointResponse created: ${response.breakpointId}');
  print('Action: ${response.action}');
  print('Modified URL: ${response.modifiedUrl}');
  
  final responseJson = response.toJson();
  print('Response JSON: $responseJson');
  
  print('Breakpoint models test completed successfully!');
}