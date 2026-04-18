import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  EnvConfig._();

  static late final String apiBaseUrl;
  static late final String supabaseUrl;
  static late final String supabaseAnonKey;

  static void initialize() {
    supabaseUrl = _readRequired('SUPABASE_URL');
    supabaseAnonKey = _readRequired('SUPABASE_ANON_KEY');
    apiBaseUrl =
        dotenv.env['MOBILE_API_BASE_URL'] ??
        dotenv.env['API_BASE_URL'] ??
        supabaseUrl;
  }

  static String _readRequired(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw StateError('Missing $key in .env');
    }

    return value;
  }
}
