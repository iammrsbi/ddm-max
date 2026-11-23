import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const DDMApp());

class DDMApp extends StatelessWidget {
  const DDMApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const DDMHome(),
    );
  }
}

class DDMHome extends StatefulWidget {
  const DDMHome({super.key});
  @override
  State<DDMHome> createState() => _DDMHomeState();
}

class _DDMHomeState extends State<DDMHome> {
  static const MethodChannel _channel = MethodChannel('com.idrish.dd8max/audio');
  int tab = 0;
  double eLevel = 5.0, feedback = 4.0, time = 6.0, modulate = 0.0;
  bool isSingle = true, isBypass = false, isRecording = false, isLoop = false;
  bool isFilePlaying = false, isFileRepeat = false, isAfterEffect = true;
  List<double> eq = [2, 0, -2, 3, 4];
  final List<String> eqLabels = ['80 Hz', '250 Hz', '1K', '4K', '10K'];
  String currentPreset = 'NAAT VOICE';
  bool isDark = true, keepScreenOn = true;
  String selectedLang = 'Roman Urdu';
  double micBoost = 0.0, outputBoost = 0.0;

  final List<Map<String, dynamic>> presets = [
    {'name': 'Sartab Adam hai tane sultan e zamana phool', 'e': 5.0, 'f': 4.0, 't': 6.0},
    {'name': 'Chamak Tujhse Paate Hai Sab Paane wale', 'e': 6.0, 'f': 5.0, 't': 7.0},
    {'name': 'Wallah Wallah', 'e': 7.0, 'f': 4.5, 't': 8.0},
    {'name': 'Wo sue lalazar phirte hai', 'e': 5.5, 'f': 3.5, 't': 6.5},
    {'name': 'Aadam Raza Preset - 720ms Ping Pong', 'e': 3.5, 'f': 5.3, 't': 7.2},
    {'name': 'Haale Dil Kis Ko Sunaye', 'e': 3.5, 'f': 5.3, 't': 7.2},
  ];

  @override
  void initState() {
    super.initState();
    _sendToNative();
  }

  Future<void> _sendToNative() async {
    try {
      await _channel.invokeMethod('setParams', {
        'eLevel': eLevel, 'feedback': feedback, 'time': time, 'modulate': modulate,
        'isSingle': isSingle, 'isBypass': isBypass, 'eq': eq,
        'micBoost': micBoost, 'outputBoost': outputBoost,
      });
    } catch (e) { debugPrint('Native error: $e'); }
  }

  Future<void> _native(String method, [Map<String, dynamic>? args]) async {
    try { await _channel.invokeMethod(method, args ?? {}); } catch (e) { debugPrint('Native $method error: $e'); }
  }

