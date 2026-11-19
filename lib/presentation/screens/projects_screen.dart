import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../models/enums.dart';
import '../../models/views.dart';
import '../../repositories/project_repository.dart';
import '../widgets/common.dart';
import 'project_detail_screen.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ProjectRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Проекты')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => showProjectDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Проект'),
      ),
      body: StreamBuilder<List<ProjectSummary>>(
        stream: repo.watchSummaries(),
        builder: (context, snap) {
          final list = snap.data;
          if (list == null)
            return const Center(child: CircularProgressIndicator());
          if (list.isEmpty)
            return const EmptyState(
              'Проектов пока нет',
              icon: Icons.folder_open,
            );
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final s = list[i];
              final p = s.project;
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProjectDetailScreen(projectId: p.id),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                p.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Pill(p.status.label, switch (p.status) {
                              ProjectStatus.active => Colors.green,
                              ProjectStatus.completed => Colors.blue,
                              ProjectStatus.archived => Colors.grey,
                            }),
                          ],
                        ),
                        if (p.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              p.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: s.percent / 100,
                          minHeight: 6,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${s.percent.toStringAsFixed(0)}% · задач: ${s.totalTasks} (завершено ${s.doneTasks}) · создан ${dateFmt.format(p.createdAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

Future<void> showProjectDialog(BuildContext context, {Project? project}) async {
  final repo = context.read<ProjectRepository>();
  final name = TextEditingController(text: project?.name);
  final desc = TextEditingController(text: project?.description);
  var status = project?.status ?? ProjectStatus.active;
  DateTime? finished = project?.finishedAt;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(
          project == null ? 'Новый проект' : 'Редактирование проекта',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Название'),
              ),
              TextField(
                controller: desc,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Описание'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<ProjectStatus>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Статус'),
                items: [
                  for (final s in ProjectStatus.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() => status = v!),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      finished == null
                          ? 'Дата завершения: не задана'
                          : 'Завершение: ${dateFmt.format(finished!)}',
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.event),
                    onPressed: () async {
                      final now = DateTime.now();
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: finished ?? now,
                        firstDate: DateTime(now.year - 5),
                        lastDate: DateTime(now.year + 10),
                      );
                      if (d != null) setState(() => finished = d);
                    },
                  ),
                  if (finished != null)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => finished = null),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              final ok = await guard(ctx, () async {
                if (project == null) {
                  await repo.create(
                    name: name.text,
                    description: desc.text,
                    status: status,
                    finishedAt: finished,
                  );
                } else {
                  await repo.update(
                    project.id,
                    name: name.text,
                    description: desc.text,
                    status: status,
                    finishedAt: finished,
                  );
                }
              });
              if (ok && ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
}
