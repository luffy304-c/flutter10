import 'package:flutter/material.dart';

import 'screens/dashboard_screen.dart';
import 'screens/more_screen.dart';
import 'screens/projects_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/users_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  static const _pages = <Widget>[
    ProjectsScreen(),
    TasksScreen(),
    UsersScreen(),
    DashboardScreen(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _index, children: _pages),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder),
          label: 'Проекты',
        ),
        NavigationDestination(icon: Icon(Icons.checklist), label: 'Задачи'),
        NavigationDestination(
          icon: Icon(Icons.group_outlined),
          selectedIcon: Icon(Icons.group),
          label: 'Люди',
        ),
        NavigationDestination(
          icon: Icon(Icons.insights_outlined),
          selectedIcon: Icon(Icons.insights),
          label: 'Статистика',
        ),
        NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Ещё'),
      ],
    ),
  );
}
