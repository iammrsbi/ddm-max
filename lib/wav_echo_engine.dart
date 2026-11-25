import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class WavEchoEngine {
  static Future<void> validate({required File input}) async {
    final bytes = await input.readAsBytes();
    if (bytes.length < 44 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('Compressed audio or unsupported WAV container.');
    }
    final data = ByteData.sublistView(bytes);
    var offset = 12;
    int? channels, bits, format, dataLength;
    while (offset + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = data.getUint32(offset + 4, Endian.little);
      final start = offset + 8;
      if (start + size > bytes.length) break;
      if (id == 'fmt ' && size >= 16) {
        format = data.getUint16(start, Endian.little);
        channels = data.getUint16(start + 2, Endian.little);
        bits = data.getUint16(start + 14, Endian.little);
      } else if (id == 'data') {
        dataLength = size;
        break;
      }
      offset = start + size + (size.isOdd ? 1 : 0);
    }
    if (format != 1 || bits != 16 || channels == null ||
        (channels != 1 && channels != 2) || dataLength == null ||
        dataLength < channels * 2 || dataLength % (channels * 2) != 0) {
      throw const FormatException('WAV ko PCM 16-bit mono/stereo mein convert karna zaroori hai.');
    }
  }

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
    int mode = 0,
    bool bypass = false,
    bool noiseReduction = true,
    bool noiseGate = true,
    double ancLevel = 0.65,
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
    final ch = channels!;
    final rate = sampleRate!;
    final startData = dataStart!;
    final lengthData = dataLength!;
    final frames = lengthData ~/ (ch * 2);
    final safeMode = mode.clamp(0, 3);
    final minDelayMs = safeMode == 0 ? 13 : (safeMode == 1 ? 50 : (safeMode == 2 ? 200 : 50));
    final maxDelayMs = safeMode == 0 ? 50 : (safeMode == 1 ? 200 : (safeMode == 2 ? 800 : 200));
    final safeDelayMs = delayMs.clamp(minDelayMs, maxDelayMs);
    final delayFrames = math.max(1, (rate * safeDelayMs / 1000).round()).toInt();
    final tailFrames = bypass ? 0 : delayFrames * (mode == 3 ? 8 : (dual ? 5 : 4));
    final totalFrames = frames + tailFrames;
    final dry = List<Float64List>.generate(ch, (_) => Float64List(totalFrames));
    for (var f = 0; f < frames; f++) {
      for (var c = 0; c < ch; c++) {
        dry[c][f] = data.getInt16(startData + (f * ch + c) * 2, Endian.little) / 32768.0;
      }
    }
    final cleaned = List<Float64List>.generate(ch, (c) {
      final out = Float64List(totalFrames);
      final strength = ancLevel.clamp(0.0, 1.0).toDouble();
      final cutoffHz = 75.0 + 135.0 * strength;
      final alpha = 1.0 / (1.0 + 2.0 * math.pi * cutoffHz / rate);
      double previousInput = 0, previousHigh = 0, gateGain = 1.0;
      for (var i = 0; i < frames; i++) {
        final x = dry[c][i];
        final high = noiseReduction ? alpha * (previousHigh + x - previousInput) : x;
        previousInput = x; previousHigh = high;
        final filtered = x * (1.0 - strength) + high * strength;
        final threshold = 0.0018 + 0.009 * strength;
        final magnitude = filtered.abs();
        final targetGate = !noiseGate ? 1.0 : (magnitude < threshold
            ? 0.06
            : (magnitude < threshold * 2.0 ? 0.06 + (magnitude - threshold) / threshold * 0.94 : 1.0));
        final smoothing = targetGate < gateGain ? 0.24 : 0.035;
        gateGain += (targetGate - gateGain) * smoothing;
        out[i] = filtered * gateGain;
      }
      return out;
    });
    final filtered = List<Float64List>.generate(ch, (c) {
      final out = Float64List(totalFrames);
      if (bypass) { for (var i=0;i<frames;i++) { out[i]=cleaned[c][i]; } return out; }
      final centers = [100.0, 350.0, 1000.0, 3500.0, 9000.0];
      final gains = List<double>.generate(5, (i) => (i < eq.length ? eq[i] : 0).clamp(-12, 12).toDouble());
      // Five broad, stable peaking bands using RBJ biquad coefficients.
      var signal = cleaned[c];
      for (var band = 0; band < 5; band++) {
        final gain = math.pow(10, gains[band] / 40).toDouble();
        // Keep every EQ band below Nyquist for low-rate WAV recordings.
        final centerHz = math.min(centers[band], rate * 0.45);
        final w = 2 * math.pi * centerHz / rate;
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
    // Mono input is promoted to stereo when a spatial mode is requested.
    final outputChannels = (ch == 1 && (pingPong || dual)) ? 2 : ch;
    final output = List<Float64List>.generate(outputChannels, (_) => Float64List(totalFrames));
    final fb = feedback.clamp(0.0, 0.92).toDouble();
    final wet = mix.clamp(0.0, 1.0).toDouble();
    final gain = level.clamp(0.0, 1.5).toDouble();
    final lineL = Float64List(delayFrames + 1);
    final lineR = Float64List((dual ? delayFrames * 3 : delayFrames) + 1);
    double echoToneL = 0, echoToneR = 0;
    for (var f=0; f<totalFrames; f++) {
      final idxL = f % lineL.length;
      final idxR = f % lineR.length;
      final delayedL = lineL[idxL];
      final delayedR = lineR[idxR];
      var echoL = delayedL;
      var echoR = delayedR;
      final toneAlpha = switch (mode) { 1 => 0.20, 2 => 0.12, 3 => 0.24, _ => 1.0 };
      if (mode >= 1 && mode <= 3) {
        echoToneL += toneAlpha * (echoL - echoToneL);
        echoToneR += toneAlpha * (echoR - echoToneR);
        echoL = echoToneL;
        echoR = echoToneR;
      }
      if (mode == 2) {
        final saturatedL = echoL * 1.25;
        final saturatedR = echoR * 1.25;
        echoL = saturatedL / (1.0 + saturatedL.abs() * 0.20);
        echoR = saturatedR / (1.0 + saturatedR.abs() * 0.20);
      } else if (mode == 3) {
        final wobble = 0.88 + 0.12 * math.sin(2 * math.pi * f / (rate * 2.8));
        echoL *= wobble;
        echoR *= wobble;
      }
      final dryL = f < frames ? filtered[0][f] : 0.0;
      final dryR = ch == 2 && f < frames ? filtered[1][f] : dryL;
      if (outputChannels == 1) {
        final echo = bypass ? 0.0 : echoL;
        output[0][f] = (((dryL * (1-wet)) + ((dryL + echo) * wet)) * gain).toDouble();
      } else {
        final wetL = bypass ? 0.0 : echoL;
        final wetR = bypass ? 0.0 : echoR;
        output[0][f] = (((dryL * (1-wet)) + ((dryL + wetL) * wet)) * gain).toDouble();
        output[1][f] = (((dryR * (1-wet)) + ((dryR + wetR) * wet)) * gain).toDouble();
      }
      if (!bypass) {
        final inL = dryL;
        // Mono ping-pong starts on the left; the feedback crosses to the right.
        final inR = ch == 2 ? dryR : (pingPong ? 0.0 : dryR);
        lineL[idxL] = (inL + (pingPong ? delayedR : delayedL) * fb).clamp(-1.0,1.0).toDouble();
        lineR[idxR] = (inR + (pingPong ? delayedL : delayedR) * fb).clamp(-1.0,1.0).toDouble();
      }
    }
    // Auto-level quiet recordings up to a safe peak, then apply a soft limiter.
    double peak = 0.0;
    for (var c=0;c<outputChannels;c++) {
      for (var f=0;f<totalFrames;f++) {
        peak = math.max(peak, output[c][f].abs());
      }
    }
    final autoGain = peak > 0.00001 ? math.min(3.0, 0.90 / peak) : 1.0;
    final pcm = BytesBuilder();
    for (var f=0;f<totalFrames;f++) {
      for (var c=0;c<outputChannels;c++) {
        final lifted = output[c][f] * autoGain;
        final limited = math.tanh(lifted * 1.15) / math.tanh(1.15);
        final sample = (limited.clamp(-1.0,0.999969) * 32768).round();
        final b = ByteData(2)..setInt16(0,sample,Endian.little);
        pcm.add(b.buffer.asUint8List());
      }
    }
    final payload = pcm.takeBytes();
    final result = BytesBuilder();
    void txt(String s)=>result.add(s.codeUnits);
    void u16(int n){final b=ByteData(2)..setUint16(0,n,Endian.little);result.add(b.buffer.asUint8List());}
    void u32(int n){final b=ByteData(4)..setUint32(0,n,Endian.little);result.add(b.buffer.asUint8List());}
    txt('RIFF');u32(36+payload.length);txt('WAVE');txt('fmt ');u32(16);u16(1);u16(outputChannels);
    u32(rate);u32(rate*outputChannels*2);u16(outputChannels*2);u16(16);txt('data');u32(payload.length);result.add(payload);
    await outputDirectory.create(recursive:true);
    final originalName = input.uri.pathSegments.isEmpty ? 'audio' : input.uri.pathSegments.last;
    final dot = originalName.lastIndexOf('.');
    final baseName = (dot > 0 ? originalName.substring(0, dot) : originalName)
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    // The renderer always writes RIFF/WAVE bytes, so the exported extension must always be .wav.
    final file=File('${outputDirectory.path}/${DateTime.now().millisecondsSinceEpoch}_DDM_$baseName.wav');
    await file.writeAsBytes(result.takeBytes(),flush:true);
    return file;
  }
}