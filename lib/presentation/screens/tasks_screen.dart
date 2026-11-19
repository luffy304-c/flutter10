import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../repositories/task_repository.dart';
import '../../state/task_list_controller.dart';
import '../widgets/task_list_view.dart';
import 'task_form_screen.dart';

/// Все задачи: поиск, фильтры, сортировка, пагинация.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  late final _controller = TaskListController(context.read<TaskRepository>());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Задачи')),
    floatingActionButton: FloatingActionButton.extended(
      heroTag: null,
      icon: const Icon(Icons.add),
      label: const Text('Задача'),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TaskFormScreen()),
      ),
    ),
    body: TaskListView(controller: _controller),
  );
}
