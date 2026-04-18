import 'package:flutter/material.dart';

class AppErrorBanner extends StatelessWidget {
  const AppErrorBanner({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
