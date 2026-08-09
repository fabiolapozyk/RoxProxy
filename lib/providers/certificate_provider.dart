import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'proxy_channel_provider.dart';

class CaTrustState {
  final bool initialized;
  final bool trusted;
  final bool isInstalling;
  final String? installError;

  const CaTrustState({
    this.initialized = false,
    this.trusted = false,
    this.isInstalling = false,
    this.installError,
  });

  CaTrustState copyWith({
    bool? initialized,
    bool? trusted,
    bool? isInstalling,
    String? installError,
    bool clearError = false,
  }) => CaTrustState(
    initialized: initialized ?? this.initialized,
    trusted: trusted ?? this.trusted,
    isInstalling: isInstalling ?? this.isInstalling,
    installError: clearError ? null : (installError ?? this.installError),
  );
}

final caTrustProvider = StateNotifierProvider<CaTrustNotifier, CaTrustState>((
  ref,
) {
  return CaTrustNotifier(ref);
});

class CaTrustNotifier extends StateNotifier<CaTrustState> {
  final Ref _ref;

  CaTrustNotifier(this._ref) : super(const CaTrustState()) {
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    try {
      final channel = _ref.read(proxyChannelProvider);
      final status = await channel.getCAStatus();
      state = state.copyWith(
        initialized: status.initialized,
        trusted: status.trusted,
      );
    } catch (_) {}
  }

  Future<void> install() async {
    state = state.copyWith(isInstalling: true, clearError: true);
    try {
      final trusted = await _ref
          .read(proxyChannelProvider)
          .installCACertificate();
      state = state.copyWith(trusted: trusted, isInstalling: false);
    } catch (e) {
      state = state.copyWith(isInstalling: false, installError: e.toString());
    }
  }

  Future<void> refresh() => _checkStatus();
}
