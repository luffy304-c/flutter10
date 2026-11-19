import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../models/enums.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/task_repository.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';

/// Создание и редактирование задачи.
class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({super.key, this.projectId, this.task});
  final int? projectId;
  final Task? task;

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.task?.title);
  late final _desc = TextEditingController(text: widget.task?.description);
  int? _projectId;
  int? _assigneeId;
  late TaskPriority _priority = widget.task?.priority ?? TaskPriority.medium;
  TaskStatus _status = TaskStatus.todo;
  DateTime? _deadline;
  List<Project> _projects = [];
  List<User> _members = [];
  bool _saving = false;

  bool get _editing => widget.task != null;

  @override
  void initState() {
    super.initState();
    _projectId = widget.task?.projectId ?? widget.projectId;
    _assigneeId = widget.task?.assigneeId;
    _deadline = widget.task?.deadline;
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<ProjectRepository>();
    final projects = await repo.watchAll().first;
    if (!mounted) return;
    setState(() => _projects = projects);
    await _loadMembers();
  }

  Future<void> _loadMembers() async {
    final pid = _projectId;
    if (pid == null) return;
    final m = await context.read<ProjectRepository>().getMembers(pid);
    if (!mounted) return;
    setState(() {
      _members = m.map((e) => e.user).toList();
      if (!_members.any((u) => u.id == _assigneeId)) _assigneeId = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10),
    );
    if (d != null)
      setState(() => _deadline = DateTime(d.year, d.month, d.day, 23, 59));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = context.read<TaskRepository>();
    final actor = context.read<AppController>().actorId;
    final ok = await guard(context, () async {
      if (_editing) {
        final t = widget.task!;
        await repo.updateTask(
          t.id,
          title: _title.text,
          description: _desc.text,
          priority: _priority,
          deadline: _deadline,
        );
        if (_assigneeId != t.assigneeId) {
          await repo.reassign(t.id, _assigneeId, actorId: actor);
        }
      } else {
        await repo.createTask(
          title: _title.text,
          description: _desc.text,
          projectId: _projectId,
          assigneeId: _assigneeId,
          priority: _priority,
          status: _status,
          deadline: _deadline,
          actorId: actor,
        );
      }
    }, success: _editing ? 'Задача сохранена' : 'Задача создана');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Редактирование задачи' : 'Новая задача'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Название',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Введите название' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _desc,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Описание',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _projectId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Проект',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final p in _projects)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: _editing || widget.projectId != null
                  ? null
                  : (v) {
                      setState(() => _projectId = v);
                      _loadMembers();
                    },
              validator: (v) => v == null ? 'Выберите проект' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              key: ValueKey('assignee-$_projectId-${_members.length}'),
              initialValue: _assigneeId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Исполнитель (участник проекта)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Не назначен'),
                ),
                for (final u in _members)
                  DropdownMenuItem<int?>(value: u.id, child: Text(u.name)),
              ],
              onChanged: (v) => setState(() => _assigneeId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<TaskPriority>(
              initialValue: _priority,
              decoration: const InputDecoration(
                labelText: 'Приоритет',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final p in TaskPriority.values)
                  DropdownMenuItem(value: p, child: Text(p.label)),
              ],
              onChanged: (v) => setState(() => _priority = v!),
            ),
            if (!_editing) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<TaskStatus>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Статус',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final s in TaskStatus.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() => _status = v!),
              ),
            ],
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Дедлайн',
                border: OutlineInputBorder(),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _deadline == null
                          ? 'Не задан'
                          : dateFmt.format(_deadline!),
                    ),
                  ),
                  TextButton(
                    onPressed: _pickDate,
                    child: const Text('Выбрать'),
                  ),
                  if (_deadline != null)
                    IconButton(
                      onPressed: () => setState(() => _deadline = null),
                      icon: const Icon(Icons.clear),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_editing ? 'Сохранить' : 'Создать задачу'),
            ),
          ],
        ),
      ),
    );
  }
}
