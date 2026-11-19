import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../models/enums.dart';
import '../../models/views.dart';
import '../../repositories/attachment_repository.dart';
import '../../repositories/comment_repository.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/task_repository.dart';
import '../../services/attachment_storage.dart';
import '../../state/app_controller.dart';
import '../widgets/common.dart';
import 'task_form_screen.dart';

class TaskDetailScreen extends StatelessWidget {
  const TaskDetailScreen({super.key, required this.taskId});
  final int taskId;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<TaskRepository>();
    return StreamBuilder<TaskView?>(
      stream: repo.watchTask(taskId),
      builder: (context, snap) {
        final v = snap.data;
        if (snap.connectionState == ConnectionState.waiting && v == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (v == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState('Задача удалена'),
          );
        }
        return _Body(view: v);
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.view});
  final TaskView view;

  Task get t => view.task;

  Future<void> _reassign(BuildContext context) async {
    final members = await context.read<ProjectRepository>().getMembers(
      t.projectId,
    );
    if (!context.mounted) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Исполнитель (только участники проекта)')),
          ListTile(
            leading: const Icon(Icons.person_off_outlined),
            title: const Text('Не назначен'),
            onTap: () => Navigator.pop(ctx, -1),
          ),
          for (final m in members)
            ListTile(
              leading: CircleAvatar(child: Text(initials(m.user.name))),
              title: Text(m.user.name),
              subtitle: Text(m.member.role.label),
              selected: m.user.id == t.assigneeId,
              onTap: () => Navigator.pop(ctx, m.user.id),
            ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    final actor = context.read<AppController>().actorId;
    await guard(
      context,
      () => context.read<TaskRepository>().reassign(
        t.id,
        picked == -1 ? null : picked,
        actorId: actor,
      ),
      success: 'Исполнитель изменён',
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<TaskRepository>();
    final actor = context.watch<AppController>().actorId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Задача'),
        actions: [
          IconButton(
            tooltip: 'Редактировать',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TaskFormScreen(task: t)),
            ),
          ),
          IconButton(
            tooltip: 'В корзину',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (!await confirm(
                context,
                'Переместить в корзину?',
                'Задачу можно будет восстановить из корзины.',
                ok: 'В корзину',
              )) {
                return;
              }
              if (!context.mounted) return;
              final nav = Navigator.of(context);
              if (await guard(
                context,
                () => repo.softDelete(t.id),
                success: 'Задача перемещена в корзину',
              )) {
                nav.pop();
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              t.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          if (t.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(t.description),
            ),
          const SectionTitle('Статус'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in TaskStatus.values)
                  ChoiceChip(
                    label: Text(s.label),
                    avatar: Icon(
                      statusIcon(s),
                      size: 18,
                      color: statusColor(s),
                    ),
                    selected: t.status == s,
                    onSelected: (_) => guard(
                      context,
                      () => repo.changeStatus(t.id, s, actorId: actor),
                    ),
                  ),
              ],
            ),
          ),
          StreamBuilder<TaskHistoryEntry?>(
            stream: repo.watchUndoable(t.id),
            builder: (context, snap) {
              final last = snap.data;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.undo),
                    label: Text(
                      last == null
                          ? 'Отменить изменение статуса'
                          : 'Отменить: ${last.oldStatus?.label} ← ${last.newStatus.label}',
                    ),
                    onPressed: last == null
                        ? null
                        : () => guard(
                            context,
                            () =>
                                repo.undoLastStatusChange(t.id, actorId: actor),
                            success: 'Статус возвращён',
                          ),
                  ),
                ),
              );
            },
          ),
          const SectionTitle('Приоритет'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final p in TaskPriority.values)
                  ChoiceChip(
                    label: Text(p.label),
                    selectedColor: priorityColor(p).withValues(alpha: 0.25),
                    selected: t.priority == p,
                    onSelected: (_) =>
                        guard(context, () => repo.changePriority(t.id, p)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(view.projectName),
            subtitle: const Text('Проект'),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(view.assigneeName ?? 'Не назначен'),
            subtitle: const Text('Исполнитель — нажмите, чтобы переназначить'),
            trailing: const Icon(Icons.swap_horiz),
            onTap: () => _reassign(context),
          ),
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: Text(
              t.deadline == null ? 'Не задан' : dateFmt.format(t.deadline!),
            ),
            subtitle: const Text('Дедлайн'),
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: Text('Создана ${dateTimeFmt.format(t.createdAt)}'),
            subtitle: Text('Изменена ${dateTimeFmt.format(t.updatedAt)}'),
          ),
          _Attachments(taskId: t.id),
          _Comments(taskId: t.id),
          _History(taskId: t.id),
        ],
      ),
    );
  }
}

