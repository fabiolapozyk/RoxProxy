# Breakpoint Feature Implementation

## Overview

This document describes the breakpoint feature implementation for Rox Proxy, which allows users to intercept, inspect, and modify HTTP/HTTPS requests and responses in real-time.

## Files Created

### Backend (Swift/NIO)

#### Models
- `Sources/RoxProxy/Models/BreakpointRequest.swift` - Data model for sending breakpoint requests to Flutter
- `Sources/RoxProxy/Models/BreakpointResponse.swift` - Data model for receiving user responses from Flutter

#### WebSocket Server
- `Sources/RoxProxy/WebSocket/WebSocketServer.swift` - Complete WebSocket server implementation
  - Handles WebSocket connections and message parsing
  - Manages breakpoint request/response routing
  - Includes HTTP to WebSocket upgrade handler

#### Enhanced Components
- `Sources/RoxProxy/Proxy/HTTPProxyHandler.swift` - Modified to support breakpoints
  - Added breakpoint detection logic
  - Implemented request pausing and modification
  - Added 30-second timeout handling

- `Sources/RoxProxy/Proxy/ProxyServer.swift` - Updated to integrate WebSocket server
  - Starts WebSocket server alongside HTTP proxy
  - Manages WebSocket server lifecycle

### Frontend (Flutter)

#### Models
- `lib/models/breakpoint_request.dart` - Dart model for breakpoint requests
- `lib/models/breakpoint_response.dart` - Dart model for breakpoint responses
- `lib/models/breakpoint_request.g.dart` - Generated JSON serialization (auto-generated)
- `lib/models/breakpoint_response.g.dart` - Generated JSON serialization (auto-generated)

#### Services
- `lib/services/breakpoint_service.dart` - WebSocket communication service
  - Handles connection and message parsing
  - Manages breakpoint request streaming

#### UI Components
- `lib/ui/breakpoint_dialog.dart` - Complete dialog for editing requests/responses
  - Supports editing method, URL, headers, and body
  - Includes add/remove header functionality
  - Provides Proceed and Cancel actions

#### State Management
- `lib/providers/breakpoint_provider.dart` - Riverpod providers
  - Manages breakpoint service lifecycle
  - Provides breakpoint request stream

#### Integration
- `lib/ui/main_window.dart` - Updated to handle breakpoint requests
  - Listens for breakpoint requests
  - Automatically shows breakpoint dialog
  - Manages WebSocket connection

## Key Features

### 1. Request Interception
- All HTTP requests can trigger breakpoints
- Configurable breakpoint conditions (currently all requests)
- Real-time interception with minimal latency

### 2. WebSocket Communication
- Bidirectional communication between Swift backend and Flutter frontend
- Automatic reconnection handling
- JSON-based message protocol

### 3. Request Modification
- Edit HTTP method (GET, POST, PUT, etc.)
- Modify URL and path
- Add/remove/modify headers
- Edit request body content

### 4. User Experience
- Professional dialog interface
- Syntax-highlighted JSON editing
- Header management with add/remove functionality
- Clear Proceed/Cancel actions

### 5. Error Handling
- 30-second timeout with automatic proceed
- Connection error handling
- Graceful degradation when WebSocket unavailable

## Technical Details

### WebSocket Protocol
- **Port**: 8081 (configurable)
- **Message Format**: JSON
- **Request Message**:
  ```json
  {
    "id": "uuid",
    "exchangeId": "uuid",
    "type": "request",
    "method": "GET",
    "url": "https://example.com",
    "headers": {"Content-Type": "application/json"},
    "body": "...",
    "isRequest": true,
    "timestamp": "2024-04-17T10:00:00Z"
  }
  ```

- **Response Message**:
  ```json
  {
    "breakpointId": "uuid",
    "action": "proceed",
    "modifiedMethod": "POST",
    "modifiedUrl": "https://example.com/api",
    "modifiedHeaders": {"Authorization": "Bearer token"},
    "modifiedBody": "...",
    "timestamp": "2024-04-17T10:00:05Z"
  }
  ```

