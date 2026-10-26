import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api.dart';
import '../../shared/widgets.dart';
import '../../core/localization.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageFrame(
    title: context.tr('Conversation history'),
    children: [
      Text(context.tr('Session metadata only. No saved audio or transcripts.')),
      ref
          .watch(historyProvider)
          .when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(context.errorText(e)),
            data: (rows) => Column(
              children: [
                if (rows.isEmpty)
                  InfoCard(
                    title: context.tr('Your first hello is ahead'),
                    body: context.tr(
                      'Completed conversations will appear here.',
                    ),
                  ),
                for (final row in rows)
                  Builder(
                    builder: (context) {
                      final start = DateTime.parse(
                        row['joined_at'] as String,
                      ).toLocal();
                      final ended =
                          row['left_at'] as String? ??
                          row['conversations']?['ended_at'] as String?;
                      final duration = ended == null
                          ? null
                          : DateTime.parse(ended).difference(start);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.translate),
                        title: Text(
                          '${context.languageName(row['source_language'] as String)} ↔ ${context.languageName(row['target_language'] as String)}',
                        ),
                        subtitle: Text(
                          '${MaterialLocalizations.of(context).formatShortDate(start)} '
                          '${TimeOfDay.fromDateTime(start).format(context)} · '
                          '${duration == null ? context.tr('Open or expired') : context.tr('{seconds}s connected', {'seconds': '${duration.inSeconds}'})}',
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
      TextButton(
        onPressed: () => ref.invalidate(historyProvider),
        child: Text(context.tr('Refresh history')),
      ),
    ],
  );
}
