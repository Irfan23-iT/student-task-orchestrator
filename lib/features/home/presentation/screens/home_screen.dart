import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../schedule/data/models/fixed_class.dart';
import '../../../schedule/data/models/schedule_overview.dart';
import '../../../schedule/presentation/providers/schedule_providers.dart';
import '../../../tasks/data/models/task_row.dart';
import '../../../tasks/presentation/providers/tasks_providers.dart';
import '../../../workspaces/data/models/workspace_overview.dart';
import '../../../workspaces/presentation/providers/workspaces_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({required this.session, super.key});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = session.user.email ?? 'student';

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('RakanStudent'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () async {
              await ref.read(authServiceProvider).signOut();
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(taskRowsProvider);
          ref.invalidate(scheduleOverviewProvider);
          ref.invalidate(workspaceOverviewProvider);
          await Future.wait([
            ref.read(taskRowsProvider.future),
            ref.read(scheduleOverviewProvider.future),
            ref.read(workspaceOverviewProvider.future),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Welcome, $email',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1D1D1F),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Here is your first live mobile feature: task rows from the backend.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6A7280)),
            ),
            const SizedBox(height: 24),
            _TasksSection(session: session),
            const SizedBox(height: 24),
            const _ScheduleSection(),
            const SizedBox(height: 16),
            const _WorkspacesSection(),
          ],
        ),
      ),
    );
  }
}

class _WorkspacesSection extends ConsumerWidget {
  const _WorkspacesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceOverviewAsync = ref.watch(workspaceOverviewProvider);

    return workspaceOverviewAsync.when(
      loading:
          () => const SizedBox(
            height: 220,
            child: AsyncStateView.loading(message: 'Loading workspaces...'),
          ),
      error:
          (error, stackTrace) => SizedBox(
            height: 240,
            child: AsyncStateView.error(
              error:
                  error is AppError
                      ? error
                      : AppError(
                        message: 'Failed to load workspaces',
                        details: error.toString(),
                      ),
              onRetry: () => ref.invalidate(workspaceOverviewProvider),
            ),
          ),
      data: (overview) {
        if (overview.workspaces.isEmpty) {
          return const SizedBox(
            height: 220,
            child: AsyncStateView.empty(
              title: 'No workspaces yet',
              message:
                  'You are authenticated, but there are no workspaces linked to this account yet.',
              icon: Icons.groups_rounded,
            ),
          );
        }

        return _WorkspaceOverviewCard(overview: overview);
      },
    );
  }
}

class _ScheduleSection extends ConsumerWidget {
  const _ScheduleSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(scheduleOverviewProvider);

    return scheduleAsync.when(
      loading:
          () => const SizedBox(
            height: 220,
            child: AsyncStateView.loading(
              message: 'Loading schedule settings...',
            ),
          ),
      error:
          (error, stackTrace) => SizedBox(
            height: 240,
            child: AsyncStateView.error(
              error:
                  error is AppError
                      ? error
                      : AppError(
                        message: 'Failed to load schedule overview',
                        details: error.toString(),
                      ),
              onRetry: () => ref.invalidate(scheduleOverviewProvider),
            ),
          ),
      data: (overview) => _ScheduleOverviewCard(overview: overview),
    );
  }
}

class _TasksSection extends ConsumerWidget {
  const _TasksSection({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskRowsAsync = ref.watch(taskRowsProvider);

    return taskRowsAsync.when(
      loading:
          () => const SizedBox(
            height: 220,
            child: AsyncStateView.loading(message: 'Loading task rows...'),
          ),
      error:
          (error, stackTrace) => SizedBox(
            height: 240,
            child: AsyncStateView.error(
              error:
                  error is AppError
                      ? error
                      : AppError(
                        message: 'Failed to load tasks',
                        details: error.toString(),
                      ),
              onRetry: () => ref.invalidate(taskRowsProvider),
            ),
          ),
      data: (rows) {
        if (rows.isEmpty) {
          return const SizedBox(
            height: 220,
            child: AsyncStateView.empty(
              title: 'No tasks yet',
              message:
                  'Your backend is connected, but there are no task rows for this account yet.',
              icon: Icons.task_alt_rounded,
            ),
          );
        }

        return _TaskRowsCard(taskRows: rows, userEmail: session.user.email);
      },
    );
  }
}

class _TaskRowsCard extends StatelessWidget {
  const _TaskRowsCard({required this.taskRows, required this.userEmail});

  final List<TaskRow> taskRows;
  final String? userEmail;

