import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../shared/widgets.dart';
import '../../core/localization.dart';
import 'live_controller.dart';

class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key, required this.roomId, this.code});
  final String roomId;
  final String? code;
  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen>
    with WidgetsBindingObserver {
  late final LiveController audio;
  Conversation? room;
  String? roomError;
  Timer? poll;
  RealtimeChannel? realtime;
  bool _loading = false, consent = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final api = ref.read(apiProvider);
    audio = LiveController(api, widget.roomId, api.auth.auth.currentUser!.id);
    unawaited(runAction(context, audio.initialize));
    unawaited(refresh());
    poll = Timer.periodic(
      const Duration(seconds: 8),
      (_) => unawaited(refresh()),
    );
    realtime = api.auth
        .channel('room:${widget.roomId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.roomId,
          ),
          callback: (_) => unawaited(refresh()),
        )
        .subscribe();
  }

  Future<void> refresh() async {
    if (_loading || !mounted) return;
    _loading = true;
    try {
      final result = await ref.read(apiProvider).room(widget.roomId);
      if (mounted) {
        setState(() {
          room = result;
          roomError = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => roomError = error.toString());
      await audio.pause('Room unavailable. Check connection or return home.');
    } finally {
      _loading = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(
        audio.pause(
          'Audio paused while the app is inactive. Reconnect to continue.',
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    poll?.cancel();
    if (realtime != null) ref.read(supabaseProvider).removeChannel(realtime!);
    audio.dispose();
    super.dispose();
  }

  Future<void> leave() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('End this conversation?')),
        content: Text(
          context.tr(
            'This closes the room for both people and clears the on-screen transcript.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('Keep talking')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('End conversation')),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    await runAction(context, () async {
      await audio.pause('Ending conversation…');
      await ref
          .read(apiProvider)
          .request('POST', '/conversations/${widget.roomId}/leave');
      ref.invalidate(historyProvider);
      ref.invalidate(allowanceProvider);
      if (mounted) context.go('/');
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: audio,
    builder: (context, _) => PageFrame(
      title: context.tr('Conversation'),
      actions: [
        IconButton(
          onPressed: () => context.go('/'),
          tooltip: context.tr('Pause and return home'),
          icon: const Icon(Icons.home_outlined),
        ),
      ],
      children: [
        if (roomError != null)
          InfoCard(
            title: context.tr('Room unavailable'),
            body: context.errorText(roomError!),
          ),
        if (room == null && roomError == null) const LinearProgressIndicator(),
        if (room != null) ...[
          Text(
            room!.status == 'waiting'
                ? context.tr('Waiting for your partner')
                : context.tr('Two voices. One connection.'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          for (final p in room!.participants)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Text(
                  p.name.isEmpty ? '?' : p.name.characters.first.toUpperCase(),
                ),
              ),
              title: Text(p.name),
              subtitle: Text(
                '${context.languageName(p.source)} → ${context.languageName(p.target)}',
              ),
            ),
          if (room!.status == 'waiting' && widget.code != null) ...[
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(data: widget.code!, size: 180),
              ),
            ),
            SelectableText(
              widget.code!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: widget.code!)),
              icon: const Icon(Icons.copy),
              label: Text(context.tr('Copy invitation code')),
            ),
            Text(
              context.tr(
                'Choose Join → Scan invitation QR on the other phone, or copy the code. Only one partner can use it.',
              ),
            ),
          ],
        ],
        InfoCard(
          title: context.tr('Short turns · AI generated voice'),
          body: context.tr(
            'Use headphones. Tap to speak, then tap to translate (up to 12 seconds). '
            'Speech and text are sent to the AI provider. The on-screen transcript is temporary.',
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: consent,
          onChanged: audio.connected
              ? null
              : (value) => setState(() => consent = value ?? false),
          title: Text(
            context.tr(
              'I agree to AI speech processing and have checked my audio output.',
            ),
          ),
        ),
        if (!audio.connected)
          FilledButton.icon(
            onPressed: consent && room?.status == 'active' && !audio.connecting
                ? audio.connect
                : null,
            icon: const Icon(Icons.link),
            label: Text(
              audio.connecting
                  ? context.tr('Connecting…')
                  : context.tr('Connect / reconnect audio'),
            ),
          ),
        Text(
          context.tr(audio.status),
          textAlign: TextAlign.center,
          semanticsLabel: context.tr(audio.status),
        ),
        if (audio.error != null)
          Text(
            context.errorText(audio.error!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Center(
          child: Semantics(
            label: audio.recording
                ? context.tr('Stop and translate')
                : context.tr('Start speaking'),
            button: true,
            child: SizedBox(
              width: 112,
              height: 112,
              child: FilledButton(
                style: FilledButton.styleFrom(shape: const CircleBorder()),
                onPressed: audio.recording
                    ? audio.stopRecording
                    : audio.canRecord
                    ? audio.startRecording
                    : null,
                child: Icon(
                  audio.recording ? Icons.stop_rounded : Icons.mic_rounded,
                  size: 44,
                ),
              ),
            ),
          ),
        ),
        if (audio.recording)
          StreamBuilder<Amplitude>(
            stream: audio.recorder.onAmplitudeChanged(
              const Duration(milliseconds: 100),
            ),
            builder: (context, snapshot) {
              final level = (((snapshot.data?.current ?? -60) + 60) / 60)
                  .clamp(0.0, 1.0)
                  .toDouble();
              return Semantics(
                label: context.tr('Microphone input level'),
                child: SizedBox(
                  height: 56,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 17; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          width: 5,
                          height: 4 + level * (48 - (i - 8).abs() * 4),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        if (audio.processing)
          LinearProgressIndicator(
            semanticsLabel: context.tr('Translation is processing'),
          ),
        Wrap(
          spacing: 12,
          children: [
            FilterChip(
              selected: audio.muted,
              label: Text(context.tr('Mute microphone')),
              onSelected: audio.setMuted,
            ),
            FilterChip(
              selected: audio.autoplay,
              label: Text(context.tr('Play translated voice')),
              onSelected: audio.setAutoplay,
            ),
          ],
        ),
        Row(
          children: [
            const Icon(Icons.volume_up_outlined),
            Expanded(
              child: Slider(
                value: audio.volume,
                label: '${(audio.volume * 100).round()}%',
                onChanged: audio.setVolume,
              ),
            ),
          ],
        ),
        for (final turn in audio.turns.reversed)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    turn.mine ? context.tr('YOU') : context.tr('PARTNER'),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(turn.original),
                  const Divider(),
                  Text(
                    turn.translated,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: leave,
          icon: const Icon(Icons.call_end),
          label: Text(context.tr('End conversation')),
        ),
      ],
    ),
  );
}
