import '../../../core/errors/app_error.dart';
import '../../../core/network/api_client.dart';
import 'models/fixed_class.dart';
import 'models/profile_settings.dart';
import 'models/schedule_overview.dart';

class ScheduleRepository {
  const ScheduleRepository({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<ScheduleOverview> fetchOverview() async {
    final settingsFuture = _fetchProfileSettings();
    final fixedClassesFuture = _fetchFixedClasses();

    final results = await Future.wait<dynamic>([
      settingsFuture,
      fixedClassesFuture,
    ]);

    return ScheduleOverview(
      settings: results[0] as ProfileSettings,
      fixedClasses: results[1] as List<FixedClass>,
    );
  }

  Future<ProfileSettings> _fetchProfileSettings() async {
    final response = await _apiClient.get('/settings/profile');
    final decoded = response.decodeJson();

    if (decoded is! Map<String, dynamic>) {
      throw const AppError(
        message: 'Invalid settings response',
        details: 'Expected an object response from /settings/profile.',
      );
    }

    final settingsJson = decoded['settings'];
    if (settingsJson is! Map<String, dynamic>) {
      throw AppError(
        message: 'Invalid settings response',
        details: 'Expected "settings" to be an object.',
        requestId: response.requestId,
      );
    }

    return ProfileSettings.fromJson(settingsJson);
  }

  Future<List<FixedClass>> _fetchFixedClasses() async {
    final response = await _apiClient.get('/calendar/fixed-classes');
    final decoded = response.decodeJson();

    if (decoded is! Map<String, dynamic>) {
      throw const AppError(
        message: 'Invalid fixed classes response',
        details: 'Expected an object response from /calendar/fixed-classes.',
      );
    }

    final classesJson = decoded['classes'];
    if (classesJson is! List) {
      throw AppError(
        message: 'Invalid fixed classes response',
        details: 'Expected "classes" to be a list.',
        requestId: response.requestId,
      );
    }

    return classesJson
        .whereType<Map<String, dynamic>>()
        .map(FixedClass.fromJson)
        .toList(growable: false);
  }
}
