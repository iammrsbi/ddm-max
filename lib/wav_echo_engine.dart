import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class WavEchoEngine {
  /// Processes uncompressed 16-bit PCM WAV (mono or stereo) and writes a new WAV.
  static Future<File> render({
    required File input,
    required Directory outputDirectory,
    required int delayMs,
    required double feedback,
    required double mix,
    required double level,
  }) async {
    final bytes = await input.readAsBytes();
    if (bytes.length < 44 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('Valid WAV audio file nahi hai.');
    }

    final data = ByteData.sublistView(bytes);
    int offset = 12;
    int? channels, sampleRate, bits, audioFormat, dataStart, dataLength;
    while (offset + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = data.getUint32(offset + 4, Endian.little);
      final start = offset + 8;
      if (start + size > bytes.length) break;
      if (id == 'fmt ' && size >= 16) {
        audioFormat = data.getUint16(start, Endian.little);
        channels = data.getUint16(start + 2, Endian.little);
        sampleRate = data.getUint32(start + 4, Endian.little);
        bits = data.getUint16(start + 14, Endian.little);
      } else if (id == 'data') {
        dataStart = start;
        dataLength = size;
        break;
      }
      offset = start + size + (size.isOdd ? 1 : 0);
    }
    if (audioFormat != 1 || bits != 16 || channels == null ||
        sampleRate == null || dataStart == null || dataLength == null ||
        (channels != 1 && channels != 2)) {
      throw const FormatException('Sirf PCM 16-bit mono/stereo WAV supported hai.');
    }

    final frames = dataLength ~/ (channels * 2);
    final delayFrames = math.max(1, (sampleRate * delayMs / 1000).round());
    final samples = Int16List(frames * channels);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = data.getInt16(dataStart + i * 2, Endian.little);
    }
    final output = Int16List(samples.length);
    final fb = feedback.clamp(0.0, 0.92);
    final wetMix = mix.clamp(0.0, 1.0);
    final gain = level.clamp(0.0, 1.5);

    for (var frame = 0; frame < frames; frame++) {
      for (var ch = 0; ch < channels; ch++) {
        final index = frame * channels + ch;
        final dry = samples[index].toDouble();
        final delayedFrame = frame - delayFrames;
        final delayed = delayedFrame >= 0
            ? output[delayedFrame * channels + ch].toDouble()
            : 0.0;
        final wet = dry + delayed * fb;
        final value = (dry * (1 - wetMix) + wet * wetMix) * gain;
        output[index] = value.round().clamp(-32768, 32767);
      }
    }

    final payload = BytesBuilder();
    for (final sample in output) {
      final b = ByteData(2)..setInt16(0, sample, Endian.little);
      payload.add(b.buffer.asUint8List());
    }
    final pcm = payload.takeBytes();
    final result = BytesBuilder();
    void putText(String value) => result.add(value.codeUnits);
    void put16(int value) {
      final b = ByteData(2)..setUint16(0, value, Endian.little);
      result.add(b.buffer.asUint8List());
    }
    void put32(int value) {
      final b = ByteData(4)..setUint32(0, value, Endian.little);
      result.add(b.buffer.asUint8List());
    }
    putText('RIFF'); put32(36 + pcm.length); putText('WAVE');
    putText('fmt '); put32(16); put16(1); put16(channels);
    put32(sampleRate); put32(sampleRate * channels * 2);
    put16(channels * 2); put16(16); putText('data'); put32(pcm.length);
    result.add(pcm);

    await outputDirectory.create(recursive: true);
    final name = input.uri.pathSegments.isEmpty ? 'audio' : input.uri.pathSegments.last;
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final out = File('${outputDirectory.path}/${DateTime.now().millisecondsSinceEpoch}_echo_$safeName.wav');
    await out.writeAsBytes(result.takeBytes(), flush: true);
    return out;
  }
}
