// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme_provider.dart';
import '../gacha/gacha_view.dart';
import '../../services/api_service.dart';

class ProfileView extends ConsumerStatefulWidget {
  const ProfileView({super.key});

  @override
  ConsumerState<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<ProfileView> {
  final ApiService _apiService = ApiService();

  bool? _isCalendarConnected;

  @override
  void initState() {
    super.initState();
    ApiService.profileNameNotifier.addListener(_handleProfileNameChanged);
    _loadCalendarStatus();
    _loadProfileName();
  }

  @override
  void dispose() {
    ApiService.profileNameNotifier.removeListener(_handleProfileNameChanged);
    super.dispose();
  }

  void _handleProfileNameChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadProfileName() async {
    try {
      await _apiService.fetchCurrentProfileName();
    } catch (error) {
      debugPrint('[ProfileView] Profile name fetch failed: $error');
    }
  }

  Future<void> _loadCalendarStatus() async {
    try {
      final isConnected = await _apiService.fetchCalendarStatus();

      if (!mounted) {
        return;
      }

      setState(() {
        _isCalendarConnected = isConnected;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isCalendarConnected = false;
      });
    }
  }

  Future<void> _signOut(BuildContext context) async {
    await _apiService.logout();
    print('DEBUG: User signed out successfully.');

    if (!context.mounted) {
      return;
    }

    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil('/login', (Route<dynamic> route) => false);
  }

  User? _currentUser() {
    try {
      return Supabase.instance.client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  String _resolveDisplayName(User? user) {
    final metadata = user?.userMetadata;
    final fullName = metadata?['full_name']?.toString().trim() ?? '';
    if (fullName.isNotEmpty) {
      return fullName;
    }

    final name = metadata?['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) {
      return name;
    }

    final email = user?.email?.trim() ?? '';
    if (email.isNotEmpty) {
      return email.split('@').first;
    }

    return 'Student';
  }

  String _formatJoinedDate(Object? rawCreatedAt) {
    final parsedDate = DateTime.tryParse('${rawCreatedAt ?? ''}');
    if (parsedDate == null) {
      return 'Unavailable';
    }

    const monthNames = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${monthNames[parsedDate.month - 1]} ${parsedDate.day}, ${parsedDate.year}';
  }

  Future<void> _showEditNameDialog() async {
    final user = _currentUser();
    final controller = TextEditingController(
      text: ApiService.profileNameNotifier.value ?? _resolveDisplayName(user),
    );
    var isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContentContext, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Name'),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSubmitting
                          ? null
                          : () => Navigator.of(dialogContentContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed:
                      isSubmitting
                          ? null
                          : () async {
                            final nextName = controller.text.trim();
                            if (nextName.isEmpty) {
                              return;
                            }

                            FocusManager.instance.primaryFocus?.unfocus();

                            setDialogState(() {
                              isSubmitting = true;
                            });

                            WidgetsBinding.instance.addPostFrameCallback((
                              _,
                            ) async {
                              if (!mounted || !dialogContentContext.mounted) {
                                return;
                              }

                              final messenger = ScaffoldMessenger.of(
                                dialogContentContext,
                              );
                              final navigator = Navigator.of(
                                dialogContentContext,
                              );
                              var didCloseDialog = false;

                              try {
                                await _apiService.updateProfile(nextName);

                                if (!mounted ||
                                    !dialogContentContext.mounted ||
                                    !navigator.mounted ||
                                    !messenger.mounted) {
                                  return;
                                }

                                navigator.pop();
                                didCloseDialog = true;

                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Profile name updated'),
                                  ),
                                );
                              } catch (e) {
                                if (!mounted ||
                                    !dialogContentContext.mounted ||
                                    !messenger.mounted) {
                                  return;
                                }

                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Unable to update profile name: $e',
                                    ),
                                  ),
                                );
                              } finally {
                                if (!didCloseDialog &&
                                    dialogContentContext.mounted) {
                                  setDialogState(() {
                                    isSubmitting = false;
                                  });
                                }
                              }
                            });
                          },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  Future<void> _syncCalendar() async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Syncing...')));

