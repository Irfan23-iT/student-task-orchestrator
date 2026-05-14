import 'dart:io';

import 'package:flutter/material.dart';

import '../services/api_service.dart';

class AddCustomTaskScreen extends StatefulWidget {
  const AddCustomTaskScreen({super.key});

  @override
  State<AddCustomTaskScreen> createState() => _AddCustomTaskScreenState();
}

class _AddCustomTaskScreenState extends State<AddCustomTaskScreen> {
  final ApiService _apiService = ApiService();

  TextEditingController? _titleController;
  TextEditingController? _descriptionController;
  FocusNode? _titleFocusNode;
  FocusNode? _descriptionFocusNode;

  String _priority = 'Medium';
  DateTime? _dueDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descriptionController =
        TextEditingController()..addListener(_handleDescriptionChanged);
    _titleFocusNode = FocusNode();
    _descriptionFocusNode = FocusNode();
  }

  void _handleDescriptionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _descriptionController?.removeListener(_handleDescriptionChanged);
    _titleFocusNode?.unfocus();
    _descriptionFocusNode?.unfocus();

    final descriptionController = _descriptionController;
    if (descriptionController != null) {
      descriptionController.dispose();
      _descriptionController = null;
    }

    final titleController = _titleController;
    if (titleController != null) {
      titleController.dispose();
      _titleController = null;
    }

    final descriptionFocusNode = _descriptionFocusNode;
    if (descriptionFocusNode != null) {
      descriptionFocusNode.dispose();
      _descriptionFocusNode = null;
    }

    final titleFocusNode = _titleFocusNode;
    if (titleFocusNode != null) {
      titleFocusNode.dispose();
      _titleFocusNode = null;
    }

    super.dispose();
  }

  String _formatSelectedDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );

    if (!mounted || selected == null) {
      return;
    }

    setState(() {
      _dueDate = selected;
    });
  }

  Future<void> _saveTask() async {
    _descriptionController?.removeListener(_handleDescriptionChanged);
    _titleFocusNode?.unfocus();
    _descriptionFocusNode?.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    final title = _titleController?.text.trim() ?? '';
    final description = _descriptionController?.text.trim() ?? '';

    if (title.isEmpty) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter a task title.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _apiService.createTask({
        'title': title,
        'description': description.isEmpty ? null : description,
        'priorityLevel': _priority,
        'dueDate': _dueDate?.toIso8601String(),
        'status': 'Pending',
      });

      if (!mounted) {
        return;
      }

      final navigator = Navigator.of(context);
      navigator.pop(true);
    } on SocketException {
      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Cannot reach server right now. Please try again.'),
        ),
      );
      setState(() {
        _isSaving = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to create task: $error')),
      );
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final descriptionLength = _descriptionController?.text.length ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Add Custom Task'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            TextField(
              controller: _titleController,
              focusNode: _titleFocusNode,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _descriptionFocusNode?.requestFocus(),
              decoration: const InputDecoration(
                labelText: 'Task Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _descriptionController,
              focusNode: _descriptionFocusNode,
              minLines: 4,
              maxLines: 7,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                labelText: 'Description / Additional Info',
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
                counterText: '$descriptionLength/500',
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _priority,
              decoration: const InputDecoration(
                labelText: 'Priority',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Low', child: Text('Low')),
                DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                DropdownMenuItem(value: 'High', child: Text('High')),
              ],
              onChanged:
                  _isSaving
                      ? null
                      : (value) {
                        if (value == null) {
                          return;
                        }

                        setState(() {
                          _priority = value;
                        });
                      },
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _isSaving ? null : _pickDueDate,
              icon: const Icon(Icons.calendar_today_rounded),
              label: Text(
                _dueDate == null
                    ? 'Optional Due Date'
                    : _formatSelectedDate(_dueDate!),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (_dueDate != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed:
                    _isSaving
                        ? null
                        : () {
                          setState(() {
                            _dueDate = null;
                          });
                        },
                child: const Text('Clear due date'),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _isSaving ? null : _saveTask,
              icon:
                  _isSaving
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.save_rounded),
              label: const Text('Save Task'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF111827),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
