import 'dart:async';

import 'package:rakanstudent_mobile/services/api_service.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ApiService.enableHealthCheckBypassForTests();
  await testMain();
}