class _Comments extends StatefulWidget {
  const _Comments({required this.taskId});
  final int taskId;

  @override
  State<_Comments> createState() => _CommentsState();
}

class _CommentsState extends State<_Comments> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<CommentRepository>();
    final me = context.watch<AppController>().currentUser;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Комментарии'),
        StreamBuilder<List<CommentView>>(
          stream: repo.watchForTask(widget.taskId),
          builder: (context, snap) {
            final list = snap.data ?? const [];
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Комментариев пока нет'),
              );
            }
            return Column(
              children: [
                for (final c in list)
                  ListTile(
                    leading: CircleAvatar(child: Text(initials(c.authorName))),
                    title: Text(c.comment.body),
                    subtitle: Text(
                      '${c.authorName} · ${dateTimeFmt.format(c.comment.createdAt)}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Удалить (только автор)',
                      onPressed: me == null
                          ? null
                          : () => guard(
                              context,
                              () =>
                                  repo.delete(c.comment.id, requesterId: me.id),
                            ),
                    ),
                  ),
              ],
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: InputDecoration(
                    hintText: me == null
                        ? 'Сначала создайте пользователя'
                        : 'Комментарий от ${me.name}',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton.filled(
                icon: const Icon(Icons.send),
                onPressed: me == null
                    ? null
                    : () async {
                        final ok = await guard(
                          context,
                          () => repo.add(
                            taskId: widget.taskId,
                            authorId: me.id,
                            text: _ctrl.text,
                          ),
                        );
                        if (ok) _ctrl.clear();
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Attachments extends StatelessWidget {
  const _Attachments({required this.taskId});
  final int taskId;

  Future<void> _add(BuildContext context) async {
    final repo = context.read<AttachmentRepository>();
    final storage = context.read<AttachmentStorage>();
    final res = await FilePicker.pickFiles();
    if (res.isEmpty || !context.mounted) return;
    final f = res.first;
    if (f.path == null) return;
    await guard(context, () async {
      final saved = await storage.store(f.path!);
      await repo.add(taskId: taskId, fileName: f.name, filePath: saved);
    }, success: 'Файл прикреплён');
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AttachmentRepository>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          'Вложения',
          trailing: TextButton.icon(
            onPressed: () => _add(context),
            icon: const Icon(Icons.attach_file),
            label: const Text('Добавить'),
          ),
        ),
        StreamBuilder<List<Attachment>>(
          stream: repo.watchForTask(taskId),
          builder: (context, snap) {
            final list = snap.data ?? const [];
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Файлов нет'),
              );
            }
            return Column(
              children: [
                for (final a in list)
                  ListTile(
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(a.fileName),
                    subtitle: Text(
                      '${dateTimeFmt.format(a.addedAt)}\n${a.filePath}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final storage = context.read<AttachmentStorage>();
                        await repo.delete(a.id);
                        await storage.deleteFile(a.filePath);
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.taskId});
  final int taskId;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<TaskRepository>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('История изменений'),
        StreamBuilder<List<HistoryView>>(
          stream: repo.watchHistory(taskId),
          builder: (context, snap) {
            final list = snap.data ?? const [];
            return Column(
              children: [
                for (final h in list)
                  ListTile(
                    dense: true,
                    leading: Icon(switch (h.entry.kind) {
                      HistoryKind.created => Icons.add_circle_outline,
                      HistoryKind.status => Icons.swap_horiz,
                      HistoryKind.reassign => Icons.person_outline,
                      HistoryKind.undo => Icons.undo,
                    }, color: h.entry.undone ? Colors.grey : null),
                    title: Text(switch (h.entry.kind) {
                      HistoryKind.status || HistoryKind.undo =>
                        '${h.entry.oldStatus?.label ?? '—'} → ${h.entry.newStatus.label}',
                      HistoryKind.created =>
                        'Создана (${h.entry.newStatus.label})',
                      HistoryKind.reassign =>
                        h.entry.details ?? 'Смена исполнителя',
                    }),
                    subtitle: Text(
                      '${h.entry.kind.label} · ${h.userName ?? 'система'} · ${dateTimeFmt.format(h.entry.changedAt)}'
                      '${h.entry.undone ? ' · отменено' : ''}',
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
