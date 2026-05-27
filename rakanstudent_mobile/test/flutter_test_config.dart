import 'dart:async';

import 'package:rakanstudent_mobile/services/api_service.dart';
import 'package:rakanstudent_mobile/views/calendar_view.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ApiService.enableHealthCheckBypassForTests();
  CalendarView.enableCalendarFetchBypassForTests();
  await testMain();
}
