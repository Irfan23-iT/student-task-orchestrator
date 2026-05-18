import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme_provider.dart';
import '../core/widgets/app_error_banner.dart';
import '../features/auth/presentation/widgets/auth_gate.dart';
import 'theme/app_theme.dart';

class RakanStudentApp extends ConsumerWidget {
  const RakanStudentApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'RakanStudent Mobile',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const AppErrorBanner(child: AuthGate()),
    );
  }
}
