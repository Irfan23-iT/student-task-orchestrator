import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../data/models/task_row.dart';
import '../../data/tasks_repository.dart';

final tasksRepositoryProvider = Provider<TasksRepository>((ref) {
  return TasksRepository(apiClient: ref.watch(apiClientProvider));
});

final taskRowsProvider = FutureProvider<List<TaskRow>>((ref) async {
  return ref.watch(tasksRepositoryProvider).fetchTaskRows();
});
