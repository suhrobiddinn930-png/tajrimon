import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/localization.dart';

Future<void> runAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.errorText(error))));
    }
  }
}

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.children,
    this.actions,
  });
  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: [const InterfaceLanguageMenu(), ...?actions],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              for (final child in children)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: child,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class InterfaceLanguageMenu extends ConsumerWidget {
  const InterfaceLanguageMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(appLocaleProvider);
    return PopupMenuButton<String>(
      tooltip: context.tr('Interface language'),
      initialValue: selected,
      icon: const Icon(Icons.language),
      onSelected: (code) => runAction(
        context,
        () => ref.read(appLocaleProvider.notifier).select(code),
      ),
      itemBuilder: (_) => [
        for (final entry in {
          ...uiLanguageNames,
          'system': context.tr('Device language'),
        }.entries)
          PopupMenuItem(
            value: entry.key,
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: selected == entry.key
                      ? const Icon(Icons.check, size: 18)
                      : null,
                ),
                Text(entry.value),
              ],
            ),
          ),
      ],
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.info_outline,
  });
  final String title, body;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
