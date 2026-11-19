import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/bench_controller.dart';
import '../widgets/common.dart';

/// Тестовая БД (1000 пользователей / 100 проектов / 10 000 задач)
/// и сравнение скорости запросов с индексами и без них.
class PerfScreen extends StatelessWidget {
  const PerfScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => BenchController(),
    child: const _View(),
  );
}

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BenchController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Производительность')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Основная база уже содержит 1000 пользователей, 100 проектов и 10 000 задач. Здесь создаётся отдельная копия такого объёма (1000 пользователей, 100 проектов, '
            '10 000 задач). Каждый запрос выполняется 5 раз без индексов, затем с индексами; '
            'показано среднее время.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: c.running ? null : c.runFull,
            icon: const Icon(Icons.speed),
            label: const Text('Создать тестовую БД и сравнить'),
          ),
          const SizedBox(height: 16),
          if (c.running)
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(c.stage),
              ],
            ),
          if (c.error != null)
            Text(c.error!, style: const TextStyle(color: Colors.red)),
          if (c.seedTime != null)
            Text(
              'БД создана за ${c.seedTime!.inMilliseconds} мс: ${c.users} польз., ${c.projects} проектов, ${c.tasks} задач.',
            ),
          const SizedBox(height: 8),
          for (final r in c.results)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'без индексов: ${r.withoutIndexMs.toStringAsFixed(2)} мс',
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'с индексами: ${r.withIndexMs.toStringAsFixed(2)} мс',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Pill(
                      r.speedup >= 1.15
                          ? 'быстрее в ${r.speedup.toStringAsFixed(1)}×'
                          : 'без заметной разницы (${r.speedup.toStringAsFixed(1)}×)',
                      r.speedup >= 1.15 ? Colors.green : Colors.grey,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
