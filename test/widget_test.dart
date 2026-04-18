import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:rakanstudent_mobile/app/app.dart';
import 'package:rakanstudent_mobile/features/auth/data/auth_service.dart';
import 'package:rakanstudent_mobile/features/auth/presentation/providers/auth_providers.dart';

class FakeAuthService extends AuthService {
  FakeAuthService();

  @override
  Stream<Session?> authSessionChanges() => Stream.value(null);

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}

void main() {
  testWidgets('App renders login screen shell', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWith((ref) => FakeAuthService()),
        ],
        child: const RakanStudentApp(),
      ),
    );

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
  });
}
