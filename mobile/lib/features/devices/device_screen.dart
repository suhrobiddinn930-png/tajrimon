import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../shared/widgets.dart';
import '../../core/localization.dart';

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key});
  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  Set<AudioDevice>? devices;
  String? error;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    if (kIsWeb) {
      setState(() {
        devices = <AudioDevice>{};
        error =
            'Use your browser and system audio settings to select a microphone and headphones. '
            'Bluetooth route discovery is available only in the mobile app.';
      });
      return;
    }
    try {
      final session = await AudioSession.instance;
      final result = await session.getDevices();
      if (mounted) {
        setState(() {
          devices = result;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Device discovery is unavailable on this platform.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: context.tr('Audio devices'),
    children: [
      InfoCard(
        title: context.tr('Pair in your phone settings'),
        body: context.tr(
          'Connect Bluetooth headphones using the system Bluetooth settings. Routing is managed by the operating system. '
          'The devices below are available devices; this list does not confirm the current output route.',
        ),
      ),
      if (error != null) Text(context.tr(error!)),
      if (devices == null && error == null) const LinearProgressIndicator(),
      for (final device in devices ?? <AudioDevice>{})
        ListTile(
          leading: Icon(device.isInput ? Icons.mic_none : Icons.headphones),
          title: Text(device.name),
          subtitle: Text(
            device.isInput
                ? context.tr('Available input')
                : context.tr('Available output'),
          ),
        ),
      FilledButton(
        onPressed: refresh,
        child: Text(context.tr('Refresh devices')),
      ),
      Text(
        context.tr(
          'If headphones disconnect or a phone call interrupts audio, translation pauses. '
          'Check your output and reconnect. Background translation is disabled in this MVP.',
        ),
      ),
    ],
  );
}
