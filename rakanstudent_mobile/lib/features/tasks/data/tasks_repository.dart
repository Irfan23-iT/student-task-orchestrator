import '../../../core/errors/app_error.dart';
import '../../../core/network/api_client.dart';
import 'models/task_row.dart';

class TasksRepository {
  const TasksRepository({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<TaskRow>> fetchTaskRows() async {
    final response = await _apiClient.get('/tasks/rows');
    final decoded = response.decodeJson();

    if (decoded is! Map<String, dynamic>) {
      throw const AppError(
        message: 'Invalid tasks response',
        details: 'Expected an object response from /tasks/rows.',
      );
    }

    final rowsJson = decoded['rows'];
    if (rowsJson is! List) {
      throw AppError(
        message: 'Invalid tasks response',
        details: 'Expected "rows" to be a list.',
        requestId: response.requestId,
      );
    }

    return rowsJson
        .whereType<Map<String, dynamic>>()
        .map(TaskRow.fromJson)
        .toList(growable: false);
  }
}
