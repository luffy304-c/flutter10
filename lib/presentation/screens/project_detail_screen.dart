import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../models/enums.dart';
import '../../models/views.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/task_repository.dart';
import '../../state/task_list_controller.dart';
import '../widgets/common.dart';
import '../widgets/task_list_view.dart';
import 'projects_screen.dart';
import 'task_form_screen.dart';

class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.projectId});
  final int projectId;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  late final TaskListController _tasks = TaskListController(
    context.read<TaskRepository>(),
    initial: TaskFilter(projectId: widget.projectId),
  );

  @override
  void dispose() {
    _tasks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ProjectRepository>();
    return StreamBuilder<Project?>(
      stream: repo.watchById(widget.projectId),
      builder: (context, snap) {
        final p = snap.data;
        if (p == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState('Проект не найден'),
          );
        }
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(p.name),
              actions: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => showProjectDialog(context, project: p),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (!await confirm(
                      context,
                      'Удалить проект?',
                      'Будут удалены все задачи проекта, участники и история.',
                    ))
                      return;
                    if (!context.mounted) return;
                    final nav = Navigator.of(context);
                    if (await guard(context, () => repo.delete(p.id)))
                      nav.pop();
                  },
                ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Задачи'),
                  Tab(text: 'Участники'),
                ],
              ),
            ),
            floatingActionButton: Builder(
              builder: (ctx) => FloatingActionButton.extended(
                heroTag: null,
                icon: const Icon(Icons.add),
                label: Text(
                  DefaultTabController.of(ctx).index == 0
                      ? 'Задача'
                      : 'Участник',
                ),
                onPressed: () => DefaultTabController.of(ctx).index == 0
                    ? Navigator.push(
                        ctx,
                        MaterialPageRoute(
                          builder: (_) => TaskFormScreen(projectId: p.id),
                        ),
                      )
                    : _addMember(ctx, p.id),
              ),
            ),
            body: TabBarView(
              children: [
                TaskListView(controller: _tasks, showProject: false),
                _Members(projectId: p.id),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addMember(BuildContext context, int projectId) async {
    final repo = context.read<ProjectRepository>();
    final candidates = await repo.usersNotInProject(projectId);
    if (!context.mounted) return;
    if (candidates.isEmpty) {
      showSnack(context, 'Нет пользователей, которых можно добавить');
      return;
    }
    final picked = await showModalBottomSheet<User>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, sc) => ListView.builder(
          controller: sc,
          itemCount: candidates.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) return const ListTile(title: Text('Добавить участника'));
            final u = candidates[i - 1];
            return ListTile(
              leading: CircleAvatar(child: Text(initials(u.name))),
              title: Text(u.name),
              subtitle: Text(u.email),
              onTap: () => Navigator.pop(ctx, u),
            );
          },
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await guard(
      context,
      () => repo.addMember(projectId, picked.id),
      success: '${picked.name} добавлен(а) в проект',
    );
  }
}

class _Members extends StatelessWidget {
  const _Members({required this.projectId});
  final int projectId;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ProjectRepository>();
    return StreamBuilder<List<MemberView>>(
      stream: repo.watchMembers(projectId),
      builder: (context, snap) {
        final list = snap.data ?? const [];
        if (list.isEmpty)
          return const EmptyState(
            'В проекте нет участников',
            icon: Icons.group_outlined,
          );
        return ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            for (final m in list)
              ListTile(
                leading: CircleAvatar(child: Text(initials(m.user.name))),
                title: Text(m.user.name),
                subtitle: Text(m.user.email),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PopupMenuButton<MemberRole>(
                      initialValue: m.member.role,
                      onSelected: (r) => repo.setRole(m.member.id, r),
                      itemBuilder: (_) => [
                        for (final r in MemberRole.values)
                          PopupMenuItem(value: r, child: Text(r.label)),
                      ],
                      child: Chip(label: Text(m.member.role.label)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: () => guard(
                        context,
                        () => repo.removeMember(projectId, m.user.id),
                        success: 'Участник удалён',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
