import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/app_exception.dart';
import '../../models/enums.dart';

final dateFmt = DateFormat('dd.MM.yyyy');
final dateTimeFmt = DateFormat('dd.MM.yyyy HH:mm');

Color priorityColor(TaskPriority p) => switch (p) {
  TaskPriority.low => Colors.blueGrey,
  TaskPriority.medium => Colors.blue,
  TaskPriority.high => Colors.orange,
  TaskPriority.critical => Colors.red,
};

Color statusColor(TaskStatus s) => switch (s) {
  TaskStatus.todo => Colors.grey,
  TaskStatus.inProgress => Colors.indigo,
  TaskStatus.done => Colors.green,
  TaskStatus.cancelled => Colors.brown,
};

IconData statusIcon(TaskStatus s) => switch (s) {
  TaskStatus.todo => Icons.radio_button_unchecked,
  TaskStatus.inProgress => Icons.timelapse,
  TaskStatus.done => Icons.check_circle,
  TaskStatus.cancelled => Icons.cancel_outlined,
};

void showSnack(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade700 : null,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Выполняет действие и показывает бизнес-ошибки пользователю.
Future<bool> guard(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (success != null && context.mounted) showSnack(context, success);
    return true;
  } on AppException catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Ошибка: $e', error: true);
  }
  return false;
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String ok = 'Удалить',
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Отмена'),
        ),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    ),
  );
}

class Pill extends StatelessWidget {
  const Pill(this.text, this.color, {super.key});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.take(2).map((e) => e.isEmpty ? '' : e[0].toUpperCase()).join();
}
