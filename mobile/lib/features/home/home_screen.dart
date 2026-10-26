import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../shared/widgets.dart';
import '../../core/localization.dart';

class LanguagePairPicker extends ConsumerWidget {
  const LanguagePairPicker({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pair = ref.watch(languagePairProvider);
    return ref
        .watch(languagesProvider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Column(
            children: [
              Text(context.errorText(e)),
              TextButton(
                onPressed: () => ref.invalidate(languagesProvider),
                child: Text(context.tr('Retry languages')),
              ),
            ],
          ),
          data: (languages) => Column(
            children: [
              for (final side in [0, 1])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    initialValue:
                        languages.contains(side == 0 ? pair.$1 : pair.$2)
                        ? (side == 0 ? pair.$1 : pair.$2)
                        : null,
                    decoration: InputDecoration(
                      labelText: side == 0
                          ? context.tr('I speak')
                          : context.tr('My partner speaks'),
                    ),
                    items: languages
                        .map(
                          (code) => DropdownMenuItem(
                            value: code,
                            child: Text(context.languageName(code)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(languagePairProvider.notifier).state =
                            side == 0 ? (value, pair.$2) : (pair.$1, value);
                      }
                    },
                  ),
                ),
              TextButton.icon(
                onPressed: () => ref.read(languagePairProvider.notifier).state =
                    (pair.$2, pair.$1),
                icon: const Icon(Icons.swap_vert),
                label: Text(context.tr('Swap languages')),
              ),
            ],
          ),
        );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageFrame(
    title: 'AI Live Translator',
    actions: [
      IconButton(
        onPressed: () => context.push('/settings'),
        tooltip: context.tr('Settings'),
        icon: const Icon(Icons.tune),
      ),
    ],
    children: [
      Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [Color(0xff11244b), Color(0xff2458b7)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.graphic_eq_rounded,
              color: Color(0xff9cc6ff),
              size: 44,
            ),
            const SizedBox(height: 24),
            Text(
              context.tr('Say hello.\nBe understood.'),
              style: Theme.of(
                context,
              ).textTheme.headlineLarge?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('Private rooms. Two phones. Your own headphones.'),
              style: const TextStyle(color: Color(0xffd6e4ff)),
            ),
          ],
        ),
      ),
      const LanguagePairPicker(),
      FilledButton.icon(
        onPressed: () => context.push('/create'),
        icon: const Icon(Icons.add),
        label: Text(context.tr('Start a conversation')),
      ),
      OutlinedButton.icon(
        onPressed: () => context.push('/join'),
        icon: const Icon(Icons.login),
        label: Text(context.tr('Join with a code')),
      ),
      for (final item in [
        (context.tr('History'), '/history', Icons.history),
        (context.tr('Audio devices'), '/devices', Icons.headphones),
        (context.tr('Plan & usage'), '/subscription', Icons.bolt),
      ])
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(item.$3),
          title: Text(item.$1),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(item.$2),
        ),
    ],
  );
}
