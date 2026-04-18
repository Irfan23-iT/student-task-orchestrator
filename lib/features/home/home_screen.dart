import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../auth/login_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();

    if (!context.mounted) {
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (context) => const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('RakanStudent Dashboard'),
        actions: [
          IconButton(
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: const Center(
        child: Text(
          'Welcome to RakanStudent!',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
