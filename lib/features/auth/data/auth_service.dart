import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService({SupabaseClient? supabaseClient})
    : _supabaseClient = supabaseClient;

  final SupabaseClient? _supabaseClient;

  SupabaseClient get _client => _supabaseClient ?? Supabase.instance.client;

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() {
    return _client.auth.signOut();
  }

  Stream<Session?> authSessionChanges() async* {
    yield _client.auth.currentSession;
    yield* _client.auth.onAuthStateChange.map((event) => event.session);
  }
}
