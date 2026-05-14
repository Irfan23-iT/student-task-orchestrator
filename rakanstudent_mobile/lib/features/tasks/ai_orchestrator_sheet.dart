import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class AIOrchestratorSheet extends StatefulWidget {
  const AIOrchestratorSheet({super.key});

  @override
  State<AIOrchestratorSheet> createState() => _AIOrchestratorSheetState();
}

class _AIOrchestratorSheetState extends State<AIOrchestratorSheet> {
  final ApiService _apiService = ApiService();
  final TextEditingController _goalController = TextEditingController();

  List<dynamic> _generatedTasks = const [];
  bool _isGenerating = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    debugPrint('--- AI ORCHESTRATOR WIRED ---');
  }

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  Future<void> _generateTasks() async {
    final goal = _goalController.text.trim();
    if (goal.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a goal before generating tasks.')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      final tasks = await _apiService.orchestrateGoal(goal);

      if (!mounted) {
        return;
      }

      setState(() {
        _generatedTasks = tasks;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to generate tasks: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _saveAllTasks() async {
    final goal = _goalController.text.trim();
    if (goal.isEmpty || _generatedTasks.isEmpty) {
      debugPrint(
        '[AIOrchestratorSheet] Save aborted: goal empty=${goal.isEmpty}, generatedTasks=${_generatedTasks.length}',
      );
      return;
    }

    debugPrint(
      '[AIOrchestratorSheet] Save requested for goal="$goal" with ${_generatedTasks.length} generated tasks.',
    );

    setState(() {
      _isSaving = true;
    });

    try {
      debugPrint('[AIOrchestratorSheet] Calling saveOrchestratedTasks...');
      await _apiService.saveOrchestratedTasks(
        goal: goal,
        tasks: _generatedTasks,
      );
      debugPrint('[AIOrchestratorSheet] saveOrchestratedTasks completed.');

      if (!mounted) {
        return;
      }

      Navigator.pop(context, true);
    } catch (error) {
      debugPrint('[AIOrchestratorSheet] Save failed: $error');
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to save tasks: $error')));
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
    final viewInsets = MediaQuery.of(context).viewInsets;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'AI Orchestrator',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _goalController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Goal',
                hintText: 'Plan my revision for next week\'s calculus quiz',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isGenerating ? null : _generateTasks,
              icon:
                  _isGenerating
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.auto_awesome_rounded),
              label: Text(_isGenerating ? 'Generating...' : 'Generate Tasks'),
            ),
            if (_generatedTasks.isNotEmpty) ...[
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _generatedTasks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final task =
                        _generatedTasks[index] as Map<dynamic, dynamic>;
                    final title = (task['title'] ?? '').toString();
                    final description = (task['description'] ?? '').toString();
                    final duration =
                        (task['duration_minutes'] ?? '').toString();
                    final priority = (task['priority'] ?? '').toString();

                    return Card(
                      child: ListTile(
                        title: Text(title),
                        subtitle: Text(
                          '$description\n$duration min • $priority priority',
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _isSaving ? null : _saveAllTasks,
                icon:
                    _isSaving
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.save_alt_rounded),
                label: Text(_isSaving ? 'Saving...' : 'Save All to Database'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
