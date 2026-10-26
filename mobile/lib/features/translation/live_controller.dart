import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'package:audio_session/audio_session.dart';
import 'package:audioplayers/audioplayers.dart' hide AVAudioSessionCategory;
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/api.dart';
import '../../core/config.dart';
import 'wav.dart';

class TranscriptTurn {
  TranscriptTurn(this.original, this.translated, this.mine);
  final String original, translated;
  final bool mine;
}

class LiveController extends ChangeNotifier {
  LiveController(this.api, this.roomId, this.userId);
  final Api api;
  final String roomId, userId;
  final recorder = AudioRecorder();
  final player = AudioPlayer();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSub;
  StreamSubscription<Uint8List>? _recordSub;
  final List<StreamSubscription<dynamic>> _audioSubs = [];
  final List<TranscriptTurn> turns = [];
  final Queue<Uint8List> _playback = Queue();
  final BytesBuilder _pcm = BytesBuilder(copy: false);
  Timer? _recordTimer, _watchdog;
  Completer<void>? _stopPlayback;
  Future<void>? _draining;
  Future<void>? _pausing;
  int _generation = 0;
  DateTime _lastMessage = DateTime.now();
  bool connected = false,
      recording = false,
      processing = false,
      playing = false;
  bool connecting = false,
      muted = false,
      autoplay = true,
      _disposed = false,
      _starting = false;
  double volume = 0.8;
  String status = 'Connect when both people are ready';
  String? error;
  int _recordBytes = 0;
  bool get canRecord =>
      connected &&
      !recording &&
      !processing &&
      !playing &&
      !muted &&
      !_starting;
  void update() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Permission.bluetoothConnect.request();
    }
    if (_disposed) return;
    if (!kIsWeb) {
      final session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.allowBluetoothA2dp,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        ),
      );
      if (_disposed) return;
      _audioSubs.add(
        session.becomingNoisyEventStream.listen((_) {
          unawaited(
            pause(
              'Audio route changed. Check your headphones, then reconnect.',
            ),
          );
        }),
      );
      _audioSubs.add(
        session.interruptionEventStream.listen((event) {
          if (event.begin) {
            unawaited(pause('Audio was interrupted. Reconnect when ready.'));
          }
        }),
      );
      _audioSubs.add(
        session.devicesChangedEventStream.listen((event) {
          if (event.devicesRemoved.isNotEmpty) {
            unawaited(
              pause(
                'An audio device disconnected. Check your output, then reconnect.',
              ),
            );
          }
        }),
      );
    }
    final preferences = await api.auth
        .from('user_preferences')
        .select('auto_play_translation')
        .eq('user_id', userId)
        .single();
    if (_disposed) return;
    autoplay = preferences['auto_play_translation'] as bool;
    update();
  }

  Future<void> connect() async {
    if (connecting || connected) return;
    connecting = true;
    error = null;
    update();
    try {
      await pause('Connecting…');
      final attempt = _generation;
      final ticket =
          await api.request('POST', '/ai/session', {
                'conversation_id': roomId,
                'consent_to_processing': true,
              })
              as Map<String, dynamic>;
      if (_disposed || attempt != _generation) return;
      final uri = Uri.parse('${AppConfig.apiUrl}${ticket['socket_path']}');
      _channel = WebSocketChannel.connect(
        uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws'),
      );
      await _channel!.ready.timeout(const Duration(seconds: 10));
      if (_disposed || attempt != _generation) return;
      _channel!.sink.add(jsonEncode({'token': ticket['token']}));
      _lastMessage = DateTime.now();
      _socketSub = _channel!.stream.listen(
        _event,
        onDone: () {
          unawaited(pause('Connection closed. Reconnect to continue.'));
        },
        onError: (Object _) {
          unawaited(pause('Connection lost. Reconnect to continue.'));
        },
      );
      _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
        if (DateTime.now().difference(_lastMessage).inSeconds > 20) {
          unawaited(
            pause('Connection timed out. Check your internet and reconnect.'),
          );
        }
      });
    } catch (e) {
      await pause('Could not connect');
      error = e.toString();
    } finally {
      connecting = false;
      update();
    }
  }

  void _event(dynamic raw) {
    if (_disposed) return;
    try {
      _lastMessage = DateTime.now();
      final event = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (event['type']) {
        case 'connected':
          connected = true;
          status = 'Ready · tap the microphone to speak';
        case 'processing':
          processing = true;
          status = 'Translating your turn…';
        case 'ready':
          processing = false;
          status = 'Ready · tap the microphone to speak';
        case 'error':
          processing = false;
          error = event['message'] as String;
        case 'translation':
          turns.add(
            TranscriptTurn(
              event['original'] as String,
              event['translated'] as String,
              event['speaker_id'] == userId,
            ),
          );
          if (turns.length > 40) turns.removeAt(0);
          final encoded = event['audio'] as String;
          if (autoplay && encoded.isNotEmpty) {
            if (_playback.length >= 3) {
              error = 'Playback queue is full. Pause between turns.';
            } else {
              _playback.add(base64Decode(encoded));
              drain();
            }
          }
      }
      update();
    } catch (_) {
      error = 'Received an invalid audio event.';
      update();
    }
  }

  Future<void> startRecording() async {
    if (!canRecord) return;
    _starting = true;
    error = null;
    update();
    try {
      if (!await recorder.hasPermission()) {
        throw const AppFailure('Microphone permission is required.');
      }
      if (!connected || _disposed || playing) return;
      _pcm.clear();
      _recordBytes = 0;
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: true,
        ),
      );
      if (!connected || _disposed) {
        await recorder.stop();
        return;
      }
      recording = true;
      status = 'Listening · tap again to translate';
      _recordSub = stream.listen(
        (data) {
          if (_recordBytes + data.length > 384000) {
            unawaited(stopRecording());
            return;
          }
          _pcm.add(data);
          _recordBytes += data.length;
        },
        onError: (Object _) {
          unawaited(pause('Microphone stopped. Check audio permissions.'));
        },
      );
      _recordTimer = Timer(
        const Duration(seconds: 12),
        () => unawaited(stopRecording()),
      );
    } catch (e) {
      error = e.toString();
    } finally {
      _starting = false;
      update();
      drain();
    }
  }

  Future<void> stopRecording() async {
    if (!recording) return;
    final generation = _generation;
    recording = false;
    _recordTimer?.cancel();
    processing = true;
    update();
    try {
      await recorder.stop();
      if (_disposed || generation != _generation) return;
      await _recordSub?.cancel();
      if (_disposed || generation != _generation) return;
      _recordSub = null;
      final pcm = _pcm.takeBytes();
      if (pcm.length < 3200 || !connected) {
        processing = false;
        error = 'Speak for at least a moment before stopping.';
      } else {
        _channel!.sink.add(pcmToWav(pcm));
        status = 'Sending your turn…';
      }
    } catch (_) {
      processing = false;
      error = 'Could not send audio. Reconnect and try again.';
    }
    update();
    drain();
  }

  void drain() {
    if (recording ||
        _starting ||
        playing ||
        _disposed ||
        !connected ||
        _playback.isEmpty) {
      return;
    }
    _draining = _drain();
  }

  Future<void> _drain() async {
    if (recording || _starting || playing || _disposed || !connected) return;
    playing = true;
    update();
    _stopPlayback = Completer<void>();
    try {
      while (_playback.isNotEmpty && connected && autoplay && !_disposed) {
        final completed = player.onPlayerComplete.first;
        await player.play(
          BytesSource(_playback.removeFirst(), mimeType: 'audio/mpeg'),
          volume: volume,
        );
        await Future.any([
          completed,
          _stopPlayback!.future,
        ]).timeout(const Duration(seconds: 45));
      }
    } catch (_) {
      if (!_disposed && connected) {
        error = 'Playback interrupted. Check your audio device.';
      }
    } finally {
      playing = false;
      update();
    }
  }

  Future<void> setAutoplay(bool value) async {
    autoplay = value;
    if (!value) {
      _playback.clear();
      if (_stopPlayback?.isCompleted == false) _stopPlayback!.complete();
      await player.stop();
    }
    update();
  }

  Future<void> setMuted(bool value) async {
    muted = value;
    if (recording) {
      recording = false;
      _recordTimer?.cancel();
      await recorder.stop();
      await _recordSub?.cancel();
      _recordSub = null;
      _pcm.clear();
    }
    update();
  }

  Future<void> setVolume(double value) async {
    volume = value;
    await player.setVolume(value);
    update();
  }

  Future<void> pause(String message) {
    if (_disposed) return Future.value();
    final pending = _pausing;
    if (pending != null) return pending;
    final cleanup = _pause(message);
    _pausing = cleanup;
    return cleanup.whenComplete(() => _pausing = null);
  }

  Future<void> _pause(String message) async {
    _generation++;
    connected = false;
    processing = false;
    recording = false;
    status = message;
    _recordTimer?.cancel();
    _watchdog?.cancel();
    update();
    await _recordSub?.cancel();
    _recordSub = null;
    await recorder.stop();
    _pcm.clear();
    _playback.clear();
    if (_stopPlayback?.isCompleted == false) _stopPlayback!.complete();
    await player.stop();
    await _draining;
    await _socketSub?.cancel();
    _socketSub = null;
    await _channel?.sink.close();
    _channel = null;
    update();
  }

  @override
  void dispose() {
    _generation++;
    _disposed = true;
    _recordTimer?.cancel();
    _watchdog?.cancel();
    for (final sub in _audioSubs) {
      sub.cancel();
    }
    _recordSub?.cancel();
    _socketSub?.cancel();
    _channel?.sink.close();
    if (_stopPlayback?.isCompleted == false) _stopPlayback!.complete();
    recorder.dispose();
    player.dispose();
    _pcm.clear();
    _playback.clear();
    turns.clear();
    super.dispose();
  }
}
