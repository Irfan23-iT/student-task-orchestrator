// ignore_for_file: avoid_print

import 'package:flutter/material.dart';

import '../../models/workspace_model.dart';
import '../../services/api_service.dart';

class WorkspacesView extends StatefulWidget {
  const WorkspacesView({super.key});

  @override
  State<WorkspacesView> createState() => _WorkspacesViewState();
}

class _WorkspacesViewState extends State<WorkspacesView> {
  List<WorkspaceModel> _workspaces = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchWorkspaces();
    _runWorkspaceIntegrationTest();
  }

  Future<void> _fetchWorkspaces() async {
    try {
      final workspaces = await ApiService().fetchWorkspacesOverview();

      if (!mounted) {
        return;
      }

      setState(() {
        _workspaces = workspaces;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _workspaces = const [];
        _isLoading = false;
      });
    }
  }

  Future<void> _runWorkspaceIntegrationTest() async {
    try {
      print('--- CODEX WORKSPACE TEST START ---');
      final workspaces = await ApiService().fetchWorkspacesOverview();
      print(
        '--- CODEX WORKSPACE SUCCESS: Fetched ${workspaces.length} workspaces ---',
      );
    } catch (e) {
      print('--- CODEX WORKSPACE TEST FAILED: $e ---');
    }
  }

  Future<void> _runWorkspaceCreationTest() async {
    try {
      print('--- CODEX WORKSPACE CREATION TEST START ---');
      await ApiService().createWorkspace('FYP Team', 'Mobile Dev Capstone');
      final workspaces = await ApiService().fetchWorkspacesOverview();
      print(
        '--- CODEX WORKSPACE CREATION SUCCESS: Now have ${workspaces.length} workspaces ---',
      );
    } catch (e) {
      print('--- CODEX WORKSPACE CREATION TEST FAILED: $e ---');
    }
  }

  Future<void> _showWorkspaceDialog() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final inviteCodeController = TextEditingController();
    var isCreateMode = true;
    var isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final navigator = Navigator.of(dialogContext);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Workspace Actions'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(
                          value: true,
                          label: Text('Create Workspace'),
                        ),
                        ButtonSegment<bool>(
                          value: false,
                          label: Text('Join Workspace'),
                        ),
                      ],
                      selected: {isCreateMode},
                      onSelectionChanged: (selection) {
                        setDialogState(() {
                          isCreateMode = selection.first;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    if (isCreateMode) ...[
                      TextField(
                        controller: nameController,
                        autofocus: true,
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: inviteCodeController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Invite Code',
                        ),
                      ),
                    ],
                  ],
                ),
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
                            try {
                              setDialogState(() {
                                isSubmitting = true;
                              });

                              if (isCreateMode) {
                                final name = nameController.text.trim();
                                final description =
                                    descriptionController.text.trim();
                                if (name.isEmpty) {
                                  setDialogState(() {
                                    isSubmitting = false;
                                  });
                                  return;
                                }
                                await ApiService().createWorkspace(
                                  name,
                                  description,
                                );
                              } else {
                                final inviteCode =
                                    inviteCodeController.text.trim();
                                if (inviteCode.isEmpty) {
                                  setDialogState(() {
                                    isSubmitting = false;
                                  });
                                  return;
                                }
                                await ApiService().joinWorkspace(inviteCode);
                              }

                              await _fetchWorkspaces();

                              if (!context.mounted) {
                                return;
                              }

                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    isCreateMode
                                        ? 'Workspace created'
                                        : 'Workspace joined',
                                  ),
                                ),
                              );
                            } catch (e) {
                              if (!context.mounted) {
                                return;
                              }

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    isCreateMode
                                        ? 'Unable to create workspace: $e'
                                        : 'Unable to join workspace: $e',
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
                  child: Text(isCreateMode ? 'Create' : 'Join'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    descriptionController.dispose();
    inviteCodeController.dispose();
  }

  Future<void> _shareWorkspace(WorkspaceModel workspace) async {
    try {
      final inviteCode = await ApiService().getWorkspaceShareLink(workspace.id);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invite code: $inviteCode')));
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to load invite code: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Workspaces')),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
                itemCount: _workspaces.length,
                itemBuilder: (context, index) {
                  final workspace = _workspaces[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text(workspace.name),
                      subtitle: Text(
                        workspace.description.isEmpty
                            ? 'No description'
                            : workspace.description,
                      ),
                      trailing: IconButton(
                        onPressed: () => _shareWorkspace(workspace),
                        icon: const Icon(Icons.share_outlined),
                        tooltip: 'Share workspace',
                      ),
                    ),
                  );
                },
              ),
      floatingActionButton: GestureDetector(
        onLongPress: _runWorkspaceCreationTest,
        child: FloatingActionButton(
          heroTag: 'workspaces-create-fab',
          onPressed: _showWorkspaceDialog,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
