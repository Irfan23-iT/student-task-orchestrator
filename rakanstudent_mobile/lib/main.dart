import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_theme.dart';
import 'core/config/env_config.dart';
import 'core/theme_provider.dart';
import 'features/auth/login_screen.dart';
import 'features/home/main_screen.dart';
import 'services/api_service.dart';
import 'services/reminder_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  await EnvConfig.initialize();
  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    anonKey: EnvConfig.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: _StudentTaskOrchestratorApp()));
}

class _StudentTaskOrchestratorApp extends ConsumerWidget {
  const _StudentTaskOrchestratorApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'RakanStudent Mobile',
      debugShowCheckedModeBanner: false,
      routes: {'/login': (_) => const LoginScreen()},
      themeMode: themeMode,
      theme: RakanAppTheme.lightTheme,
      darkTheme: RakanAppTheme.darkTheme,
      home: const _StartupGate(),
    );
  }
}

class _StartupGate extends StatelessWidget {
  const _StartupGate();

  static final ApiService _apiService = ApiService();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _apiService.isLoggedIn(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data ?? false) {
          ReminderSyncService.instance.startPeriodicSync();
          return const MainScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
