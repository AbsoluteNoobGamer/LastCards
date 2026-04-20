// Regenerate: dart run tool/generate_timer_tick_wav.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Soft quartz-watch style tick: very short, low level, gentle decay.
void main() {
  const sampleRate = 44100;
  const duration = 0.032;
  final n = (sampleRate * duration).round();
  const fHi = 3800.0;
  const fLo = 720.0;
  final samples = Int16List(n);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final attack = 1 - math.exp(-t * 2000);
    final decay = math.exp(-t * 95);
    final env = attack * decay;
    final v = env *
        (0.72 * math.sin(2 * math.pi * fHi * t) +
            0.28 * math.sin(2 * math.pi * fLo * t));
    samples[i] = (v * 5200).round().clamp(-32767, 32767);
  }
  final pcm = samples.buffer.asUint8List();
  final header = _wavHeader(pcm.length, sampleRate);
  final out = File('assets/audio/sfx/timer_tick.wav');
  out.writeAsBytesSync([...header, ...pcm], flush: true);
  // ignore: avoid_print
  print('Wrote ${out.path} (${out.lengthSync()} bytes)');
}

Uint8List _wavHeader(int pcmByteLength, int sampleRate) {
  final byteRate = sampleRate * 2;
  const blockAlign = 2;
  final chunkSize = 36 + pcmByteLength;
  final b = BytesBuilder();
  void w32(int v) {
    b.add([
      v & 0xff,
      (v >> 8) & 0xff,
      (v >> 16) & 0xff,
      (v >> 24) & 0xff,
    ]);
  }

  void w16(int v) {
    b.add([v & 0xff, (v >> 8) & 0xff]);
  }

  b.add('RIFF'.codeUnits);
  w32(chunkSize);
  b.add('WAVE'.codeUnits);
  b.add('fmt '.codeUnits);
  w32(16);
  w16(1);
  w16(1);
  w32(sampleRate);
  w32(byteRate);
  w16(blockAlign);
  w16(16);
  b.add('data'.codeUnits);
  w32(pcmByteLength);
  return b.toBytes();
}
