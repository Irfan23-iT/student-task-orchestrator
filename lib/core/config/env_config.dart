import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';

class EnvConfig {
  EnvConfig._();

  static const MethodChannel _deviceChannel = MethodChannel(
    'rakanstudent_mobile/device',
  );
  static const String _physicalAndroidApiBaseUrl =
      'http://192.168.0.129:5000/api';
  static const String _emulatorAndroidApiBaseUrl =
      'http://192.168.0.129:5000/api';

  static String? _apiBaseUrl;
  static String? _supabaseUrl;
  static String? _supabaseAnonKey;

  static String get apiBaseUrl =>
      _apiBaseUrl ??
      (kIsWeb ? 'http://localhost:5000/api' : _physicalAndroidApiBaseUrl);
  static String get supabaseUrl =>
      _supabaseUrl ??
      _readFirstOrFallback([
        'SUPABASE_URL',
        'MOBILE_SUPABASE_URL',
      ], 'https://example.supabase.co');
  static String get supabaseAnonKey =>
      _supabaseAnonKey ??
      _readFirstOrFallback([
        'SUPABASE_ANON_KEY',
        'MOBILE_SUPABASE_ANON_KEY',
      ], 'test-anon-key');

  static Future<void> initialize() async {
    _supabaseUrl = _readFirstRequired(['SUPABASE_URL', 'MOBILE_SUPABASE_URL']);
    _supabaseAnonKey = _readFirstRequired([
      'SUPABASE_ANON_KEY',
      'MOBILE_SUPABASE_ANON_KEY',
    ]);
    _apiBaseUrl = await _readApiBaseUrl();
  }

  static String _readFirstRequired(List<String> keys) {
    for (final key in keys) {
      final value = _readEnv(key);
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    throw StateError('Missing ${keys.join(' or ')} in .env');
  }

  static String _readFirstOrFallback(List<String> keys, String fallback) {
    for (final key in keys) {
      final value = _readEnv(key);
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    return fallback;
  }

  static Future<String> _readApiBaseUrl() async {
    final configuredUrl =
        _readEnv('API_URL') ??
        _readEnv('MOBILE_API_BASE_URL') ??
        _readEnv('API_BASE_URL');

    if (kIsWeb) {
      if (configuredUrl == null || configuredUrl.isEmpty) {
        return 'http://localhost:5000/api';
      }

      return configuredUrl.replaceFirst('10.0.2.2', 'localhost');
    }

    final isAndroidEmulator = await _isAndroidEmulator();
    if (isAndroidEmulator) {
      return _emulatorAndroidApiBaseUrl;
    }

    return configuredUrl ?? _physicalAndroidApiBaseUrl;
  }

  static String? _readEnv(String key) {
    try {
      return dotenv.env[key];
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _isAndroidEmulator() async {
    if (!defaultTargetPlatform.name.contains('android')) {
      return false;
    }

    try {
      return await _deviceChannel.invokeMethod<bool>('isEmulator') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
