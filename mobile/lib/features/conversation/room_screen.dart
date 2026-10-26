import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/api.dart';
import '../../shared/widgets.dart';
import '../../core/localization.dart';
import '../home/home_screen.dart';

class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({super.key, required this.join});
  final bool join;
  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  final code = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> scan() async {
    final result = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _ScannerScreen()));
    if (result != null && mounted) setState(() => code.text = result);
  }

  Future<void> submit() async {
    setState(() => busy = true);
    await runAction(context, () async {
      final pair = ref.read(languagePairProvider);
      final result =
          await ref.read(apiProvider).request(
                'POST',
                widget.join ? '/conversations/join' : '/conversations',
                {
                  'source_language': pair.$1,
                  'target_language': pair.$2,
                  if (widget.join)
                    'code': code.text.trim().toUpperCase().replaceAll(' ', ''),
                },
              )
              as Map<String, dynamic>;
      if (mounted) {
        context.go('/live/${result['id']}', extra: result['code'] as String?);
      }
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: widget.join
        ? context.tr('Join a conversation')
        : context.tr('Your conversation'),
    children: [
      const LanguagePairPicker(),
      if (widget.join)
        TextField(
          controller: code,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[a-zA-Z2-9 ]')),
          ],
          decoration: InputDecoration(
            labelText: context.tr('16-character room code'),
            hintText: context.tr('Paste the host’s code'),
          ),
        ),
      if (widget.join)
        OutlinedButton.icon(
          onPressed: busy ? null : scan,
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(context.tr('Scan invitation QR')),
        ),
      InfoCard(
        title: widget.join
            ? context.tr('Use the reverse language pair')
            : context.tr('Invite one person'),
        body: widget.join
            ? context.tr(
                'If the host speaks English and you speak German, choose German → English.',
              )
            : context.tr(
                'Your code can admit one signed-in partner, once. Rooms expire after one hour.',
              ),
      ),
      FilledButton(
        onPressed: busy ? null : submit,
        child: Text(
          busy
              ? context.tr('Connecting…')
              : widget.join
              ? context.tr('Join securely')
              : context.tr('Create room'),
        ),
      ),
    ],
  );
}

class _ScannerScreen extends StatefulWidget {
  const _ScannerScreen();
  @override
  State<_ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<_ScannerScreen> {
  final scanner = MobileScannerController();
  bool detected = false;
  @override
  void dispose() {
    scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('Scan invitation'))),
    body: MobileScanner(
      controller: scanner,
      onDetect: (capture) {
        if (detected) return;
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue;
          if (value != null &&
              RegExp(r'^[A-HJ-NP-Z2-9]{16}$').hasMatch(value)) {
            detected = true;
            Navigator.pop(context, value);
            return;
          }
        }
      },
    ),
  );
}
