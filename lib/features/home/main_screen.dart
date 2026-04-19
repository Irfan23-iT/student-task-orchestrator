import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../profile/profile_view.dart';
import '../schedule/schedule_view.dart';
import '../tasks/tasks_view.dart';
import '../workspaces/workspaces_view.dart';
import 'dashboard_view.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  static const _titles = <String>[
    'RakanStudent Dashboard',
    'Schedule',
    'Tasks',
    'Profile',
    'Workspaces',
  ];

  static const _views = <Widget>[
    DashboardView(),
    ScheduleView(),
    TasksView(),
    ProfileView(),
    WorkspacesView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar:
          (_currentIndex == 1 || _currentIndex == 4)
              ? null
              : AppBar(title: Text(_titles[_currentIndex])),
      body: IndexedStack(index: _currentIndex, children: _views),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_rounded),
            label: 'Schedule',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list_rounded),
            label: 'Tasks',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.group_rounded),
            label: 'Workspaces',
          ),
        ],
      ),
    );
  }
}
