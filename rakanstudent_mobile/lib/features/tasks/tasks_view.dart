// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/task_model.dart';
import '../../screens/add_custom_task_screen.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import '../gacha/gacha_controller.dart';
import 'voice_capture_widget.dart';

class TasksView extends ConsumerStatefulWidget {
  const TasksView({
    super.key,
    this.refreshSignal = 0,
    @visibleForTesting this.fetchOnInit = true,
    @visibleForTesting this.enableVoiceCapture = true,
    @visibleForTesting this.fetchTasks,
    @visibleForTesting this.deleteAllTasks,
  });

  final int refreshSignal;
  final bool fetchOnInit;
  final bool enableVoiceCapture;
  final Future<List<Map<String, dynamic>>> Function()? fetchTasks;
  final Future<void> Function()? deleteAllTasks;

  @override
  ConsumerState<TasksView> createState() => _TasksViewState();
}

enum _TaskCreationMode { manual, camera, flashcards, voice }

class _TasksViewState extends ConsumerState<TasksView> {
  static const int _maxImageBytes = 1024 * 1024;

  final ApiService _apiService = ApiService();
  final ImagePicker _imagePicker = ImagePicker();

  List<Task> _tasks = const [];
  bool _isLoading = true;
  bool _isSyncingCalendar = false;
  bool _isImportingDrive = false;
  bool _isScanningTaskImage = false;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.initialize();
    ApiService.taskMutationNotifier.addListener(_handleTaskMutation);
    if (widget.fetchOnInit) {
      _fetchTasks();
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    ApiService.taskMutationNotifier.removeListener(_handleTaskMutation);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TasksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshSignal != oldWidget.refreshSignal) {
      _fetchTasks();
    }
  }

  void _handleTaskMutation() {
    if (mounted) {
      _fetchTasks();
    }
  }

  void _showNetworkErrorSnackBar() {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cannot reach server right now. Please try again.'),
      ),
    );
  }

  Future<void> _fetchTasks() async {
    if (mounted) {
      setState(() {
        _tasks = const [];
        _isLoading = true;
      });
    }

    try {
      final response = await _loadTaskRows();
      final tasks = _dedupeTasks(
        response.map(Task.fromJson).toList(growable: false),
      );
      await NotificationService.instance.scheduleTaskReminders(tasks);

      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
    } on SocketException {
      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = const [];
        _isLoading = false;
      });
      _showNetworkErrorSnackBar();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = const [];
        _isLoading = false;
      });
    }
  }

  List<Task> _dedupeTasks(List<Task> fetchedTasks) {
    final uniqueTasks = <String, Task>{};

    for (final task in fetchedTasks) {
      final normalizedId = task.id.trim();
      final fallbackKey = [
        task.title.trim().toLowerCase(),
        task.dueDate?.toUtc().toIso8601String() ?? '',
        task.createdAt.toUtc().toIso8601String(),
      ].join('|');
      final key = normalizedId.isEmpty ? fallbackKey : normalizedId;

      uniqueTasks[key] = task;
    }

    return uniqueTasks.values.toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _loadTaskRows() {
    return widget.fetchTasks?.call() ?? _apiService.getTasks();
  }

  Future<void> _deleteAllTaskRows() {
    return widget.deleteAllTasks?.call() ?? _apiService.deleteAllTasks();
  }

  Future<void> _handleVoiceTaskCreated(AiChatResponse response) async {
    if (!mounted) {
      return;
    }

    await _fetchTasks();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(response.message)));
  }

  Future<void> _createReminderForTask(Task task) async {
    final now = DateTime.now();
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );

    if (!mounted) {
      return;
    }

    if (selectedDate == null) {
      return;
    }

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (!mounted) {
      return;
    }

    if (selectedTime == null) {
      return;
    }

    final reminderAt = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    if (reminderAt.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a future reminder time.')),
      );
      return;
    }

    final reminderAtIso = reminderAt.toUtc().toIso8601String();
    final messenger = ScaffoldMessenger.of(context);
    final reminderDateLabel = MaterialLocalizations.of(
      context,
    ).formatShortDate(reminderAt);
    final reminderTimeLabel = selectedTime.format(context);

    try {
      await _apiService.createReminder(
        task.id,
        'Reminder: ${task.title}',
        reminderAtIso,
        taskType: 'task',
      );

      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Reminder set for $reminderTimeLabel on $reminderDateLabel',
          ),
        ),
      );
    } on SocketException {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Cannot reach server right now. Please try again.'),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Unable to set reminder: $e')),
      );
    }
  }

  Future<void> _runReminderTest() async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      print('--- CODEX REMINDER TEST START ---');

      if (_tasks.isEmpty) {
        throw Exception('No fetched tasks are available for reminder testing.');
      }

      final task = _tasks.first;
      final oneHourFromNow =
          DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String();

      await _apiService.createReminder(
        task.id,
        'Reminder: ${task.title}',
        oneHourFromNow,
      );

      print('--- CODEX REMINDER SUCCESS: Reminder created for task ---');
    } on SocketException {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Cannot reach server right now. Please try again.'),
        ),
      );
    } catch (e) {
      print('--- CODEX REMINDER TEST FAILED: $e ---');
    }
  }

  Future<void> _toggleTaskCompletion({
    required Task task,
    required bool newValue,
  }) async {
    final previousTasks = _tasks;
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _tasks = _tasks
          .map(
            (entry) =>
                entry.id == task.id
                    ? entry.copyWith(isCompleted: newValue)
                    : entry,
          )
          .toList(growable: false);
    });

    try {
      await _apiService.updateSubTaskCompletion(
        id: task.id,
        completed: newValue,
      );

      ApiService.notifyTaskMutation();

      if (!mounted) {
        return;
      }

      if (newValue && !task.isCompleted) {
        final earnedToken =
            ref.read(gachaControllerProvider.notifier).incrementTask();
        if (earnedToken) {
          messenger.showSnackBar(
            const SnackBar(content: Text('+1 Gacha Token Earned')),
          );
        }
      }
    } on SocketException {
      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = previousTasks;
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Cannot reach server right now. Please try again.'),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = previousTasks;
      });

      messenger.showSnackBar(
        const SnackBar(content: Text('Unable to update the task right now.')),
      );
    }
  }

  Future<bool> _handleTaskSwipe(DismissDirection direction, Task task) async {
    final messenger = ScaffoldMessenger.of(context);

    if (direction == DismissDirection.startToEnd) {
      try {
        await _apiService.updateSubTaskCompletion(id: task.id, completed: true);

        if (!mounted) {
          return false;
        }

        ApiService.notifyTaskMutation();

        if (!task.isCompleted) {
          final earnedToken =
              ref.read(gachaControllerProvider.notifier).incrementTask();
          if (earnedToken) {
            messenger.showSnackBar(
              const SnackBar(content: Text('+1 Gacha Token Earned')),
            );
          }
        }

        setState(() {
          _tasks = _tasks
              .where((entry) => entry.id != task.id)
              .toList(growable: false);
        });

        messenger.showSnackBar(
          SnackBar(content: Text('"${task.title}" marked completed.')),
        );
        return true;
      } on SocketException {
        if (!mounted) {
          return false;
        }

        messenger.showSnackBar(
          const SnackBar(
            content: Text('Cannot reach server right now. Please try again.'),
          ),
        );
        return false;
      } catch (error) {
        if (!mounted) {
          return false;
        }

        messenger.showSnackBar(
          SnackBar(content: Text('Unable to complete task: $error')),
        );
        return false;
      }
    }

    try {
      await _apiService.deleteTask(task.id);

      if (!mounted) {
        return false;
      }

      setState(() {
        _tasks = _tasks
            .where((entry) => entry.id != task.id)
            .toList(growable: false);
      });

      messenger.showSnackBar(
        SnackBar(content: Text('"${task.title}" deleted.')),
      );
      return true;
    } on SocketException {
      if (!mounted) {
        return false;
      }

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Cannot reach server right now. Please try again.'),
        ),
      );
      return false;
    } catch (error) {
      if (!mounted) {
        return false;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Unable to delete task: $error')),
      );
      return false;
    }
  }

  Future<void> _deleteAllTasks() async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _deleteAllTaskRows();

      if (!mounted) {
        return;
      }

      await _fetchTasks();

      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        const SnackBar(content: Text('All tasks deleted')),
      );
    } on SocketException {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Cannot reach server right now. Please try again.'),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Unable to delete tasks: $e')),
      );
    }
  }

  Future<void> _syncTasksToCalendar() async {
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isSyncingCalendar = true;
    });

    messenger.showSnackBar(const SnackBar(content: Text('Syncing...')));

    try {
      await _apiService.syncTasksToCalendar();

      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        const SnackBar(content: Text('Tasks pushed to Google Calendar!')),
      );
    } on GoogleAccountNotLinkedException catch (error) {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on SocketException {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Cannot reach server right now. Please try again.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Unable to sync calendar: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingCalendar = false;
        });
      }
    }
  }

  Future<void> _importFromDrive() async {
    if (_isImportingDrive) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isImportingDrive = true;
    });

    try {
      final connected = await _apiService.fetchDriveStatus();
      if (!connected) {
        final shouldConnect = await _confirmDriveConnect();
        if (shouldConnect != true) {
          return;
        }

        final url = await _apiService.getDriveConnectUrl();
        final uri = Uri.parse(url);
        final launched =
            await canLaunchUrl(uri)
                ? await launchUrl(uri, mode: LaunchMode.externalApplication)
                : false;
        if (!mounted) return;

        messenger.showSnackBar(
          SnackBar(
            content: Text(
              launched
                  ? 'Finish Google Drive connection, then tap Import Drive again.'
                  : 'Unable to open Google Drive connection URL.',
            ),
          ),
        );
        return;
      }

      final files = await _apiService.listDriveFiles();
      if (!mounted) return;

      if (files.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'No supported Drive files found. Try a PDF, text file, or Google Doc.',
            ),
          ),
        );
        return;
      }

      final selectedFile = await _showDriveFilePicker(files);
      if (selectedFile == null) {
        return;
      }

      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  SizedBox(width: 18),
                  Expanded(
                    child: Text('Importing Drive document into tasks...'),
                  ),
                ],
              ),
            ),
      );

      DriveImportResultDto result;
      try {
        result = await _apiService.importDriveFile(selectedFile.id);
      } finally {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }

      await _fetchTasks();
      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.taskCount > 0
                ? 'Imported ${result.taskCount} task${result.taskCount == 1 ? '' : 's'} from Drive.'
                : result.message,
          ),
        ),
      );
    } on DriveNotConnectedException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on DriveIntegrationUnavailableException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on SocketException {
      if (!mounted) return;
      _showNetworkErrorSnackBar();
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to import from Drive: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isImportingDrive = false;
        });
      }
    }
  }

  Future<bool?> _confirmDriveConnect() {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Connect Google Drive'),
            content: const Text(
              'RakanStudent needs read-only Google Drive access to import PDFs, text files, and Google Docs into tasks.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Connect'),
              ),
            ],
          ),
    );
  }

  Future<DriveFileDto?> _showDriveFilePicker(List<DriveFileDto> files) {
    return showModalBottomSheet<DriveFileDto>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemBuilder: (context, index) {
                final file = files[index];
                return ListTile(
                  leading: const Icon(Icons.description_rounded),
                  title: Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(_driveFileTypeLabel(file.mimeType)),
                  onTap: () => Navigator.of(context).pop(file),
                );
              },
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemCount: files.length,
            ),
          ),
    );
  }

  String _driveFileTypeLabel(String mimeType) {
    if (mimeType == 'application/pdf') return 'PDF document';
    if (mimeType == 'application/vnd.google-apps.document') {
      return 'Google Doc';
    }
    if (mimeType.startsWith('text/')) return 'Text file';
    return 'Drive file';
  }

  int get _remainingTasksCount =>
      _tasks.where((task) => !task.isCompleted).length;

  Color _priorityBg(String? band) {
    switch ((band ?? 'medium').trim().toLowerCase()) {
      case 'high':
        return const Color(0xFFFEE2E2);
      case 'low':
        return const Color(0xFFDCFCE7);
      default:
        return const Color(0xFFFFEDD5);
    }
  }

  Color _priorityFg(String? band) {
    switch ((band ?? 'medium').trim().toLowerCase()) {
      case 'high':
        return const Color(0xFFDC2626);
      case 'low':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFFEA580C);
    }
  }

  String _priorityLabel(String? band) {
    final normalized = (band ?? 'medium').trim().toLowerCase();
    switch (normalized) {
      case 'high':
        return 'High Priority';
      case 'low':
        return 'Low Priority';
      default:
        return 'Medium Priority';
    }
  }

  Future<void> _openCustomTaskScreen() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final created = await navigator.push<bool>(
      MaterialPageRoute(builder: (context) => const AddCustomTaskScreen()),
    );

    if (!mounted) {
      return;
    }

    if (created == true) {
      await _fetchTasks();

      if (!mounted) {
        return;
      }

      messenger.showSnackBar(const SnackBar(content: Text('Task created')));
    }
  }

  String _mimeTypeForImage(XFile image) {
    final explicitMimeType = image.mimeType;
    if (explicitMimeType != null && explicitMimeType.startsWith('image/')) {
      return explicitMimeType;
    }

    final path = image.path.toLowerCase();
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.webp')) return 'image/webp';
    if (path.endsWith('.heic')) return 'image/heic';
    if (path.endsWith('.heif')) return 'image/heif';
    return 'image/jpeg';
  }

  Future<void> _scanTaskImage() async {
    if (_isScanningTaskImage) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    setState(() {
      _isScanningTaskImage = true;
    });

    var dialogOpen = false;
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 55,
        requestFullMetadata: false,
      );

      if (image == null) {
        return;
      }

      final bytes = await image.readAsBytes();
      if (bytes.lengthInBytes > _maxImageBytes) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Image is still over 1 MB. Please retake it closer.'),
          ),
        );
        return;
      }

      if (!mounted) return;
      showDialog<void>(
        context: rootNavigator.context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  SizedBox(width: 18),
                  Expanded(child: Text('Scanning image into tasks...')),
                ],
              ),
            ),
      );
      dialogOpen = true;

      final response = await _apiService.scanImageForTasks(
        imageBase64: base64Encode(bytes),
        mimeType: _mimeTypeForImage(image),
      );
      final createdItems = response['created'] as List<dynamic>? ?? const [];
      if (createdItems.isNotEmpty) {
        ApiService.notifyTaskMutation();
      }

      if (!mounted) return;
      if (dialogOpen) {
        rootNavigator.pop();
        dialogOpen = false;
      }
      await _fetchTasks();
      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            createdItems.isEmpty
                ? 'No academic tasks found in that image.'
                : 'Added ${createdItems.length} task group${createdItems.length == 1 ? '' : 's'} from camera.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      if (dialogOpen) {
        rootNavigator.pop();
        dialogOpen = false;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to scan image: $error')),
      );
    } finally {
      if (dialogOpen && mounted) {
        rootNavigator.pop();
      }
      if (mounted) {
        setState(() {
          _isScanningTaskImage = false;
        });
      }
    }
  }

  Future<void> _generateFlashcardsFromCamera() async {
    if (_isScanningTaskImage) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    setState(() {
      _isScanningTaskImage = true;
    });

    var dialogOpen = false;
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 55,
        requestFullMetadata: false,
      );

      if (image == null) {
        return;
      }

      final bytes = await image.readAsBytes();
      if (bytes.lengthInBytes > _maxImageBytes) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Image is still over 1 MB. Please retake it closer.'),
          ),
        );
        return;
      }

      if (!mounted) return;
      showDialog<void>(
        context: rootNavigator.context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  SizedBox(width: 18),
                  Expanded(child: Text('Generating flashcards...')),
                ],
              ),
            ),
      );
      dialogOpen = true;

      final flashcards = await _apiService.generateFlashcardsFromImage(
        imageBase64: base64Encode(bytes),
        mimeType: _mimeTypeForImage(image),
      );

      if (!mounted) return;
      if (dialogOpen) {
        rootNavigator.pop();
        dialogOpen = false;
      }

      if (flashcards.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No flashcards were generated.')),
        );
        return;
      }

      await _showFlashcardsDialog(flashcards);
    } catch (error) {
      if (!mounted) return;
      if (dialogOpen) {
        rootNavigator.pop();
        dialogOpen = false;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to generate flashcards: $error')),
      );
    } finally {
      if (dialogOpen && mounted) {
        rootNavigator.pop();
      }
      if (mounted) {
        setState(() {
          _isScanningTaskImage = false;
        });
      }
    }
  }

  Future<void> _showFlashcardsDialog(List<FlashcardDto> flashcards) {
    return showDialog<void>(
      context: context,
      builder: (context) => _FlashcardsDialog(flashcards: flashcards),
    );
  }

  Future<void> _openVoiceTaskSheet() async {
    if (!widget.enableVoiceCapture) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                12,
                24,
                24 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Voice to Task',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Say what you need to do. RakanStudent will turn it into a task.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  VoiceCaptureWidget(
                    onTaskCreated: (response) {
                      unawaited(_handleVoiceTaskCreated(response));
                    },
                    onClose: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Future<void> _showTaskCreationOptions() async {
    final selectedMode = await showModalBottomSheet<_TaskCreationMode>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Create Task',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Choose the fastest way to add what you need to do.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  _TaskCreationOptionTile(
                    icon: Icons.edit_note_rounded,
                    title: 'Add manually',
                    subtitle: 'Type a custom task with details.',
                    onTap: () {
                      Navigator.of(context).pop(_TaskCreationMode.manual);
                    },
                  ),
                  _TaskCreationOptionTile(
                    icon: Icons.camera_alt_rounded,
                    title: 'Scan Syllabus',
                    subtitle: 'Scan a worksheet, notes, or assignment page.',
                    onTap: () {
                      Navigator.of(context).pop(_TaskCreationMode.camera);
                    },
                  ),
                  _TaskCreationOptionTile(
                    icon: Icons.style_rounded,
                    title: 'Generate Flashcards',
                    subtitle: 'Turn handwritten study notes into swipe cards.',
                    onTap: () {
                      Navigator.of(context).pop(_TaskCreationMode.flashcards);
                    },
                  ),
                  _TaskCreationOptionTile(
                    icon: Icons.mic_rounded,
                    title: 'Voice to task',
                    subtitle: 'Speak a task and let AI structure it.',
                    onTap:
                        widget.enableVoiceCapture
                            ? () {
                              Navigator.of(
                                context,
                              ).pop(_TaskCreationMode.voice);
                            }
                            : null,
                  ),
                ],
              ),
            ),
          ),
    );

    if (!mounted || selectedMode == null) {
      return;
    }

    switch (selectedMode) {
      case _TaskCreationMode.manual:
        unawaited(_openCustomTaskScreen());
      case _TaskCreationMode.camera:
        unawaited(_scanTaskImage());
      case _TaskCreationMode.flashcards:
        unawaited(_generateFlashcardsFromCamera());
      case _TaskCreationMode.voice:
        unawaited(_openVoiceTaskSheet());
    }
  }

  Widget _buildTaskChip({
    required String label,
    required Color background,
    required Color foreground,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(BuildContext context, Task task) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
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

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: shadow,
      ),
      child: Dismissible(
        key: Key(task.id),
        direction: DismissDirection.horizontal,
        background: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: Colors.green.shade600,
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: const Icon(Icons.check_circle_rounded, color: Colors.white),
        ),
        secondaryBackground: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: const Icon(Icons.delete_rounded, color: Colors.white),
        ),
        confirmDismiss: (direction) => _handleTaskSwipe(direction, task),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                value: task.isCompleted,
                shape: const CircleBorder(),
                activeColor: const Color(0xFF8B5CF6),
                side: BorderSide(color: Colors.grey.shade400, width: 1.6),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (value) {
                  _toggleTaskCompletion(task: task, newValue: value ?? false);
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildTaskChip(
                          label: _priorityLabel(task.priorityBand),
                          background: _priorityBg(task.priorityBand),
                          foreground: _priorityFg(task.priorityBand),
                        ),
                        _buildTaskChip(
                          label:
                              task.estimatedMinutes != null &&
                                      task.estimatedMinutes! > 0
                                  ? '${task.estimatedMinutes} min'
                                  : 'Duration unknown',
                          background: const Color(0xFFF3F4F6),
                          foreground: Colors.grey.shade700,
                          icon: Icons.schedule_rounded,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: () => _createReminderForTask(task),
                onLongPress: _runReminderTest,
                icon: const Icon(Icons.notifications_none_rounded),
                color: const Color(0xFFF59E0B),
                tooltip: 'Set reminder',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskOverviewCard({
    required int remainingTasks,
    required int completedTasks,
    required List<BoxShadow> shadow,
  }) {
    final totalTasks = _tasks.length;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF111827), Color(0xFF4C1D95)],
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Today’s Focus',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      remainingTasks == 0
                          ? 'All clear'
                          : '$remainingTasks task${remainingTasks == 1 ? '' : 's'} left',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      totalTasks == 0
                          ? 'Use Add Task to capture your first task.'
                          : '$completedTasks completed out of $totalTasks total tasks.',
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.task_alt_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _showTaskCreationOptions,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Task'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF111827),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUtilityActions() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: (MediaQuery.sizeOf(context).width - 52) / 2,
          child: _TaskUtilityButton(
            icon: _isSyncingCalendar ? null : Icons.sync_rounded,
            label: _isSyncingCalendar ? 'Syncing...' : 'Sync Calendar',
            foreground: const Color(0xFF7C3AED),
            background: const Color(0xFFF3E8FF),
            onPressed: _isSyncingCalendar ? null : _syncTasksToCalendar,
            busy: _isSyncingCalendar,
          ),
        ),
        SizedBox(
          width: (MediaQuery.sizeOf(context).width - 52) / 2,
          child: _TaskUtilityButton(
            icon: _isImportingDrive ? null : Icons.cloud_download_rounded,
            label: _isImportingDrive ? 'Importing...' : 'Import Drive',
            foreground: const Color(0xFF2563EB),
            background: const Color(0xFFDBEAFE),
            onPressed: _isImportingDrive ? null : _importFromDrive,
            busy: _isImportingDrive,
          ),
        ),
        SizedBox(
          width: (MediaQuery.sizeOf(context).width - 52) / 2,
          child: _TaskUtilityButton(
            icon: Icons.delete_sweep_rounded,
            label: 'Clear Tasks',
            foreground: const Color(0xFFDC2626),
            background: const Color(0xFFFEE2E2),
            onPressed: _deleteAllTasks,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final remainingTasks = _remainingTasksCount;
    final completedTasks = _tasks.length - remainingTasks;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF4F0FF);
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final subTextColor = isDark ? Colors.grey[400] : Colors.grey[600];
    final shadow =
        isDark
            ? <BoxShadow>[]
            : [
              BoxShadow(
                color: const Color(0xFF4C1D95).withValues(alpha: 0.08),
                blurRadius: 30,
                offset: const Offset(0, 14),
              ),
            ];

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _fetchTasks,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
            children: [
              _buildTaskOverviewCard(
                remainingTasks: remainingTasks,
                completedTasks: completedTasks,
                shadow: shadow,
              ),
              const SizedBox(height: 14),
              _buildUtilityActions(),
              const SizedBox(height: 24),
              Row(
                children: [
                  Text(
                    'Task Queue',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_tasks.length} total',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: subTextColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'No tasks yet.',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: subTextColor),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _tasks.length,
                  itemBuilder: (context, index) {
                    return _buildTaskCard(context, _tasks[index]);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskCreationOptionTile extends StatelessWidget {
  const _TaskCreationOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: enabled ? 0.65 : 0.35,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color:
                            enabled
                                ? theme.colorScheme.onSurface
                                : theme.disabledColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            enabled
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.disabledColor,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color:
                    enabled
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.disabledColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlashcardsDialog extends StatefulWidget {
  const _FlashcardsDialog({required this.flashcards});

  final List<FlashcardDto> flashcards;

  @override
  State<_FlashcardsDialog> createState() => _FlashcardsDialogState();
}

class _FlashcardsDialogState extends State<_FlashcardsDialog> {
  final PageController _pageController = PageController(viewportFraction: 0.9);
  int _currentIndex = 0;

  bool get _canGoBack => _currentIndex > 0;
  bool get _canGoForward => _currentIndex < widget.flashcards.length - 1;

  void _goToCard(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToPreviousCard() {
    if (_canGoBack) {
      _goToCard(_currentIndex - 1);
    }
  }

  void _goToNextCard() {
    if (_canGoForward) {
      _goToCard(_currentIndex + 1);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog.fullscreen(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Generated Flashcards',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Swipe through the cards from your notes or use the arrows.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: widget.flashcards.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    final flashcard = widget.flashcards[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF111827), Color(0xFF4C1D95)],
                          ),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF4C1D95,
                              ).withValues(alpha: 0.28),
                              blurRadius: 30,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(26),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Card ${index + 1} of ${widget.flashcards.length}',
                                style: const TextStyle(
                                  color: Color(0xFFDDD6FE),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 28),
                              Text(
                                flashcard.front,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.12),
                                  ),
                                ),
                                child: Text(
                                  flashcard.back,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    height: 1.4,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: _canGoBack ? _goToPreviousCard : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                    tooltip: 'Previous card',
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(widget.flashcards.length, (
                        index,
                      ) {
                        final selected = index == _currentIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: selected ? 22 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color:
                                selected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        );
                      }),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _canGoForward ? _goToNextCard : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: 'Next card',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskUtilityButton extends StatelessWidget {
  const _TaskUtilityButton({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
    required this.onPressed,
    this.busy = false,
  });

  final IconData? icon;
  final String label;
  final Color foreground;
  final Color background;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: background,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foreground,
              ),
            )
          else if (icon != null)
            Icon(icon, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
