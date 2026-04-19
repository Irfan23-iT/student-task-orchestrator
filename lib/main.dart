import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env_config.dart';
import 'features/auth/login_screen.dart';
import 'features/home/main_screen.dart';
import 'services/api_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  EnvConfig.initialize();

  runApp(const ProviderScope(child: _StudentTaskOrchestratorApp()));
}

class _StudentTaskOrchestratorApp extends StatelessWidget {
  const _StudentTaskOrchestratorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RakanStudent Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.light,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
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
          return const MainScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
