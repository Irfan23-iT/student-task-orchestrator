import 'package:flutter/material.dart';

import '../core/widgets/app_error_banner.dart';
import '../features/auth/presentation/widgets/auth_gate.dart';
import 'theme/app_theme.dart';

class RakanStudentApp extends StatelessWidget {
  const RakanStudentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RakanStudent Mobile',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const AppErrorBanner(child: AuthGate()),
    );
  }
}
