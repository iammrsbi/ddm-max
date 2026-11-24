import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class WavEchoEngine {
  static Future<File> render({
    required File input,
    required Directory outputDirectory,
    required int delayMs,
    required double feedback,
    required double mix,
    required double level,
    List<double> eq = const [0, 0, 0, 0, 0],
    bool pingPong = false,
    bool dual = false,
    bool bypass = false,
  }) async {
    final bytes = await input.readAsBytes();
    if (bytes.length < 44 || String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('Valid WAV file nahi hai.');
    }
    final data = ByteData.sublistView(bytes);
    var offset = 12;
    int? channels, sampleRate, bits, format, dataStart, dataLength;
    while (offset + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = data.getUint32(offset + 4, Endian.little);
      final start = offset + 8;
      if (start + size > bytes.length) break;
      if (id == 'fmt ' && size >= 16) {
        format = data.getUint16(start, Endian.little);
        channels = data.getUint16(start + 2, Endian.little);
        sampleRate = data.getUint32(start + 4, Endian.little);
        bits = data.getUint16(start + 14, Endian.little);
      } else if (id == 'data') {
        dataStart = start; dataLength = size; break;
      }
      offset = start + size + (size.isOdd ? 1 : 0);
    }
    if (format != 1 || bits != 16 || channels == null || sampleRate == null ||
        dataStart == null || dataLength == null || (channels != 1 && channels != 2)) {
      throw const FormatException('Sirf PCM 16-bit mono/stereo WAV supported hai.');
    }
    final frames = dataLength ~/ (channels * 2);
    final delayFrames = math.max(1, (sampleRate * delayMs / 1000).round());
    final tailFrames = bypass ? 0 : delayFrames * (dual ? 5 : 4);
    final totalFrames = frames + tailFrames;
    final dry = List<Float64List>.generate(channels, (_) => Float64List(totalFrames));
    for (var f = 0; f < frames; f++) {
      for (var c = 0; c < channels; c++) {
        dry[c][f] = data.getInt16(dataStart + (f * channels + c) * 2, Endian.little) / 32768.0;
      }
    }
    final filtered = List<Float64List>.generate(channels, (c) {
      final out = Float64List(totalFrames);
      if (bypass) { for (var i=0;i<frames;i++) { out[i]=dry[c][i]; } return out; }
      final centers = [100.0, 350.0, 1000.0, 3500.0, 9000.0];
      final gains = List<double>.generate(5, (i) => (i < eq.length ? eq[i] : 0).clamp(-12, 12).toDouble());
      // Five broad, stable peaking bands using RBJ biquad coefficients.
      var signal = dry[c];
      for (var band = 0; band < 5; band++) {
        final gain = math.pow(10, gains[band] / 40).toDouble();
        final w = 2 * math.pi * centers[band] / sampleRate;
        final alpha = math.sin(w) / (2 * 1.0);
        final cosw = math.cos(w);
        final a0 = 1 + alpha / gain;
        final b0 = (1 + alpha * gain) / a0;
        final b1 = (-2 * cosw) / a0;
        final b2 = (1 - alpha * gain) / a0;
        final a1 = (-2 * cosw) / a0;
        final a2 = (1 - alpha / gain) / a0;
        final next = Float64List(totalFrames);
        double x1=0,x2=0,y1=0,y2=0;
        for (var i=0;i<totalFrames;i++) {
          final x = signal[i];
          final y = b0*x + b1*x1 + b2*x2 - a1*y1 - a2*y2;
          next[i]=y; x2=x1; x1=x; y2=y1; y1=y;
        }
        signal = next;
      }
      return signal;
    });
    final output = List<Float64List>.generate(channels, (_) => Float64List(totalFrames));
    final fb = feedback.clamp(0.0, 0.92);
    final wet = mix.clamp(0.0, 1.0);
    final gain = level.clamp(0.0, 1.5);
    final lineL = Float64List(delayFrames + 1);
    final lineR = Float64List((dual ? delayFrames * 3 : delayFrames) + 1);
    for (var f=0; f<totalFrames; f++) {
      final idxL = f % lineL.length;
      final idxR = f % lineR.length;
      final delayedL = lineL[idxL];
      final delayedR = lineR[idxR];
      for (var c=0;c<channels;c++) {
        final drySample = f < frames ? filtered[c][f] : 0.0;
        final delayed = channels == 1 ? delayedL : (pingPong ? (c == 0 ? delayedR : delayedL) : (c == 0 ? delayedL : delayedR));
        final echo = bypass ? 0.0 : delayed;
        output[c][f] = ((drySample * (1-wet)) + ((drySample + echo) * wet)) * gain;
      }
      if (!bypass) {
        final inL = f < frames ? filtered[0][f] : 0.0;
        final inR = channels == 2 && f < frames ? filtered[1][f] : inL;
        lineL[idxL] = (inL + (pingPong && channels == 2 ? delayedR : delayedL) * fb).clamp(-1.0,1.0);
        lineR[idxR] = (inR + (pingPong && channels == 2 ? delayedL : delayedR) * fb).clamp(-1.0,1.0);
      }
    }
    final pcm = BytesBuilder();
    for (var f=0;f<totalFrames;f++) {
      for (var c=0;c<channels;c++) {
        final sample = (output[c][f].clamp(-1.0,0.999969) * 32768).round();
        final b = ByteData(2)..setInt16(0,sample,Endian.little);
        pcm.add(b.buffer.asUint8List());
      }
    }
    final payload = pcm.takeBytes();
    final result = BytesBuilder();
    void txt(String s)=>result.add(s.codeUnits);
    void u16(int n){final b=ByteData(2)..setUint16(0,n,Endian.little);result.add(b.buffer.asUint8List());}
    void u32(int n){final b=ByteData(4)..setUint32(0,n,Endian.little);result.add(b.buffer.asUint8List());}
    txt('RIFF');u32(36+payload.length);txt('WAVE');txt('fmt ');u32(16);u16(1);u16(channels);
    u32(sampleRate);u32(sampleRate*channels*2);u16(channels*2);u16(16);txt('data');u32(payload.length);result.add(payload);
    await outputDirectory.create(recursive:true);
    final safe = input.uri.pathSegments.last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'),'_');
    final file=File('${outputDirectory.path}/${DateTime.now().millisecondsSinceEpoch}_DDM_$safe');
    await file.writeAsBytes(result.takeBytes(),flush:true);
    return file;
  }
}