    try {
      await _apiService.syncCalendar();
      if (!mounted) return;

      await _loadCalendarStatus();
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Calendar sync started')));
    } on CalendarNotConnectedException catch (error) {
      debugPrint(
        '[ProfileView] Calendar sync requires connection: ${error.toString()}',
      );
      if (!mounted) return;

      await _showCalendarConnectDialog(error.message);
      if (!mounted) return;
    } catch (e) {
      debugPrint('[ProfileView] Calendar sync failed: ${e.toString()}');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to sync calendar: ${e.toString()}')),
      );
    }
  }

  Future<void> _showCalendarConnectDialog(String message) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Connect Google Calendar'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();

                try {
                  final url = await _apiService.getCalendarConnectUrl();
                  if (!mounted) return;

                  final uri = Uri.parse(url);
                  final launched =
                      await canLaunchUrl(uri)
                          ? await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          )
                          : false;
                  if (!mounted) return;

                  if (!launched) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Unable to open the browser. Please try again.',
                        ),
                      ),
                    );
                  }
                } catch (error) {
                  debugPrint(
                    '[ProfileView] Calendar connect launch failed: ${error.toString()}',
                  );
                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Unable to get calendar connect URL: ${error.toString()}',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isDarkMode = themeMode == ThemeMode.dark;
    final user = _currentUser();
    final email = user?.email ?? 'local tester';
    final profileName = ApiService.profileNameNotifier.value;
    final displayName =
        profileName?.trim().isNotEmpty == true
            ? profileName!.trim()
            : _resolveDisplayName(user);
    final avatarLetter =
        displayName.isEmpty ? 'U' : displayName.substring(0, 1).toUpperCase();
    final joinedDate = _formatJoinedDate(user?.createdAt);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final calendarConnected = _isCalendarConnected == true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF5F5F7);
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.grey[400] : Colors.grey[600];
    final shadow =
        isDark
            ? <BoxShadow>[]
            : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ];

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
          children: [
            Text(
              'Profile',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(32),
                boxShadow: shadow,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      avatarLetter,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: textColor,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _showEditNameDialog,
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Edit name',
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: subTextColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Joined $joinedDate',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: subTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(32),
                boxShadow: shadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Integrations',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.calendar_month_rounded,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Google Calendar',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: textColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              calendarConnected ? 'Connected' : 'Not Connected',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: subTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _syncCalendar,
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.primaryContainer,
                          foregroundColor: colorScheme.onPrimaryContainer,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          elevation: 0,
                        ),
                        child: Text(calendarConnected ? 'Sync' : 'Connect'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(32),
                boxShadow: shadow,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => const GachaView(),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.redeem_rounded,
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rewards & Loot',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: textColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Enter the Gacha Machine',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: subTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(32),
                boxShadow: shadow,
              ),
              child: SwitchListTile(
                value: isDarkMode,
                onChanged: (isDarkMode) {
                  ref
                      .read(themeModeProvider.notifier)
                      .setThemeMode(
                        isDarkMode ? ThemeMode.dark : ThemeMode.light,
                      );
                },
                secondary: Icon(
                  isDarkMode
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded,
                  color: colorScheme.primary,
                ),
                title: Text(
                  isDarkMode ? 'Dark Mode' : 'Light Mode',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  isDarkMode
                      ? 'Midnight neon interface'
                      : 'Bright study interface',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: subTextColor,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 6,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _signOut(context),
                style: OutlinedButton.styleFrom(
                  backgroundColor: colorScheme.errorContainer,
                  foregroundColor: colorScheme.onErrorContainer,
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                icon: const Icon(Icons.logout_rounded),
                label: const Text(
                  'Sign Out',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
