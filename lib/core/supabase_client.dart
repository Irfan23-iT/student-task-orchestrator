import 'package:supabase_flutter/supabase_flutter.dart';

class AppSupabaseClient {
  AppSupabaseClient._();

  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) {
    return Supabase.initialize(url: url, anonKey: anonKey);
  }

  static SupabaseClient get instance => Supabase.instance.client;
}
