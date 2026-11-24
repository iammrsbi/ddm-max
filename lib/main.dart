import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'wav_echo_engine.dart';

void main() => runApp(const DDMMaxApp());
const green = Color(0xFF20C878);
const gold = Color(0xFFFFC857);
const panel = Color(0xDD101B18);

class DDMMaxApp extends StatelessWidget {
  const DDMMaxApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'DDM-MAX',
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF07110E),
      colorScheme: ColorScheme.fromSeed(seedColor: green, brightness: Brightness.dark),
      sliderTheme: const SliderThemeData(activeTrackColor: green, thumbColor: gold, inactiveTrackColor: Colors.white24),
    ),
    home: const ConsoleHome(),
  );
}

class ConsoleHome extends StatefulWidget {
  const ConsoleHome({super.key});
  @override
  State<ConsoleHome> createState() => _ConsoleHomeState();
}

class _ConsoleHomeState extends State<ConsoleHome> {
  int tab = 0;
  double level = 70, feedback = 42, delayTime = 360, mix = 35;
  double bass = 0, lowMid = 0, mid = 0, highMid = 0, treble = 0;
  bool bypass = false, pingPong = false, dual = false, liveMic = false, loop = false, recording = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  File? _selectedAudio;
  File? _echoAudio;
  bool _working = false;
  bool _isPlaying = false;

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _pickAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['wav']);
      if (result == null || result.files.single.path == null) return;
      await _audioPlayer.stop();
      setState(() { _selectedAudio = File(result.files.single.path!); _echoAudio = null; _isPlaying = false; });
      _notice('WAV file select ho gayi. Ab PLAY ya SAVE ECHO dabao.');
    } catch (e) { _notice('File select nahi hui: $e'); }
  }

  Future<void> _playAudio({bool echo = false}) async {
    final file = echo ? _echoAudio : _selectedAudio;
    if (file == null) { _notice(echo ? 'Pehle SAVE ECHO banao.' : 'Pehle WAV file select karo.'); return; }
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
      await _audioPlayer.play(DeviceFileSource(file.path));
      setState(() => _isPlaying = true);
    } catch (e) { _notice('Audio play nahi hua: $e'); }
  }

  Future<void> _stopAudio() async {
    await _audioPlayer.stop();
    if (mounted) setState(() => _isPlaying = false);
  }

  Future<void> _makeEcho() async {
    if (_selectedAudio == null) { _notice('Pehle WAV file select karo.'); return; }
    setState(() => _working = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final output = await WavEchoEngine.render(
        input: _selectedAudio!, outputDirectory: Directory('${dir.path}/DDM-MAX'),
        delayMs: delayTime.round(), feedback: feedback / 100,
        mix: mix / 100, level: level / 100,
      );
      if (!mounted) return;
      setState(() { _echoAudio = output; _working = false; });
      _notice('Echo WAV save ho gayi: ${output.path}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      _notice('Echo process nahi hua: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_delayPage(), _filePage(), _eqPage(), _recordPage(), _libraryPage()];
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        Image.asset('assets/combo_bg.jpg', fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF07110E))),
        Container(color: const Color(0xE607100D)),
        SafeArea(child: Column(children: [_header(), Expanded(child: pages[tab])])),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        backgroundColor: const Color(0xFF0B1713),
        indicatorColor: green.withOpacity(.22),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.graphic_eq), label: 'Delay'),
          NavigationDestination(icon: Icon(Icons.audio_file), label: 'File Echo'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'EQ'),
          NavigationDestination(icon: Icon(Icons.mic), label: 'Record'),
          NavigationDestination(icon: Icon(Icons.library_music), label: 'Naat'),
        ],
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
    child: Row(children: [
      Container(width: 46, height: 46, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: gold, width: 1.5), color: Colors.black54), child: const Icon(Icons.graphic_eq, color: gold, size: 27)),
      const SizedBox(width: 12),
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('DDM-MAX', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: 2)),
        Text('DIGITAL DELAY • NAAT AUDIO SYSTEM', style: TextStyle(fontSize: 9, color: gold, letterSpacing: 1.1)),
      ])),
      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white24)), child: const Row(children: [Icon(Icons.circle, color: green, size: 8), SizedBox(width: 6), Text('READY', style: TextStyle(fontSize: 10, letterSpacing: 1))])),
    ]),
  );

  Widget _scroll(List<Widget> children) => SingleChildScrollView(padding: const EdgeInsets.fromLTRB(14, 2, 14, 20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children));
  Widget _title(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 5),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 1)),
      Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.white60)),
    ]),
  );
  Widget _panel(Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 13), padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(17), border: Border.all(color: Colors.white.withOpacity(.13)), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 5))]),
    child: child,
  );

  Widget _delayPage() => _scroll([
    Row(children: [const Expanded(child: Text('DIGITAL DELAY', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 1))), _pill('DD-8 STYLE')]),
    const Text('STUDIO EFFECT PROCESSOR', style: TextStyle(fontSize: 10, color: Colors.white60)),
    const SizedBox(height: 10),
    _panel(Column(children: [
      Row(children: [Expanded(child: _mode('SINGLE DELAY', !dual, () => setState(() => dual = false))), const SizedBox(width: 8), Expanded(child: _mode('DUAL DELAY', dual, () => setState(() => dual = true)))]),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: _switch('PING-PONG', pingPong, (v) => setState(() => pingPong = v))), const SizedBox(width: 8), Expanded(child: _switch('BYPASS', bypass, (v) => setState(() => bypass = v)))]),
    ])),
    _panel(Column(children: [
      _slider('LEVEL', level, 0, 100, level.round().toString() + '%', (v) => setState(() => level = v)),
      _slider('FEEDBACK', feedback, 0, 95, feedback.round().toString() + '%', (v) => setState(() => feedback = v)),
      _slider('TIME', delayTime, 40, 1200, delayTime.round().toString() + ' ms', (v) => setState(() => delayTime = v)),
      _slider('EFFECT MIX', mix, 0, 100, mix.round().toString() + '%', (v) => setState(() => mix = v)),
    ])),
    _title('INPUT SOURCE', 'CHOOSE YOUR AUDIO INPUT'),
    _panel(Row(children: [
      Expanded(child: _action(Icons.mic, 'LIVE MIC', liveMic, () => setState(() => liveMic = !liveMic))),
      const SizedBox(width: 10),
      Expanded(child: _action(Icons.audio_file, 'FILE INPUT', false, () => setState(() => tab = 1))),
    ])),
    _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('SIGNAL MONITOR', style: TextStyle(color: gold, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Row(children: List.generate(24, (i) => Expanded(child: Container(height: 8 + ((i * 17) % 23).toDouble(), margin: const EdgeInsets.symmetric(horizontal: 1), decoration: BoxDecoration(color: i < 17 ? green : gold, borderRadius: BorderRadius.circular(3)))))),
      const SizedBox(height: 7),
      const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('INPUT', style: TextStyle(fontSize: 9, color: Colors.white54)), Text('OUTPUT', style: TextStyle(fontSize: 9, color: Colors.white54))]),
    ])),
    const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Interface stage: audio DSP and live microphone routing are not connected yet.', style: TextStyle(color: Colors.white54, fontSize: 10))),
  ]);

  Widget _filePage() => _scroll([
    _title('FILE ECHO', 'REAL WAV DELAY PROCESSOR'),
    _panel(Column(children: [
      const Icon(Icons.audio_file, size: 54, color: gold), const SizedBox(height: 10),
      Text(_selectedAudio == null ? 'NO AUDIO SELECTED' : _selectedAudio!.uri.pathSegments.last, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: .5)),
      const SizedBox(height: 5), const Text('Select an uncompressed PCM 16-bit WAV file', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 11)),
      const SizedBox(height: 15),
      _action(Icons.folder_open, 'CHOOSE WAV FILE', _selectedAudio != null, _working ? () {} : _pickAudio),
    ])),
    _panel(Column(children: [
      _slider('DELAY TIME', delayTime, 40, 1200, delayTime.round().toString() + ' ms', (v) => setState(() => delayTime = v)),
      _slider('FEEDBACK', feedback, 0, 92, feedback.round().toString() + '%', (v) => setState(() => feedback = v)),
      _slider('EFFECT MIX', mix, 0, 100, mix.round().toString() + '%', (v) => setState(() => mix = v)),
      _slider('OUTPUT LEVEL', level, 0, 100, level.round().toString() + '%', (v) => setState(() => level = v)),
      _switch('REPEAT / LOOP PLAYBACK', loop, (v) => setState(() => loop = v)),
      const Divider(color: Colors.white12),
      Row(children: [
        Expanded(child: _outline(Icons.play_arrow, 'PLAY ORIGINAL', () => _playAudio())),
        const SizedBox(width: 7), Expanded(child: _outline(Icons.stop, 'STOP', _stopAudio)),
      ]),
      const SizedBox(height: 9),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        onPressed: _working ? null : _makeEcho,
        icon: _working ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
        label: Text(_working ? 'PROCESSING WAV...' : 'PROCESS & SAVE ECHO'),
        style: FilledButton.styleFrom(backgroundColor: green, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 13)),
      )),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: _echoAudio == null ? null : () => _playAudio(echo: true),
        icon: const Icon(Icons.play_circle), label: const Text('PLAY PROCESSED ECHO'),
      )),
      if (_echoAudio != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Saved: ${_echoAudio!.uri.pathSegments.last}', textAlign: TextAlign.center, style: const TextStyle(color: green, fontSize: 10))),
    ])),
    _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('BEFORE / AFTER', style: TextStyle(color: gold, fontWeight: FontWeight.bold, letterSpacing: 1)),
      const SizedBox(height: 12),
      Row(children: [Expanded(child: _compare('BEFORE', _selectedAudio == null ? 'Original audio' : 'Original WAV selected')), const SizedBox(width: 8), Expanded(child: _compare('AFTER', _echoAudio == null ? 'Process echo first' : 'Echo file ready'))]),
    ])),
    const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Note: This first working processor supports PCM 16-bit mono/stereo WAV. MP3 conversion and live microphone DSP are separate next steps.', style: TextStyle(color: Colors.white54, fontSize: 10))),
  ]);

  Widget _eqPage() => _scroll([
    _title('5-BAND EQUALIZER', 'SHAPE YOUR NAAT VOICE'),
    _panel(Column(children: [
      Row(children: [
        Expanded(child: _mode('FLAT', bass == 0 && treble == 0, () => setState(() { bass = 0; lowMid = 0; mid = 0; highMid = 0; treble = 0; }))),
        const SizedBox(width: 7),
        Expanded(child: _mode('NAAT VOICE', false, () => setState(() { bass = 2; lowMid = 1; mid = 3; highMid = 4; treble = 2; }))),
      ]),
      const SizedBox(height: 8),
      _slider('BASS', bass, -12, 12, bass.toStringAsFixed(0) + ' dB', (v) => setState(() => bass = v)),
      _slider('LOW MID', lowMid, -12, 12, lowMid.toStringAsFixed(0) + ' dB', (v) => setState(() => lowMid = v)),
      _slider('MID', mid, -12, 12, mid.toStringAsFixed(0) + ' dB', (v) => setState(() => mid = v)),
      _slider('HIGH MID', highMid, -12, 12, highMid.toStringAsFixed(0) + ' dB', (v) => setState(() => highMid = v)),
      _slider('TREBLE', treble, -12, 12, treble.toStringAsFixed(0) + ' dB', (v) => setState(() => treble = v)),
    ])),
    _panel(Row(children: [
      Expanded(child: _mode('BASS BOOST', false, () => setState(() => bass = 8))),
      const SizedBox(width: 8),
      Expanded(child: _mode('CLEAR VOCAL', false, () => setState(() { mid = 3; highMid = 6; treble = 3; }))),
    ])),
    const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Equalizer controls are interface-only until connected to the native audio engine.', style: TextStyle(color: Colors.white54, fontSize: 10))),
  ]);

  Widget _recordPage() => _scroll([
    _title('RECORDING STUDIO', 'CAPTURE YOUR NAAT PERFORMANCE'),
    _panel(Column(children: [
      Container(width: 112, height: 112, decoration: BoxDecoration(shape: BoxShape.circle, color: recording ? Colors.red.withOpacity(.2) : Colors.white10, border: Border.all(color: recording ? Colors.redAccent : gold, width: 2)), child: Icon(recording ? Icons.stop : Icons.mic, size: 48, color: recording ? Colors.redAccent : gold)),
      const SizedBox(height: 14),
      Text(recording ? 'RECORDING' : 'READY TO RECORD', style: TextStyle(fontWeight: FontWeight.bold, color: recording ? Colors.redAccent : Colors.white, letterSpacing: 1.5)),
      const SizedBox(height: 18),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: recording ? Colors.red.shade700 : green, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: () => setState(() => recording = !recording),
        icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record),
        label: Text(recording ? 'STOP' : 'START RECORDING', style: const TextStyle(fontWeight: FontWeight.bold)),
      )),
    ])),
    _panel(const Column(children: [Text('YOUR RECORDINGS', style: TextStyle(color: gold, fontWeight: FontWeight.bold, letterSpacing: 1)), SizedBox(height: 12), Text('No recordings yet', style: TextStyle(color: Colors.white54, fontSize: 12))])),
    const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Recording controls are visual placeholders until microphone permission and file saving are connected.', style: TextStyle(color: Colors.white54, fontSize: 10))),
  ]);

  Widget _libraryPage() => _scroll([
    _title('NAAT COLLECTION', 'YOUR AUDIO LIBRARY'),
    _panel(const Column(children: [
      Icon(Icons.library_music, size: 48, color: gold), SizedBox(height: 10),
      Text('NAAT LIBRARY', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
      SizedBox(height: 6),
      Text('Your existing Naat collection will be connected here.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 11)),
    ])),
  ]);

  Widget _slider(String label, double value, double min, double max, String readout, ValueChanged<double> change) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Column(children: [
      Row(children: [Expanded(child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1))), Text(readout, style: const TextStyle(color: gold, fontSize: 12, fontWeight: FontWeight.bold))]),
      Slider(value: value.clamp(min, max), min: min, max: max, onChanged: change),
    ]),
  );

  Widget _switch(String label, bool value, ValueChanged<bool> change) => Row(children: [
    Expanded(child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: .7))),
    Switch(value: value, activeColor: green, onChanged: change),
  ]);

  Widget _mode(String label, bool selected, VoidCallback tap) => OutlinedButton(
    style: OutlinedButton.styleFrom(foregroundColor: selected ? Colors.black : Colors.white, backgroundColor: selected ? green : Colors.transparent, side: BorderSide(color: selected ? green : Colors.white30), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    onPressed: tap, child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
  );

  Widget _action(IconData icon, String label, bool selected, VoidCallback tap) => FilledButton.icon(
    style: FilledButton.styleFrom(backgroundColor: selected ? gold : green, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 13)),
    onPressed: tap, icon: Icon(icon, size: 18), label: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
  );

  Widget _outline(IconData icon, String label, VoidCallback tap) => OutlinedButton(
    onPressed: tap, style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white30), padding: const EdgeInsets.symmetric(vertical: 11)),
    child: Column(children: [Icon(icon, size: 19), const SizedBox(height: 3), Text(label, style: const TextStyle(fontSize: 9))]),
  );

  Widget _pill(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(color: green.withOpacity(.16), borderRadius: BorderRadius.circular(20), border: Border.all(color: green.withOpacity(.5))),
    child: Text(label, style: const TextStyle(color: green, fontSize: 9, fontWeight: FontWeight.bold)),
  );

  void _notice(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));

  static Widget _compare(String title, String subtitle) => Container(
    padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
    child: Column(children: [Text(title, style: const TextStyle(color: gold, fontSize: 11, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 9))]),
  );
}
