import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_error.dart';
import '../../../../core/errors/backend_error_parser.dart';
import '../../data/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final authSessionProvider = StreamProvider<Session?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authSessionChanges();
});

final loginControllerProvider =
    StateNotifierProvider<LoginController, LoginState>((ref) {
      return LoginController(authService: ref.watch(authServiceProvider));
    });

class LoginController extends StateNotifier<LoginState> {
  LoginController({required AuthService authService})
    : _authService = authService,
      super(const LoginState());

  final AuthService _authService;

  Future<void> signIn({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      await _authService.signInWithEmail(email: email, password: password);
      state = state.copyWith(isLoading: false, error: null);
    } catch (error, stackTrace) {
      state = state.copyWith(
        isLoading: false,
        error: BackendErrorParser.fromException(error, stackTrace: stackTrace),
      );
    }
  }
}

class LoginState {
  const LoginState({this.isLoading = false, this.error});

  final bool isLoading;
  final AppError? error;

  LoginState copyWith({bool? isLoading, AppError? error}) {
    return LoginState(isLoading: isLoading ?? this.isLoading, error: error);
  }
}