### Timeout Handling
- **Duration**: 30 seconds
- **Behavior**: Automatic proceed with original request on timeout
- **Configurable**: Can be adjusted in `HTTPProxyHandler.swift`

### Performance
- **Latency**: Minimal overhead when breakpoints not triggered
- **Memory**: Efficient handling of large request/response bodies
- **Concurrency**: Uses NIO event loops for non-blocking operation

## Usage

### Starting the Proxy with Breakpoints

```dart
// Flutter side - automatically handled by the app
final proxyChannel = ProxyChannel();
final port = await proxyChannel.startProxy(
  port: 8080,
  domainRules: [],
  connectionTimeoutSeconds: 30,
  setSystemProxy: true,
  httpsInterceptionEnabled: true,
);

// WebSocket connection is established automatically
```

### Handling Breakpoints

1. **User Makes Request**: Any HTTP request through the proxy triggers a breakpoint
2. **Dialog Appears**: Breakpoint dialog shows request details
3. **User Edits**: Modify method, URL, headers, or body
4. **User Chooses Action**:
   - **Proceed**: Send modified request to server
   - **Cancel**: Abort the request with 400 Bad Request
5. **Timeout**: If no action after 30 seconds, proceed with original request

### Testing

A test script is provided at `test_breakpoint.dart`:

```bash
dart run test_breakpoint.dart
```

This verifies that the JSON serialization/deserialization works correctly.

## Configuration

### Breakpoint Conditions

Modify `shouldBreakpointRequest()` in `HTTPProxyHandler.swift` to change when breakpoints trigger:

```swift
private func shouldBreakpointRequest(head: HTTPRequestHead) -> Bool {
    // Current: breakpoint on all requests
    return true
    
    // Example: breakpoint only on POST requests
    // return head.method == .POST
    
    // Example: breakpoint on specific URLs
    // return head.uri.contains("api.example.com")
}
```

### WebSocket Port

Change the default WebSocket port in `ProxyServer.swift`:

```swift
init(
    port: Int,
    // ... other parameters ...
    websocketPort: Int = 8081 // Change this value
)
```

### Timeout Duration

Adjust the breakpoint timeout in `HTTPProxyHandler.swift`:

```swift
let timeoutTask = context.eventLoop.scheduleTask(in: .seconds(30)) {
    promise.fail(BreakpointError.timeout)
}
```

## Troubleshooting

### Build Issues

If you encounter build issues:

1. **Clean build**:
   ```bash
   flutter clean
   flutter pub get
   ```

2. **Regenerate JSON serialization**:
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

3. **Check dependencies**:
   ```bash
   flutter pub outdated
   flutter pub upgrade
   ```

### Runtime Issues

1. **WebSocket connection failed**:
   - Verify WebSocket server is running
   - Check firewall settings
   - Verify port 8081 is available

2. **Breakpoints not triggering**:
   - Check `shouldBreakpointRequest()` logic
   - Verify proxy is intercepting traffic
   - Check browser/system proxy settings

3. **Modifications not applied**:
   - Verify JSON serialization/deserialization
   - Check WebSocket message format
   - Review `applyModifications()` in `HTTPProxyHandler.swift`

## Future Enhancements

1. **Response Breakpoints**: Intercept and modify responses
2. **Binary Data Support**: Handle image/video uploads
3. **Breakpoint Rules**: UI for configuring breakpoint conditions
4. **Breakpoint History**: Track past breakpoints and modifications
5. **Scripting**: Allow JavaScript/Python scripts to modify requests
6. **Automation**: Auto-respond to breakpoints based on rules

## Dependencies Added

### Swift
- `NIOWebSocket`: WebSocket support for SwiftNIO
- `Logging`: Structured logging framework

### Flutter
- `web_socket_channel`: WebSocket client for Flutter
- `json_annotation`: JSON serialization annotations
- `json_serializable`: JSON serialization code generation

## Version

Implementation completed for Rox Proxy v0.0.6+6

## License

This implementation is provided under the same license as Rox Proxy (see LICENSE file).