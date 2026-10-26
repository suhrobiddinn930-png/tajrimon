import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_live_translator/features/translation/wav.dart';

void main() {
  test(
    'PCM transport encodes little-endian mono WAV with exact payload length',
    () {
      final pcm = Uint8List.fromList([0, 0, 255, 127, 0, 128]);
      final result = pcmToWav(pcm);
      final header = ByteData.sublistView(result);
      expect(String.fromCharCodes(result.sublist(0, 4)), 'RIFF');
      expect(header.getUint32(4, Endian.little), 42);
      expect(header.getUint32(24, Endian.little), 16000);
      expect(header.getUint16(22, Endian.little), 1);
      expect(header.getUint32(40, Endian.little), pcm.length);
      expect(result.sublist(44), pcm);
    },
  );
}
