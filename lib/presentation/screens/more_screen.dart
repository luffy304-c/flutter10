import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_controller.dart';
import '../widgets/common.dart';
import 'perf_screen.dart';
import 'trash_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Ещё')),
      body: ListView(
        children: [
          const SectionTitle('Текущий пользователь'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'От его имени записывается история изменений и комментарии.',
            ),
          ),
          for (final u in app.users.take(20))
            RadioListTile<int>(
              value: u.id,
              groupValue: app.currentUser?.id,
              onChanged: (v) => app.setCurrent(v!),
              title: Text(u.name),
              subtitle: Text(u.email),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Корзина задач'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TrashScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Производительность и индексы'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PerfScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