  @override
  Widget build(BuildContext context) {
    final totalMinutes = taskRows.fold<int>(
      0,
      (sum, row) => sum + (row.estimatedMinutes ?? 0),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
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
                      Text(
                        'Task Rows',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${taskRows.length} tasks | $totalMinutes min total${userEmail == null ? '' : ' | $userEmail'}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF6A7280),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x142F628F),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Live',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            for (var index = 0; index < taskRows.length; index++) ...[
              _TaskRowTile(taskRow: taskRows[index]),
              if (index != taskRows.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _TaskRowTile extends StatelessWidget {
  const _TaskRowTile({required this.taskRow});

  final TaskRow taskRow;

  @override
  Widget build(BuildContext context) {
    final priorityBand = taskRow.priorityBand?.toUpperCase() ?? 'NORMAL';
    final estimatedMinutes = taskRow.estimatedMinutes;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  taskRow.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1D1D1F),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _MetaChip(
                label: priorityBand,
                foreground: AppTheme.primary,
                background: const Color(0x142F628F),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(
                label: taskRow.status,
                foreground: const Color(0xFF3D8C61),
                background: const Color(0x143D8C61),
              ),
              _MetaChip(
                label:
                    estimatedMinutes == null
                        ? 'No estimate'
                        : '$estimatedMinutes min',
                foreground: const Color(0xFF6A7280),
                background: const Color(0x146A7280),
              ),
              _MetaChip(
                label: taskRow.scheduleLabel,
                foreground: const Color(0xFF6A7280),
                background: const Color(0x146A7280),
              ),
            ],
          ),
          if (taskRow.priorityReason != null) ...[
            const SizedBox(height: 10),
            Text(
              taskRow.priorityReason!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6A7280)),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScheduleOverviewCard extends StatelessWidget {
  const _ScheduleOverviewCard({required this.overview});

  final ScheduleOverview overview;

  @override
  Widget build(BuildContext context) {
    final classes = List<FixedClass>.from(overview.fixedClasses)..sort((a, b) {
      final dayCompare = a.dayOfWeek.compareTo(b.dayOfWeek);
      if (dayCompare != 0) {
        return dayCompare;
      }

      return a.startTime.compareTo(b.startTime);
    });

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
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
                      Text(
                        'Schedule Overview',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${classes.length} recurring classes | Transit buffer ${overview.settings.transitBufferMinutes ?? 0} min',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF6A7280),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x142F628F),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Live',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaChip(
                  label: 'Wake/Sleep ${overview.settings.wakeSleepLabel}',
                  foreground: const Color(0xFF6A7280),
                  background: const Color(0x146A7280),
                ),
                _MetaChip(
                  label: overview.settings.mealsLabel,
                  foreground: const Color(0xFF6A7280),
                  background: const Color(0x146A7280),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (classes.isEmpty)
              Text(
                'No recurring fixed classes have been saved yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF6A7280),
                ),
              )
            else
              for (var index = 0; index < classes.length; index++) ...[
                _FixedClassTile(fixedClass: classes[index]),
                if (index != classes.length - 1) const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}

class _FixedClassTile extends StatelessWidget {
  const _FixedClassTile({required this.fixedClass});

  final FixedClass fixedClass;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0x142F628F),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                fixedClass.dayLabel,
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fixedClass.className,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1D1D1F),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${fixedClass.startTime} - ${fixedClass.endTime}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6A7280),
                  ),
                ),
                if (fixedClass.classType != null) ...[
                  const SizedBox(height: 6),
                  _MetaChip(
                    label: fixedClass.classType!,
                    foreground: AppTheme.primary,
                    background: const Color(0x142F628F),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceOverviewCard extends StatelessWidget {
  const _WorkspaceOverviewCard({required this.overview});

  final WorkspaceOverview overview;

  @override
  Widget build(BuildContext context) {
    final activeMembersCount =
        overview.members.where((member) => member.status == 'active').length;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
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
                      Text(
                        'Workspaces',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${overview.workspaces.length} workspaces | '
                        '$activeMembersCount active members | '
                        '${overview.assignments.length} assignments',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF6A7280),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x142F628F),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Live',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            for (
              var index = 0;
              index < overview.workspaces.length;
              index++
            ) ...[
              _WorkspaceTile(
                workspace: overview.workspaces[index],
                activeMemberCount:
                    overview.members
                        .where(
                          (member) =>
                              member.workspaceId ==
                                  overview.workspaces[index].id &&
                              member.status == 'active',
                        )
                        .length,
                assignmentCount:
                    overview.assignments
                        .where(
                          (assignment) =>
                              assignment.workspaceId ==
                              overview.workspaces[index].id,
                        )
                        .length,
              ),
              if (index != overview.workspaces.length - 1)
                const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({
    required this.workspace,
    required this.activeMemberCount,
    required this.assignmentCount,
  });

  final Workspace workspace;
  final int activeMemberCount;
  final int assignmentCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  workspace.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1D1D1F),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _MetaChip(
                label: '$activeMemberCount members',
                foreground: AppTheme.primary,
                background: const Color(0x142F628F),
              ),
            ],
          ),
          if (workspace.description != null) ...[
            const SizedBox(height: 8),
            Text(
              workspace.description!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6A7280)),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(
                label: '$assignmentCount assignments',
                foreground: const Color(0xFF6A7280),
                background: const Color(0x146A7280),
              ),
              if (workspace.inviteCode != null)
                _MetaChip(
                  label: 'Invite ${workspace.inviteCode}',
                  foreground: const Color(0xFF6A7280),
                  background: const Color(0x146A7280),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}
