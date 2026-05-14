import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakanstudent_mobile/core/config/env_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('rakanstudent_mobile/device');

  Future<void> loadEnv({String? apiBaseUrl}) async {
    dotenv.loadFromString(
      envString: [
        if (apiBaseUrl != null) 'MOBILE_API_BASE_URL=$apiBaseUrl',
        'MOBILE_SUPABASE_URL=https://example.supabase.co',
        'MOBILE_SUPABASE_ANON_KEY=test-anon-key',
      ].join('\n'),
    );
  }

  setUp(() {
    EnvConfig.resetForTesting();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
    EnvConfig.resetForTesting();
  });

  test('defaults Android emulator API calls to host loopback alias', () async {
    await loadEnv();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'isEmulator');
          return true;
        });

    await EnvConfig.initialize();

    expect(EnvConfig.apiBaseUrl, 'http://10.0.2.2:5000/api');
  });

  test(
    'uses configured API base URL on Android emulator when provided',
    () async {
      await loadEnv(apiBaseUrl: 'http://10.0.2.2:5000/api');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => true);

      await EnvConfig.initialize();

      expect(EnvConfig.apiBaseUrl, 'http://10.0.2.2:5000/api');
    },
  );

  test(
    'requires configured API base URL for physical Android devices',
    () async {
      await loadEnv();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => false);

      await expectLater(
        EnvConfig.initialize(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Missing MOBILE_API_BASE_URL'),
          ),
        ),
      );
    },
  );
}
