import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/theme/app_theme.dart';
import 'core/auth_gate.dart';
import 'core/config/env_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  EnvConfig.initialize();

  runApp(
    const ProviderScope(
      child: _StudentTaskOrchestratorApp(),
    ),
  );
}

class _StudentTaskOrchestratorApp extends StatelessWidget {
  const _StudentTaskOrchestratorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RakanStudent Mobile',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AuthGate(),
    );
  }
}
