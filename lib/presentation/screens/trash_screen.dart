import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/views.dart';
import '../../repositories/task_repository.dart';
import '../widgets/common.dart';

/// Корзина (Soft Delete): просмотр, восстановление, полное удаление.
class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<TaskRepository>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Корзина'),
        actions: [
          TextButton(
            onPressed: () async {
              if (await confirm(
                context,
                'Очистить корзину?',
                'Все задачи из корзины будут удалены безвозвратно.',
                ok: 'Очистить',
              )) {
                if (context.mounted) await guard(context, repo.emptyTrash);
              }
            },
            child: const Text('Очистить'),
          ),
        ],
      ),
      body: StreamBuilder<List<TaskView>>(
        stream: repo.watchTasks(
          const TaskFilter(onlyDeleted: true),
          limit: 500,
        ),
        builder: (context, snap) {
          final list = snap.data;
          if (list == null)
            return const Center(child: CircularProgressIndicator());
          if (list.isEmpty)
            return const EmptyState(
              'Корзина пуста',
              icon: Icons.delete_outline,
            );
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              final t = list[i].task;
              return ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(t.title),
                subtitle: Text(
                  '${list[i].projectName} · удалена ${dateTimeFmt.format(t.deletedAt!)}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Восстановить',
                      icon: const Icon(Icons.restore),
                      onPressed: () => guard(
                        context,
                        () => repo.restore(t.id),
                        success: 'Задача восстановлена',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Удалить навсегда',
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      onPressed: () async {
                        if (await confirm(
                          context,
                          'Удалить навсегда?',
                          t.title,
                        )) {
                          if (context.mounted)
                            await guard(context, () => repo.purge(t.id));
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
