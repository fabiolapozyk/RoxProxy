sealed class ProxyState {
  const ProxyState();

  bool get isRunning => this is ProxyRunning;

  String get description => switch (this) {
    ProxyStopped() => 'Stopped',
    ProxyStarting() => 'Starting…',
    ProxyRunning(:final port) => 'Running on :$port',
    ProxyError(:final message) => 'Error: $message',
  };
}

class ProxyStopped extends ProxyState {
  const ProxyStopped();
}

class ProxyStarting extends ProxyState {
  const ProxyStarting();
}

class ProxyRunning extends ProxyState {
  final int port;
  const ProxyRunning(this.port);
}

class ProxyError extends ProxyState {
  final String message;
  const ProxyError(this.message);
}
