import 'package:flutter/material.dart';

import '../errors/app_error.dart';

class AsyncStateView extends StatelessWidget {
  const AsyncStateView.loading({super.key, this.message})
    : variant = AsyncStateVariant.loading,
      onRetry = null,
      error = null,
      title = null,
      icon = null;

  const AsyncStateView.empty({
    required this.title,
    required this.message,
    this.icon,
    super.key,
  }) : variant = AsyncStateVariant.empty,
       onRetry = null,
       error = null;

  const AsyncStateView.error({
    required this.error,
    required this.onRetry,
    super.key,
  }) : variant = AsyncStateVariant.error,
       title = null,
       message = null,
       icon = null;

  final AsyncStateVariant variant;
  final String? title;
  final String? message;
  final IconData? icon;
  final AppError? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    switch (variant) {
      case AsyncStateVariant.loading:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              if (message != null) ...[
                const SizedBox(height: 16),
                Text(message!),
              ],
            ],
          ),
        );
      case AsyncStateVariant.empty:
        return _CardShell(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon ?? Icons.inbox_rounded,
                size: 32,
                color: const Color(0xFF6A7280),
              ),
              const SizedBox(height: 12),
              Text(
                title!,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF6A7280),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      case AsyncStateVariant.error:
        return _CardShell(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 32,
                color: Color(0xFFFF3B30),
              ),
              const SizedBox(height: 12),
              Text(
                error!.userMessage,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              if (error!.requestId != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Request ID: ${error!.requestId}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6A7280),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        );
    }
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Padding(padding: const EdgeInsets.all(24), child: child),
        ),
      ),
    );
  }
}

enum AsyncStateVariant { loading, empty, error }
