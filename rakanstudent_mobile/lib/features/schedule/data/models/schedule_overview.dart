import 'fixed_class.dart';
import 'profile_settings.dart';

class ScheduleOverview {
  const ScheduleOverview({required this.settings, required this.fixedClasses});

  final ProfileSettings settings;
  final List<FixedClass> fixedClasses;
}