  void loadPreset(Map p) {
    setState(() {
      eLevel = (p['e'] as double);
      feedback = (p['f'] as double);
      time = (p['t'] as double);
      currentPreset = p['name'] as String;
      tab = 0;
    });
    _sendToNative();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Preset Load: ${p['name']}'), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A1A3A) : Colors.grey.shade100,
      body: Column(
        children: [
          Container(
            height: 200, width: double.infinity,
            decoration: const BoxDecoration(color: Color(0xFF112244)),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset('assets/combo_bg.jpg', fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(color: const Color(0xFF112244))),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                    ),
                  ),
                ),
                const Positioned(
                  bottom: 8, left: 0, right: 0,
                  child: Column(
                    children: [
                      Text('शायर-ए-रसूल', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFFFFCC00))),
                      Text('DIGITAL DELAY  DD-8  MAX', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
                      Text('Developer: IDRISH', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (tab == 0)
            Padding(
              padding: const EdgeInsets.all(8),
              child: GestureDetector(
                onTap: () => loadPreset(presets[4]),
                child: Container(
                  padding: const EdgeInsets.all(12), width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFF8800)]),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Text(
                    currentPreset.contains('Aadam') ? '✅ AADAM RAZA ON - 720ms' : '⭐ AADAM RAZA PRESET - REEL WALI SETTING - TAP KARO',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black),
                  ),
                ),
              ),
            ),
          Expanded(child: [_liveMicPage(), _fileEchoPage(), _presetsPage(), _equalizerPage(), _settingsPage()][tab]),
          Container(
            color: const Color(0xFF111111),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                _nav(0, '🎤', 'LIVE MIC'),
                _nav(1, '🎵', 'FILE ECHO'),
                _nav(2, '⭐', 'PRESETS'),
                _nav(3, '🎚️', 'EQUALIZER'),
                _nav(4, '⚙️', 'SETTINGS'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nav(int i, String emoji, String label) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => tab = i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: tab == i ? const Color(0xFF1A4AA0) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _liveMicPage() {
    return SingleChildScrollView(
      child: Container(
        margin: const EdgeInsets.all(8), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF00C6FF))),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('IN  |||||||', style: TextStyle(color: Colors.green)),
                Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: isBypass ? Colors.grey : Colors.red, shape: BoxShape.circle)), const Text(' CHECK', style: TextStyle(color: Colors.white))]),
                const Text('OUT  |||||||', style: TextStyle(color: Colors.green)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _knob('E.LEVEL', eLevel, 0, 10, (v) { setState(() => eLevel = v); _sendToNative(); }),
                _knob('FEEDBACK', feedback, 0, 10, (v) { setState(() => feedback = v); _sendToNative(); }),
                _knob('TIME', time, 0, 10, (v) { setState(() => time = v); _sendToNative(); }),
                _knob('MODULATE', modulate, 0, 10, (v) { setState(() => modulate = v); _sendToNative(); }),
              ],
            ),
            const SizedBox(height: 6),
            Text('TAP: SET TEMPO  |  HOLD: ECHO LOOP', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('RECORD (LIVE MIC)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                      const SizedBox(height: 4),
                      ElevatedButton(
                        onPressed: () { setState(() => isRecording = !isRecording); _native(isRecording ? 'startRecording' : 'stopRecording'); },
                        style: ElevatedButton.styleFrom(backgroundColor: isRecording ? Colors.red : Colors.blue),
                        child: Text(isRecording ? '● STOP' : '● REC'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      const Text('TAP TEMPO (120 BPM)', style: TextStyle(color: Colors.white, fontSize: 10)),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(onPressed: () => _native('tapTempo'), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)), child: const Text('TAP')),
                          const SizedBox(width: 4),
                          ElevatedButton(
                            onPressed: () { setState(() => isLoop = !isLoop); _native('setLoop', {'on': isLoop}); },
                            style: ElevatedButton.styleFrom(backgroundColor: isLoop ? Colors.green : Colors.grey, padding: const EdgeInsets.symmetric(horizontal: 10)),
                            child: const Text('LOOP'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      const Text('PING-PONG (ON)', style: TextStyle(color: Colors.white, fontSize: 10)),
                      const SizedBox(height: 4),
                      ElevatedButton(onPressed: () => _native('holdEcho'), child: const Text('HOLD')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: () { setState(() => isSingle = true); _sendToNative(); }, style: ElevatedButton.styleFrom(backgroundColor: isSingle ? Colors.blue : Colors.grey.shade800), child: const Text('Single'))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton(onPressed: () { setState(() => isSingle = false); _sendToNative(); }, style: ElevatedButton.styleFrom(backgroundColor: !isSingle ? Colors.blue : Colors.grey.shade800), child: const Text('Dual'))),
              ],
            ),
            const SizedBox(height: 8),
            Text('Digital Delay MAX - ${isSingle ? "Single" : "Dual"}  |  ${(time * 100).toInt()} ms', style: const TextStyle(color: Color(0xFF00C6FF), fontWeight: FontWeight.bold)),
            GestureDetector(
              onTap: () { setState(() => isBypass = !isBypass); _sendToNative(); },
              child: Container(
                margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(14), width: double.infinity,
                decoration: BoxDecoration(color: isBypass ? Colors.red : Colors.grey.shade900, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white)),
                child: Text(isBypass ? '● BYPASS ON (EFFECT OFF)' : '● EFFECT ACTIVE (TAP TO BYPASS)', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: () => _native('startLive'), child: const Text('▶ LIVE MIC ON'))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton(onPressed: () => _native('stopLive'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('⏹ STOP'))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _knob(String label, double val, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      children: [
        Container(
          width: 58, height: 58,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade900, border: Border.all(color: const Color(0xFF00C6FF), width: 2.5)),
          child: Center(child: Text(val.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
        ),
        SizedBox(width: 72, child: Slider(value: val, min: min, max: max, activeColor: const Color(0xFF00C6FF), onChanged: onChanged)),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _fileEchoPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('File Echo', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF00C6FF))),
          const Text('Pick any Naat, audio or video file, add echo to it, listen and save.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          _fileBtn('📂 Choose File (Audio / Video)', Colors.grey.shade300, Colors.black, () => _native('pickFile')),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _fileBtn(isFilePlaying ? '⏹ Stop' : '▶ Play', Colors.blue, Colors.white, () { setState(() => isFilePlaying = !isFilePlaying); _native(isFilePlaying ? 'playFile' : 'stopFile'); })),
              const SizedBox(width: 8),
              Expanded(child: _fileBtn('💾 Save Echo File', Colors.green, Colors.white, () => _native('saveEchoFile'))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _fileBtn(isFileRepeat ? '🔁 Repeat: ON' : '🔁 Repeat: OFF', isFileRepeat ? Colors.orange : Colors.grey.shade700, Colors.white, () { setState(() => isFileRepeat = !isFileRepeat); _native('setLoop', {'on': isFileRepeat}); })),
              const SizedBox(width: 8),
              Expanded(child: _fileBtn(isAfterEffect ? '✨ After (With Echo)' : '🎙️ Before (Original)', Colors.purple, Colors.white, () { setState(() => isAfterEffect = !isAfterEffect); _native('toggleBeforeAfter'); })),
            ],
          ),
          const SizedBox(height: 12),
          _fileBtn('📲 Send on WhatsApp', const Color(0xFF25D366), Colors.white, () => _native('shareWhatsApp')),
        ],
      ),
    );
  }

  Widget _fileBtn(String text, Color bg, Color fg, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: fg, padding: const EdgeInsets.symmetric(vertical: 14)),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _presetsPage() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: presets.length,
      itemBuilder: (context, index) {
        final p = presets[index];
        final isSelected = currentPreset == p['name'];
        return Card(
          color: isSelected ? const Color(0xFF1A4AA0) : Colors.black87,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.star, color: Color(0xFFFFCC00)),
            title: Text(p['name'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text('E.Level: ${p['e']} | Feedback: ${p['f']} | Time: ${p['t']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            trailing: ElevatedButton(onPressed: () => loadPreset(p), child: const Text('LOAD')),
          ),
        );
      },
    );
  }

  Widget _equalizerPage() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('5-Band Equalizer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF00C6FF))),
              ElevatedButton(
                onPressed: () { setState(() => eq = [2, 0, -2, 3, 4]); _sendToNative(); },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                child: const Text('NAAT VOICE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(5, (i) {
                return Column(
                  children: [
                    Text('${eq[i] > 0 ? "+" : ""}${eq[i].toInt()} dB', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Slider(value: eq[i], min: -12, max: 12, activeColor: const Color(0xFF00C6FF), onChanged: (v) { setState(() => eq[i] = v); _sendToNative(); }),
                      ),
                    ),
                    Text(eqLabels[i], style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                );
              }),
            ),
          ),
          Row(
            children: [
              Expanded(child: ElevatedButton(onPressed: () { setState(() => eq = [0, 0, 0, 0, 0]); _sendToNative(); }, child: const Text('FLAT'))),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton(onPressed: () { setState(() => eq = [6, 4, 0, -1, -2]); _sendToNative(); }, child: const Text('BASS BOOST'))),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton(onPressed: () { setState(() => eq = [-2, -1, 2, 4, 5]); _sendToNative(); }, child: const Text('CLEAR VOCAL'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settingsPage() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ListTile(
          title: const Text('Language'),
          trailing: DropdownButton<String>(
            value: selectedLang,
            items: ['English', 'Roman Urdu', 'Hindi', 'Urdu', 'Bangla'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) { if (v != null) setState(() => selectedLang = v); },
          ),
        ),
        SwitchListTile(title: const Text('Dark Theme'), value: isDark, onChanged: (v) => setState(() => isDark = v)),
        SwitchListTile(title: const Text('Keep Screen ON'), value: keepScreenOn, onChanged: (v) => setState(() => keepScreenOn = v)),
        ListTile(
          title: Text('Mic Boost: +${micBoost.toInt()} dB'),
          subtitle: Slider(value: micBoost, min: 0, max: 20, onChanged: (v) { setState(() => micBoost = v); _sendToNative(); }),
        ),
        ListTile(
          title: Text('Output Boost: +${outputBoost.toInt()} dB'),
          subtitle: Slider(value: outputBoost, min: 0, max: 20, onChanged: (v) { setState(() => outputBoost = v); _sendToNative(); }),
        ),
        const ListTile(title: Text('Pedal Theme'), trailing: Chip(label: Text('CLASSIC DD-8 MAX'))),
        ListTile(
          title: const Text('Reset All'),
          trailing: ElevatedButton(
            onPressed: () { setState(() { eLevel = 5.0; feedback = 4.0; time = 6.0; eq = [2, 0, -2, 3, 4]; }); _sendToNative(); },
            child: const Text('RESET'),
          ),
        ),
      ],
    );
  }
}
