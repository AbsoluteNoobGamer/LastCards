import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

void main() {
  Directory('assets/audio').createSync(recursive: true);

  // Soft pop for click (short duration, low volume, sine)
  writeWav('assets/audio/click.wav', 0.05, 400, 'pop', 0.1);

  // Swoosh for card play (fast decay, noise + sweep down)
  writeWav('assets/audio/swoosh.wav', 0.15, 600, 'swoosh', 0.25);

  // Soft, lower pop for drag (very short, lower pitch)
  writeWav('assets/audio/drag.wav', 0.08, 200, 'pop', 0.08);

  // Instrumental BGM (8 second loop of a soft electric piano arpeggio)
  writeBgmWav('assets/audio/bgm.wav', 8.0, 0.06);

  print('Audio files updated with swoosh and BGM.');
}

void writeWav(
    String path, double durationSecs, double freq, String type, double maxVol) {
  final file = File(path);
  final sampleRate = 44100;
  final numSamples = (durationSecs * sampleRate).toInt();

  final numChannels = 1;
  final byteRate = sampleRate * numChannels * 2;
  final blockAlign = numChannels * 2;

  final dataSize = numSamples * 2;
  final fileSize = 36 + dataSize;

  final builder = BytesBuilder();
  builder.add('RIFF'.codeUnits);
  builder.add(_int32ToBytes(fileSize));
  builder.add('WAVE'.codeUnits);
  builder.add('fmt '.codeUnits);
  builder.add(_int32ToBytes(16)); // Chunk size
  builder.add(_int16ToBytes(1)); // Audio format (PCM)
  builder.add(_int16ToBytes(numChannels));
  builder.add(_int32ToBytes(sampleRate));
  builder.add(_int32ToBytes(byteRate));
  builder.add(_int16ToBytes(blockAlign));
  builder.add(_int16ToBytes(16)); // Bits per sample
  builder.add('data'.codeUnits);
  builder.add(_int32ToBytes(dataSize));

  for (int i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    double sample = 0;

    if (type == 'pop') {
      // Fast exponential decay for a soft "pop" or "blip"
      final env = exp(-t * 30);
      sample = sin(2 * pi * freq * t) * env;
    } else if (type == 'swoosh') {
      // Envelope for sharp attack, smooth decay
      final env = t < 0.05 ? (t / 0.05) : exp(-(t - 0.05) * 15);
      final noise = (Random().nextDouble() * 2 - 1) * 0.4;
      // Fast frequency sweep down
      final sweep = sin(2 * pi * (freq - (400 * t)) * t);
      sample = (sweep + noise) * env;
    }

    sample *= maxVol;

    final val = (sample * 32767).toInt().clamp(-32768, 32767);
    builder.add(_int16ToBytes(val));
  }

  file.writeAsBytesSync(builder.takeBytes());
}

void writeBgmWav(String path, double durationSecs, double maxVol) {
  final file = File(path);
  final sampleRate = 44100;
  final numSamples = (durationSecs * sampleRate).toInt();

  // Buffer to accumulate audio
  final buffer = List<double>.filled(numSamples, 0.0);

  // Simple sequencer
  // Notes: A minor 7 arpeggio (A2, C3, E3, G3)
  final bpm = 120.0;
  final beatDuration = 60.0 / bpm; // 0.5s

  // Eighth notes
  final sequence = [
    [110.0, 164.81], // A2 + E3
    [130.81], // C3
    [164.81], // E3
    [196.00], // G3
    [220.0, 164.81], // A3 + E3
    [196.00], // G3
    [164.81], // E3
    [130.81], // C3
  ];

  void addNote(double freq, double startTimeSec, double noteVol) {
    final startSample = (startTimeSec * sampleRate).toInt();
    for (int i = 0; i < sampleRate * 2; i++) {
      // Note rings for 2s max
      final sampleIdx = startSample + i;
      if (sampleIdx >= numSamples) break;

      final t = i / sampleRate;

      // Electric piano-ish timbre: Fundamental + slightly detuned 2nd harmonic
      final fundamental = sin(2 * pi * freq * t);
      final harmonic = 0.3 * sin(2 * pi * (freq * 2.01) * t);

      // Envelope: sharp attack, exponential decay
      final attack = min(1.0, t / 0.01); // 10ms attack
      final decay = exp(-t * 3.0); // decay rate

      final env = attack * decay;

      buffer[sampleIdx] += (fundamental + harmonic) * env * noteVol;
    }
  }

  for (int bar = 0; bar < 4; bar++) {
    // 4 bars = 8 seconds total
    for (int beat = 0; beat < sequence.length; beat++) {
      final startTime =
          bar * sequence.length * beatDuration / 2 + beat * beatDuration / 2;
      for (final freq in sequence[beat]) {
        addNote(freq, startTime, 1.0);
      }
    }
  }

  final numChannels = 1;
  final byteRate = sampleRate * numChannels * 2;
  final blockAlign = numChannels * 2;

  final dataSize = numSamples * 2;
  final fileSize = 36 + dataSize;

  final builder = BytesBuilder();
  builder.add('RIFF'.codeUnits);
  builder.add(_int32ToBytes(fileSize));
  builder.add('WAVE'.codeUnits);
  builder.add('fmt '.codeUnits);
  builder.add(_int32ToBytes(16)); // Chunk size
  builder.add(_int16ToBytes(1)); // Audio format (PCM)
  builder.add(_int16ToBytes(numChannels));
  builder.add(_int32ToBytes(sampleRate));
  builder.add(_int32ToBytes(byteRate));
  builder.add(_int16ToBytes(blockAlign));
  builder.add(_int16ToBytes(16)); // Bits per sample
  builder.add('data'.codeUnits);
  builder.add(_int32ToBytes(dataSize));

  for (int i = 0; i < numSamples; i++) {
    var sample = buffer[i] * maxVol;

    // Smooth fade out at the very end to prevent popping on loop boundary
    if (i > numSamples - 4410) {
      // last 100ms
      sample *= (numSamples - i) / 4410.0;
    }

    final val = (sample * 32767).toInt().clamp(-32768, 32767);
    builder.add(_int16ToBytes(val));
  }

  file.writeAsBytesSync(builder.takeBytes());
}

List<int> _int32ToBytes(int value) {
  return [
    (value & 0xff),
    ((value >> 8) & 0xff),
    ((value >> 16) & 0xff),
    ((value >> 24) & 0xff)
  ];
}

List<int> _int16ToBytes(int value) {
  return [(value & 0xff), ((value >> 8) & 0xff)];
}
