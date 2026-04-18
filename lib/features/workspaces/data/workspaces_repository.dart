import '../../../core/errors/app_error.dart';
import '../../../core/network/api_client.dart';
import 'models/workspace_overview.dart';

class WorkspacesRepository {
  const WorkspacesRepository({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<WorkspaceOverview> getWorkspaceOverview() async {
    final response = await _apiClient.get('/workspaces/overview');
    final decoded = response.decodeJson();

    if (decoded is! Map<String, dynamic>) {
      throw AppError(
        message: 'Invalid workspaces response',
        details: 'Expected an object response from /workspaces/overview.',
        requestId: response.requestId,
      );
    }

    if (decoded['workspaces'] is! List ||
        decoded['members'] is! List ||
        decoded['assignments'] is! List ||
        decoded['activity'] is! List) {
      throw AppError(
        message: 'Invalid workspaces response',
        details:
            'Expected "workspaces", "members", "assignments", and "activity" to be lists.',
        requestId: response.requestId,
      );
    }

    return WorkspaceOverview.fromJson(decoded);
  }
}
