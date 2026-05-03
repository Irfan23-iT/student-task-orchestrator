// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/settings_model.dart';
import '../../services/api_service.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final ApiService _apiService = ApiService();
  final _wakeTimeController = TextEditingController();
  final _sleepTimeController = TextEditingController();

  String? _displayName;
  SettingsModel? _settings;
  bool? _isCalendarConnected;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadCalendarStatus();
    _runCodexSettingsTest();
  }

  @override
  void dispose() {
    _wakeTimeController.dispose();
    _sleepTimeController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _apiService.fetchProfileSettings();

      if (!mounted) {
        return;
      }

      setState(() {
        _settings = settings;
        _wakeTimeController.text = settings.wakeTime;
        _sleepTimeController.text = settings.sleepTime;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _settings = const SettingsModel(
          wakeTime: '07:00',
          sleepTime: '23:00',
          breakfastStart: '07:30',
          breakfastEnd: '08:30',
          lunchStart: '12:30',
          lunchEnd: '13:30',
          dinnerStart: '19:00',
          dinnerEnd: '20:00',
          transitBufferMinutes: 30,
        );
        _wakeTimeController.text = _settings!.wakeTime;
        _sleepTimeController.text = _settings!.sleepTime;
        _isLoading = false;
      });
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

  Future<void> _runCodexSettingsTest() async {
    try {
      print('--- CODEX SETTINGS TEST START ---');
      final settings = await _apiService.fetchProfileSettings();
      print(
        '--- CODEX SETTINGS FETCHED: Wake Time is ${settings.wakeTime} ---',
      );
    } catch (e) {
      print('--- CODEX SETTINGS TEST FAILED: $e ---');
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

  Future<void> _saveSettings() async {
    final currentSettings = _settings;
    if (currentSettings == null) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final updatedSettings = currentSettings.copyWith(
        wakeTime: _wakeTimeController.text.trim(),
        sleepTime: _sleepTimeController.text.trim(),
      );

      await _apiService.updateProfileSettings(updatedSettings);
      await _loadCalendarStatus();

      if (!mounted) {
        return;
      }

      setState(() {
        _settings = updatedSettings;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved')));
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to save settings: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _showEditNameDialog() async {
    final user = _currentUser();
    final controller = TextEditingController(
      text: _displayName ?? _resolveDisplayName(user),
    );
    var isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final navigator = Navigator.of(dialogContext);
        final messenger = ScaffoldMessenger.of(context);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Name'),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => navigator.pop(),
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

                            try {
                              setDialogState(() {
                                isSubmitting = true;
                              });
                              await _apiService.updateProfile(nextName);

                              if (!mounted) {
                                return;
                              }

                              setState(() {
                                _displayName = nextName;
                              });
                              navigator.pop();
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Profile name updated'),
                                ),
                              );
                            } catch (e) {
                              if (!mounted) {
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
                              if (context.mounted) {
                                setDialogState(() {
                                  isSubmitting = false;
                                });
                              }
                            }
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

  Widget _buildLabeledTimeRow({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.black,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _currentUser();
    final email = user?.email ?? 'local tester';
    final displayName = _displayName ?? _resolveDisplayName(user);
    final avatarLetter =
        displayName.isEmpty ? 'U' : displayName.substring(0, 1).toUpperCase();
    final joinedDate = _formatJoinedDate(user?.createdAt);
    final theme = Theme.of(context);
    final calendarConnected = _isCalendarConnected == true;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            Text(
              'Profile',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.black,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 74,
                    height: 74,
                    decoration: const BoxDecoration(
                      color: Color(0xFF7C3AED),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      avatarLetter,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
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
                                  color: Colors.black,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _showEditNameDialog,
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Edit name',
                              color: Colors.grey.shade600,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Joined $joinedDate',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
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
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sleep Schedule',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildLabeledTimeRow(
                    label: 'Wake Time',
                    value:
                        _wakeTimeController.text.trim().isEmpty
                            ? '07:00'
                            : _wakeTimeController.text.trim(),
                  ),
                  _buildLabeledTimeRow(
                    label: 'Sleep Time',
                    value:
                        _sleepTimeController.text.trim().isEmpty
                            ? '23:00'
                            : _sleepTimeController.text.trim(),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child:
                          _isSaving
                              ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Text(
                                'Save Settings',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Integrations',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.black,
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
                          color: const Color(0xFFE0F2FE),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.calendar_month_rounded,
                          color: Color(0xFF2563EB),
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
                                color: Colors.black,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              calendarConnected ? 'Connected' : 'Not Connected',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _syncCalendar,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEDE9FE),
                          foregroundColor: const Color(0xFF7C3AED),
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
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _signOut(context),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFFFEE2E2),
                  foregroundColor: const Color(0xFFDC2626),
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
            if (_isLoading) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
