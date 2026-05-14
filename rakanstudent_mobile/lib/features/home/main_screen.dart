import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../profile/profile_view.dart';
import '../schedule/schedule_view.dart';
import '../tasks/tasks_view.dart';
import 'dashboard_view.dart';
import '../../views/ai_chat_view.dart';
import '../../views/calendar_view.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, @visibleForTesting this.testScreens});

  final List<Widget>? testScreens;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  int _taskTabRefreshSignal = 0;

  static const _titles = <String>[
    'Home',
    'Schedule',
    'Tasks',
    'Calendar',
    'AI',
    'Profile',
  ];

  void _setCurrentIndex(int index) {
    if (_currentIndex == index) {
      if (index == 2) {
        setState(() {
          _taskTabRefreshSignal++;
        });
      }
      return;
    }

    setState(() {
      _currentIndex = index;
      if (index == 2) {
        _taskTabRefreshSignal++;
      }
    });
  }

  Widget _buildNavItem({
    Key? key,
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isActive = _currentIndex == index;
    final theme = Theme.of(context);

    if (isActive) {
      return AnimatedContainer(
        key: key,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Icon(icon, key: key, color: Colors.grey, size: 26);
  }

  Widget _buildNavButton({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isActive = _currentIndex == index;

    return Expanded(
      flex: isActive ? 3 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _setCurrentIndex(index),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                );
              },
              child: _buildNavItem(
                key: ValueKey<bool>(isActive),
                index: index,
                icon: icon,
                label: label,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomNavBar() {
    return Container(
      width: double.infinity,
      height: 75.0,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(35),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildNavButton(
            index: 0,
            icon: Icons.home_rounded,
            label: _titles[0],
          ),
          _buildNavButton(
            index: 1,
            icon: Icons.calendar_month_rounded,
            label: _titles[1],
          ),
          _buildNavButton(
            index: 2,
            icon: Icons.list_rounded,
            label: _titles[2],
          ),
          _buildNavButton(
            index: 3,
            icon: Icons.event_available_rounded,
            label: _titles[3],
          ),
          _buildNavButton(
            index: 4,
            icon: Icons.auto_awesome_rounded,
            label: _titles[4],
          ),
          _buildNavButton(
            index: 5,
            icon: Icons.person_rounded,
            label: _titles[5],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens =
        widget.testScreens ??
        <Widget>[
          const DashboardView(),
          const ScheduleView(),
          TasksView(refreshSignal: _taskTabRefreshSignal),
          const CalendarView(),
          const AiChatView(),
          const ProfileView(),
        ];
    assert(screens.length == _titles.length);

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );

    return Container(
      constraints: const BoxConstraints.expand(),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF241033), Color(0xFF121014), Color(0xFF08070A)],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: IndexedStack(index: _currentIndex, children: screens),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(
                  bottom: 16.0,
                  left: 24.0,
                  right: 24.0,
                ),
                child: _buildCustomNavBar(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
