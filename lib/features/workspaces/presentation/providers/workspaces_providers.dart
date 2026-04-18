import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../data/models/workspace_overview.dart';
import '../../data/workspaces_repository.dart';

final workspacesRepositoryProvider = Provider<WorkspacesRepository>((ref) {
  return WorkspacesRepository(apiClient: ref.watch(apiClientProvider));
});

final workspaceOverviewProvider = FutureProvider<WorkspaceOverview>((
  ref,
) async {
  return ref.watch(workspacesRepositoryProvider).getWorkspaceOverview();
});
