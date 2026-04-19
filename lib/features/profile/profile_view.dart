// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Signed out')));
  }

  User? _currentUser() {
    try {
      return Supabase.instance.client.auth.currentUser;
    } catch (_) {
      return null;
    }
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

  @override
  Widget build(BuildContext context) {
    final user = _currentUser();
    final email = user?.email ?? 'local tester';
    final avatarLetter =
        email.isEmpty ? 'U' : email.substring(0, 1).toUpperCase();
    final joinedDate = _formatJoinedDate(user?.createdAt);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        CircleAvatar(
          radius: 40,
          backgroundColor: theme.primaryColor,
          child: Text(
            avatarLetter,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          email,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Joined $joinedDate',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else ...[
          TextFormField(
            controller: _wakeTimeController,
            decoration: const InputDecoration(
              labelText: 'Wake Time',
              hintText: '07:00',
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _sleepTimeController,
            decoration: const InputDecoration(
              labelText: 'Sleep Time',
              hintText: '23:00',
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isSaving ? null : _saveSettings,
            child:
                _isSaving
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('Save Settings'),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today),
            title: const Text('Google Calendar Status'),
            trailing: Text(
              _isCalendarConnected == true
                  ? 'Connected'
                  : _isCalendarConnected == false
                  ? 'Not Connected'
                  : 'Checking...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color:
                    _isCalendarConnected == true
                        ? Colors.green
                        : _isCalendarConnected == false
                        ? Colors.red
                        : Colors.black54,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => _signOut(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign Out'),
        ),
      ],
    );
  }
}
