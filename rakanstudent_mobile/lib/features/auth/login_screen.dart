import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/api_service.dart';
import '../home/main_screen.dart';
import 'auth_layout_wrapper.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _apiService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) {
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(builder: (context) => const MainScreen()),
      );
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login failed. Please try again.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthViewPortLayout(
      title: 'Welcome back',
      subtitle: 'Sign in with your email and password to continue.',
      logo: const AuthLogoMark(icon: Icons.auto_awesome_rounded),
      formBody: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: authInputDecoration(
                context: context,
                hintText: 'Email',
                icon: Icons.alternate_email_rounded,
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) {
                  return 'Email is required';
                }

                if (!_emailPattern.hasMatch(email)) {
                  return 'Enter a valid email address';
                }

                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: authInputDecoration(
                context: context,
                hintText: 'Password',
                icon: Icons.lock_outline_rounded,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Password is required';
                }

                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }

                return null;
              },
            ),
          ],
        ),
      ),
      primaryActionButton: authGradientButton(
        label: 'Login',
        icon: Icons.arrow_forward_rounded,
        onPressed: _submit,
        isLoading: _isLoading,
      ),
      secondaryActionLink: TextButton(
        onPressed:
            _isLoading
                ? null
                : () async {
                  final didRegister = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute<bool>(
                      builder: (context) => const SignUpScreen(),
                    ),
                  );

                  if (!context.mounted || didRegister != true) {
                    return;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Registration successful!')),
                  );
                },
        child: const Text('Don\'t have an account? Sign Up'),
      ),
    );
  }
}
