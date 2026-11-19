import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/views.dart';
import '../../repositories/user_repository.dart';
import '../../state/task_list_controller.dart';
import '../screens/task_detail_screen.dart';
import 'common.dart';

/// Список задач с поиском, фильтрами, сортировкой и пагинацией.
class TaskListView extends StatefulWidget {
  const TaskListView({
    super.key,
    required this.controller,
    this.showProject = true,
  });
  final TaskListController controller;
  final bool showProject;

  @override
  State<TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends State<TaskListView> {
  final _search = TextEditingController();

  TaskListController get c => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickAssignee() async {
    final users = await context.read<UserRepository>().getAll();
    if (!mounted) return;
    final picked = await showModalBottomSheet<int?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, sc) => ListView.builder(
          controller: sc,
          itemCount: users.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              return ListTile(
                leading: const Icon(Icons.clear),
                title: const Text('Любой исполнитель'),
                onTap: () => Navigator.pop(ctx, -1),
              );
            }
            final u = users[i - 1];
            return ListTile(
              leading: CircleAvatar(child: Text(initials(u.name))),
              title: Text(u.name),
              onTap: () => Navigator.pop(ctx, u.id),
            );
          },
        ),
      ),
    );
    if (picked == null) return;
    c.setAssignee(picked == -1 ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final f = c.filter;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Поиск по названию и описанию',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _search.clear();
                            c.setSearch('');
                          },
                        ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onChanged: (v) {
                  setState(() {});
                  c.setSearch(v);
                },
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                children: [
                  _menuChip<TaskStatus>(
                    label: f.status?.label ?? 'Статус',
                    selected: f.status != null,
                    values: TaskStatus.values,
                    labelOf: (s) => s.label,
                    onSelected: c.setStatus,
                  ),
                  _menuChip<TaskPriority>(
                    label: f.priority?.label ?? 'Приоритет',
                    selected: f.priority != null,
                    values: TaskPriority.values,
                    labelOf: (s) => s.label,
                    onSelected: c.setPriority,
                  ),
                  if (!c.hasLockedAssignee)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(
                          f.assigneeId == null
                              ? 'Исполнитель'
                              : 'Исполнитель ✓',
                        ),
                        selected: f.assigneeId != null,
                        onSelected: (_) => _pickAssignee(),
                      ),
                    ),
                  ChoiceChip(
                    label: Text(
                      f.sortField == TaskSortField.createdAt
                          ? 'Сортировка: создание'
                          : 'Сортировка: дедлайн',
                    ),
                    selected: false,
                    avatar: const Icon(Icons.sort, size: 18),
                    onSelected: (_) => c.setSort(
                      f.sortField == TaskSortField.createdAt
                          ? TaskSortField.deadline
                          : TaskSortField.createdAt,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: Icon(
                      f.ascending ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 18,
                    ),
                    label: Text(f.ascending ? 'по возрастанию' : 'по убыванию'),
                    onPressed: c.toggleDirection,
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      _search.clear();
                      c.reset();
                    },
                    child: const Text('Сбросить'),
                  ),
                ],
              ),
            ),
            StreamBuilder<int>(
              stream: c.total,
              builder: (context, s) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Найдено задач: ${s.data ?? 0}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<TaskView>>(
                stream: c.tasks,
                builder: (context, snap) {
                  if (snap.hasError) return EmptyState('${snap.error}');
                  final list = snap.data;
                  if (list == null)
                    return const Center(child: CircularProgressIndicator());
                  if (list.isEmpty) {
                    return const EmptyState('Задач нет', icon: Icons.task_alt);
                  }
                  final more = list.length >= c.limit;
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: list.length + (more ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == list.length) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: OutlinedButton.icon(
                            onPressed: c.loadMore,
                            icon: const Icon(Icons.expand_more),
                            label: Text(
                              'Показать ещё (загружено ${list.length})',
                            ),
                          ),
                        );
                      }
                      return TaskTile(
                        view: list[i],
                        showProject: widget.showProject,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _menuChip<T>({
    required String label,
    required bool selected,
    required List<T> values,
    required String Function(T) labelOf,
    required void Function(T?) onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<T?>(
        onSelected: onSelected,
        itemBuilder: (_) => [
          const PopupMenuItem(value: null, child: Text('Любой')),
          for (final v in values)
            PopupMenuItem(value: v, child: Text(labelOf(v))),
        ],
        child: Chip(
          label: Text(label),
          backgroundColor: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          avatar: const Icon(Icons.arrow_drop_down, size: 18),
        ),
      ),
    );
  }
}

class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.view, this.showProject = true});
  final TaskView view;
  final bool showProject;

  @override
  Widget build(BuildContext context) {
    final t = view.task;
    final overdue =
        t.status.isOpen &&
        t.deadline != null &&
        t.deadline!.isBefore(DateTime.now());
    return ListTile(
      leading: Icon(statusIcon(t.status), color: statusColor(t.status)),
      title: Text(
        t.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.status == TaskStatus.done || t.status == TaskStatus.cancelled
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Pill(t.priority.label, priorityColor(t.priority)),
            if (showProject)
              Text(view.projectName, style: const TextStyle(fontSize: 12)),
            Text(
              '👤 ${view.assigneeName ?? '—'}',
              style: const TextStyle(fontSize: 12),
            ),
            if (t.deadline != null)
              Text(
                '⏰ ${dateFmt.format(t.deadline!)}',
                style: TextStyle(
                  fontSize: 12,
                  color: overdue ? Colors.red : null,
                  fontWeight: overdue ? FontWeight.bold : null,
                ),
              ),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: t.id)),
      ),
    );
  }
}
