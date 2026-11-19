import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/app_database.dart';
import '../../models/views.dart';
import '../../repositories/task_repository.dart';
import '../../repositories/user_repository.dart';
import '../../state/task_list_controller.dart';
import '../widgets/common.dart';
import '../widgets/task_list_view.dart';

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Пользователи')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => showUserDialog(context),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Пользователь'),
      ),
      body: StreamBuilder<List<User>>(
        stream: repo.watchAll(),
        builder: (context, snap) {
          final list = snap.data;
          if (list == null)
            return const Center(child: CircularProgressIndicator());
          if (list.isEmpty)
            return const EmptyState(
              'Пользователей нет',
              icon: Icons.group_outlined,
            );
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final u = list[i];
              return ListTile(
                leading: CircleAvatar(child: Text(initials(u.name))),
                title: Text(u.name),
                subtitle: Text(
                  '${u.email} · с ${dateFmt.format(u.registeredAt)}',
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => UserDetailScreen(user: u)),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') {
                      showUserDialog(context, user: u);
                    } else if (v == 'delete') {
                      if (await confirm(
                        context,
                        'Удалить пользователя?',
                        u.name,
                      )) {
                        if (context.mounted) {
                          await guard(
                            context,
                            () => repo.delete(u.id),
                            success: 'Пользователь удалён',
                          );
                        }
                      }
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                    PopupMenuItem(value: 'delete', child: Text('Удалить')),
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

Future<void> showUserDialog(BuildContext context, {User? user}) async {
  final repo = context.read<UserRepository>();
  final name = TextEditingController(text: user?.name);
  final email = TextEditingController(text: user?.email);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(user == null ? 'Новый пользователь' : 'Редактирование'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Имя'),
          ),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          if (user == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Дата регистрации: ${dateFmt.format(DateTime.now())}',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () async {
            final ok = await guard(ctx, () async {
              if (user == null) {
                await repo.create(name: name.text, email: email.text);
              } else {
                await repo.update(user.id, name: name.text, email: email.text);
              }
            });
            if (ok && ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
}

/// Задачи, назначенные конкретному пользователю.
class UserDetailScreen extends StatefulWidget {
  const UserDetailScreen({super.key, required this.user});
  final User user;

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  late final _c = TaskListController(
    context.read<TaskRepository>(),
    initial: TaskFilter(assigneeId: widget.user.id),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Задачи: ${widget.user.name}')),
    body: TaskListView(controller: _c),
  );
}
