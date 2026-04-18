import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../data/models/schedule_overview.dart';
import '../../data/schedule_repository.dart';

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  return ScheduleRepository(apiClient: ref.watch(apiClientProvider));
});

final scheduleOverviewProvider = FutureProvider<ScheduleOverview>((ref) async {
  return ref.watch(scheduleRepositoryProvider).fetchOverview();
});
