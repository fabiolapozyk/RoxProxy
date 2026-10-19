import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rox_proxy/services/menu_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(MenuChannel.clearHandler);

  Future<void> deliver(String method, Object? arguments) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          MenuChannel.channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          (_) {},
        );
  }

  test('forwards menuAction arguments to the registered handler', () async {
    final received = <String>[];
    MenuChannel.setHandler((action) async => received.add(action));

    await deliver(MenuChannel.actionMethod, 'openCapture');
    await deliver(MenuChannel.actionMethod, 'openSession');
    await deliver(MenuChannel.actionMethod, 'exportHar');

    expect(received, ['openCapture', 'openSession', 'exportHar']);
  });

  test('ignores unknown methods and non-string arguments', () async {
    final received = <String>[];
    MenuChannel.setHandler((action) async => received.add(action));

    await deliver('somethingElse', 'openCapture');
    await deliver(MenuChannel.actionMethod, 42);

    expect(received, isEmpty);
  });

  test('clearHandler unsubscribes the handler', () async {
    var called = false;
    MenuChannel.setHandler((action) async => called = true);
    MenuChannel.clearHandler();

    await deliver(MenuChannel.actionMethod, 'openCapture');

    expect(called, isFalse);
  });
}
