import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'wav_echo_engine.dart';

void main() => runApp(const DDMMaxApp());
const green = Color(0xFF168DFF), gold = Color(0xFF45CAFF), panel = Color(0xE6071426);

class DDMMaxApp extends StatelessWidget {
  const DDMMaxApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner:false, title:'DDM-MAX',
    theme:ThemeData(brightness:Brightness.dark,scaffoldBackgroundColor:const Color(0xFF030914),
      colorScheme:ColorScheme.fromSeed(seedColor:green,brightness:Brightness.dark),
      sliderTheme:const SliderThemeData(activeTrackColor:green,thumbColor:gold,inactiveTrackColor:Colors.white24)),
    home:const ConsoleHome());
}

class ConsoleHome extends StatefulWidget {
  const ConsoleHome({super.key});
  @override State<ConsoleHome> createState()=>_ConsoleHomeState();
}
class _ConsoleHomeState extends State<ConsoleHome> {
  int tab=0;
  int delayMode=1;
  static const List<String> delayModeNames=['S','M','L','SHORT LOOP'];
  Duration fileDuration=Duration.zero, filePosition=Duration.zero;
  final List<DateTime> _tapTimes=[];
  int tapBpm=120;
  bool playbackPaused=false;
  double level=50,feedback=30,delayTime=200,mix=50;
  final List<double> eq=[0,0,0,0,0];
  String eqPreset='FLAT';
  bool bypass=false,pingPong=false,dual=false,loop=false,recording=false,recordingHeld=false,working=false,liveMonitoring=false;
  bool noiseReduction=true,noiseGate=true;
  static const MethodChannel liveChannel=MethodChannel('ddm.max/live_audio');
  final AudioPlayer player=AudioPlayer();
  final AudioRecorder recorder=AudioRecorder();
  File? selected,processed,recorded,currentPlayback;
  double playbackVolume=1.0,ancLevel=65;
  String? recordingPath;

  @override void initState(){super.initState(); player.onDurationChanged.listen((d){if(mounted)setState(()=>fileDuration=d);}); player.onPositionChanged.listen((p){if(mounted)setState(()=>filePosition=p);}); player.onPlayerStateChanged.listen((st){if(mounted)setState(()=>playbackPaused=st==PlayerState.paused);}); player.onPlayerComplete.listen((_){if(mounted)setState(()=>filePosition=fileDuration);});}
  @override void dispose(){liveChannel.invokeMethod('stop');player.dispose();recorder.dispose();super.dispose();}

  void note(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  Future<File> _copyPickedAudio(PlatformFile picked) async {
    final docs = await getApplicationDocumentsDirectory();
    final folder = Directory('${docs.path}/DDM-MAX/Imported');
    await folder.create(recursive: true);
    final safeName = picked.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final destination = File('${folder.path}/${DateTime.now().microsecondsSinceEpoch}_$safeName');

    // Copy into app-private storage immediately so temporary picker paths cannot expire.
    if (picked.path != null) {
      final source = File(picked.path!);
      if (await source.exists()) {
        try { await source.copy(destination.path); } catch (_) {
          if (await destination.exists()) await destination.delete();
        }
      }
    }
    if (!await destination.exists() && picked.readStream != null) {
      final sink = destination.openWrite();
      try {
        await sink.addStream(picked.readStream!);
        await sink.flush();
      } finally {
        await sink.close();
      }
    }
    if (!await destination.exists() && picked.bytes != null) {
      await destination.writeAsBytes(picked.bytes!, flush: true);
    }
    if (!await destination.exists() || await destination.length() == 0) {
      throw const FileSystemException('Selected audio file could not be copied into app storage.');
    }
    return destination;
  }

  Future<void> chooseAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio, allowMultiple: false, withReadStream: true, withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = await _copyPickedAudio(result.files.single);

      await player.stop();
      setState(() {
        selected = file; processed = null; currentPlayback = null;
        fileDuration = Duration.zero; filePosition = Duration.zero; playbackPaused = false;
      });
      try {
        await player.setSource(DeviceFileSource(file.path));
        final duration = await player.getDuration();
        if (mounted && duration != null) setState(() => fileDuration = duration);
      } catch (_) {
        note('File import ho gayi. Preview codec support nahi mila; APPLY EFFECT try karo.');
      }
      note('File upload ho gayi — original preview ab play ho raha hai.');
      await play(file);
    } catch (e) {
      note('File upload error: $e');
    }
  }
  Future<void> play(File? f) async {
    if (f == null) { note('Pehle audio file select karo.'); return; }
    if (!await f.exists() || await f.length() == 0) { note('Audio file mil nahi rahi. Dobara upload karo.'); return; }
    try {
      await player.stop();
      currentPlayback = f;
      await player.setVolume(playbackVolume);
      await player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
      await player.play(DeviceFileSource(f.path));
    } catch (e) { note('Play error: $e'); }
  }
  Future<void> togglePause() async {
    try {
      if (player.state == PlayerState.playing) {
        await player.pause();
      } else if (player.state == PlayerState.paused) {
        await player.resume();
      } else if (currentPlayback != null) {
        await play(currentPlayback);
      } else {
        note('Pehle PLAY ORIGINAL dabao.');
      }
    } catch (e) { note('Playback control error: $e'); }
  }
  String _time(Duration d){final m=d.inMinutes.remainder(60).toString().padLeft(2,'0');final sec=d.inSeconds.remainder(60).toString().padLeft(2,'0');final h=d.inHours;return h>0?'$h:$m:$sec':'$m:$sec';}
  Future<void> auditionEffect() async { await process(selected); }

  void tapTempo() {
    final now=DateTime.now();
    _tapTimes.add(now);
    if(_tapTimes.length>5) _tapTimes.removeAt(0);
    if(_tapTimes.length<2) { note('Tap again to set tempo.'); return; }
    final gaps=<int>[];
    for(var i=1;i<_tapTimes.length;i++) {
      final gap=_tapTimes[i].difference(_tapTimes[i-1]).inMilliseconds;
      if(gap>0 && gap<2000) gaps.add(gap);
    }
    if(gaps.isEmpty) { _tapTimes..clear()..add(now); return; }
    final average=gaps.reduce((x,y)=>x+y)/gaps.length;
    final bpm=(60000/average).round().clamp(30,300);
    _changeLive(() { tapBpm=bpm; delayTime=(60000/bpm).clamp(12.5,800).toDouble(); processed=null; });
  }

  Future<void> stop() async { await player.stop(); if(mounted)setState(()=>filePosition=Duration.zero); }
  Future<File> _decodeUploadedAudio(File source) async {
    if (!await source.exists() || await source.length() == 0) {
      throw const FormatException('Uploaded audio file missing ya empty hai.');
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/DDM-MAX/Converted');
    await dir.create(recursive: true);
    final output = File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}_DDM_CONVERTED.wav');
    try {
      await liveChannel.invokeMethod<String>('decodeToWav', {
        'inputPath': source.path, 'outputPath': output.path,
      });
    } on PlatformException catch (error) {
      throw FormatException(error.message ?? 'Android audio decoder failed (${error.code}).');
    }
    if (!await output.exists() || await output.length() < 44) {
      throw const FormatException('Audio PCM WAV mein convert nahi ho payi. DRM ya unsupported codec ho sakta hai.');
    }
    return output;
  }

  Future<void> process(File? source) async {
    if (source == null) { note('Pehle PICK AUDIO FILE se file upload karo.'); return; }
    if (working) return;
    if (!await source.exists() || await source.length() == 0) {
      note('Uploaded file available nahi hai. Dobara upload karo.');
      return;
    }
    setState(() { working = true; processed = null; });
    try {
      final docs = await getApplicationDocumentsDirectory();
      final outputDir = Directory('${docs.path}/DDM-MAX/Processed');
      await outputDir.create(recursive: true);
      File pcmWav = source;
      try {
        await WavEchoEngine.validate(input: source);
      } on FormatException {
        note('Audio decode/convert ho rahi hai...');
        pcmWav = await _decodeUploadedAudio(source);
      }
      final output = await WavEchoEngine.render(
        input: pcmWav, outputDirectory: outputDir,
        delayMs: delayTime.round(), feedback: feedback / 100,
        mix: mix / 100, level: level / 100, eq: eq,
        pingPong: pingPong, dual: dual, bypass: bypass,
        noiseReduction: noiseReduction, noiseGate: noiseGate, ancLevel: ancLevel / 100,
        mode: delayMode,
      );
      if (!mounted) return;
      setState(() => processed = output);
      await play(output);
      note('Effect apply ho gaya — processed WAV ab play ho rahi hai.');
    } catch (e) {
      if (mounted) note('Effect apply nahi hua: $e');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }
  Future<void> toggleLiveMonitor() async {
    try {
      if(liveMonitoring) {
        await liveChannel.invokeMethod('stop');
        if(mounted)setState(()=>liveMonitoring=false);
        note('Live mic effect band ho gaya.');
        return;
      }
      final permission=await Permission.microphone.request();
      if(!permission.isGranted){note('Microphone permission allow karo.');return;}
      final caps=await liveChannel.invokeMapMethod<String,dynamic>('start', {'delayMs':delayTime.round(),'feedback':feedback/100,'mix':mix/100,'level':level/100,'noiseReduction':noiseReduction,'noiseGate':noiseGate,'ancLevel':ancLevel/100,'dual':dual,'pingPong':pingPong,'bypass':bypass,'eq':eq,'mode':delayMode});
      if(mounted)setState(()=>liveMonitoring=true);
      final ns=caps?['noiseSuppressor']==true;
      final aec=caps?['echoCanceler']==true;
      note('Live mic chalu. Device Noise Suppression: ${ns?'ON':'not available'} • Echo cancellation: ${aec?'ON':'not available'}. Headphones use karo.');
    } catch(e) { note('Live mic start nahi hua: $e'); }
  }
  Future<void> startRecording() async {
    try{
      if(!await recorder.hasPermission()){note('Microphone permission allow karo.');return;}
      final d=await getApplicationDocumentsDirectory();
      recordingPath='${d.path}/DDM-MAX/record_${DateTime.now().millisecondsSinceEpoch}.wav';
      await Directory('${d.path}/DDM-MAX').create(recursive:true);
      await recorder.start(const RecordConfig(encoder:AudioEncoder.wav,sampleRate:44100,numChannels:1),path:recordingPath!);
      setState(()=>recording=true);note('Mic recording start ho gayi.');
    }catch(e){note('Recording start nahi hui: $e');}
  }
  Future<void> toggleRecordingHold() async {
    try {
      if(!recording){note('Pehle RECORD dabao.');return;}
      if(recordingHeld){await recorder.resume();setState(()=>recordingHeld=false);note('Recording resume ho gayi.');}
      else {await recorder.pause();setState(()=>recordingHeld=true);note('Recording HOLD par hai.');}
    }catch(e){note('Hold control error: $e');}
  }
  Future<void> stopRecording() async {
    try{
      final p=await recorder.stop();
      if(p!=null){setState(()=>recorded=File(p));note('Recording save ho gayi. Ab Play ya Process Echo dabao.');}
    }catch(e){note('Recording stop error: $e');}
    if(mounted)setState(()=>recording=false);
  }
  Future<void> shareFile(File? f) async {
    if(f==null){note('Pehle file banao.');return;}
    await Share.shareXFiles([XFile(f.path)],text:'DDM-MAX Audio');
  }
  Map<String,dynamic> _liveConfig()=>({
    'delayMs':delayTime.round(),'feedback':feedback/100,'mix':mix/100,'level':level/100,
    'noiseReduction':noiseReduction,'noiseGate':noiseGate,'ancLevel':ancLevel/100,
    'dual':dual,'pingPong':pingPong,'bypass':bypass,'eq':eq,'mode':delayMode,
  });
  Future<void> _updateLiveEngine() async {
    if(!liveMonitoring)return;
    try{await liveChannel.invokeMethod('update',_liveConfig());}
    catch(e){note('Live control update error: $e');}
  }
  void _changeLive(VoidCallback change){setState(change);_updateLiveEngine();}
  @override Widget build(BuildContext context){
    final pages=[delayPage(),filePage()];
    return Scaffold(
      body:Stack(fit:StackFit.expand,children:[
        Image.asset('assets/combo_bg.jpg',fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(color:const Color(0xFF030914))),
        Container(color:const Color(0x99030712)),
        SafeArea(child:Column(children:[header(),Expanded(child:pages[tab])])),
      ]),
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),
        backgroundColor:const Color(0xFF0B1713),indicatorColor:green.withOpacity(.22),
        destinations:const[
          NavigationDestination(icon:Icon(Icons.mic),label:'LIVE MIC'),
          NavigationDestination(icon:Icon(Icons.audio_file),label:'PICK FILE'),
        ]),
    );
  }
  Widget header()=>Padding(padding:const EdgeInsets.fromLTRB(16,10,16,12),child:Row(children:[
    Container(width:46,height:46,decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:gold,width:1.5),color:Colors.black54),child:const Icon(Icons.graphic_eq,color:gold,size:27)),
    const SizedBox(width:12),const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('DDM MAX',style:TextStyle(fontSize:25,fontWeight:FontWeight.w900,letterSpacing:2,color:gold)),
      Text('IDRISH',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900,letterSpacing:5,color:Colors.white)),
      Text('HOLOGRAM X • PRO AUDIO',style:TextStyle(fontSize:9,color:green,letterSpacing:2)),
    ])),_pill('AUDIO READY'),
  ]));
  Widget scroll(List<Widget> c)=>SingleChildScrollView(padding:const EdgeInsets.fromLTRB(14,4,14,20),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:c));
  Widget title(String a,String b)=>Padding(padding:const EdgeInsets.only(bottom:10,top:5),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(a,style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold,letterSpacing:1)),
    Text(b,style:const TextStyle(fontSize:10,color:Colors.white60)),
  ]));
  Widget box(Widget c)=>Container(margin:const EdgeInsets.only(bottom:13),padding:const EdgeInsets.all(14),
    decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(23),border:Border.all(color:Colors.white.withOpacity(.16))),child:c);
  Widget delayPage()=>scroll([
    title('DDM MAX DIGITAL DELAY','LIVE MIC • Digital controls • Headphones recommended'),
    box(Row(children:[
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('TAP TEMPO',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),
        Text('$tapBpm BPM',style:const TextStyle(fontFamily:'monospace',fontSize:22,color:Color(0xFF65FF24),fontWeight:FontWeight.w900)),
      ])),
      FilledButton.icon(onPressed:tapTempo,icon:const Icon(Icons.touch_app),label:const Text('TAP'),
        style:FilledButton.styleFrom(backgroundColor:green,foregroundColor:Colors.black,shape:const StadiumBorder(),padding:const EdgeInsets.symmetric(horizontal:28,vertical:16))),
    ])),
    box(Column(children:[
      const Icon(Icons.mic,color:gold,size:38),
      Text(liveMonitoring?'LIVE MIC • EFFECT ON':'LIVE MIC • STANDBY',
        style:TextStyle(color:liveMonitoring?green:gold,fontWeight:FontWeight.w900,letterSpacing:1.1)),
      const SizedBox(height:9),
      SizedBox(width:double.infinity,child:FilledButton.icon(
        onPressed:toggleLiveMonitor,
        icon:Icon(liveMonitoring?Icons.stop_circle:Icons.play_circle_fill),
        label:Text(liveMonitoring?'STOP LIVE MIC':'START LIVE MIC'),
        style:FilledButton.styleFrom(backgroundColor:liveMonitoring?Colors.redAccent:green,
          foregroundColor:Colors.black,padding:const EdgeInsets.symmetric(vertical:14),
          shape:const StadiumBorder()),
      )),
    ])),
    box(Column(children:[
      const Text('FIVE MAIN DIGITAL CONTROLS',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),
      const SizedBox(height:14),
      Wrap(alignment:WrapAlignment.center,spacing:7,runSpacing:14,children:[
        numberControl('E.LEVEL',level,0,100,'%',1,(v)=>_changeLive(()=>level=v)),
        numberControl('FEEDBACK',feedback,0,92,'%',1,(v)=>_changeLive(()=>feedback=v)),
        numberControl('TIME / DELAY',delayTime,12.5,800,'ms',2,(v)=>_changeLive(()=>delayTime=v)),
        numberControl('BASS',eq[0],-12,12,'dB',1,(v)=>_changeLive(()=>eq[0]=v)),
        numberControl('TREBLE',eq[4],-12,12,'dB',1,(v)=>_changeLive(()=>eq[4]=v)),
      ]),
    ])),
    box(Column(children:[const Text('DELAY MODE',style:TextStyle(color:gold,fontWeight:FontWeight.w900)),const SizedBox(height:10),roundModeDial()])),
    box(Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Text('SHORT LOOP • RECORD / HOLD / REPEAT / STOP',
        style:TextStyle(color:gold,fontWeight:FontWeight.w900,fontSize:11)),
      const SizedBox(height:10),
      Wrap(spacing:7,runSpacing:7,alignment:WrapAlignment.center,children:[
        FilledButton.tonalIcon(onPressed:recording?null:startRecording,
          icon:const Icon(Icons.fiber_manual_record),label:const Text('RECORD')),
        FilledButton.tonalIcon(onPressed:recording?toggleRecordingHold:null,
          icon:Icon(recordingHeld?Icons.play_arrow:Icons.pause),
          label:Text(recordingHeld?'RESUME':'HOLD')),
        FilledButton.tonalIcon(onPressed:recorded==null?null:()async{
          setState(()=>loop=true);
          await player.setReleaseMode(ReleaseMode.loop);
          await play(recorded);
        },icon:const Icon(Icons.repeat),label:const Text('REPEAT')),
        FilledButton.tonalIcon(onPressed:()async{
          if(recording) await stopRecording();
          await stop();
          setState(()=>loop=false);
          await player.setReleaseMode(ReleaseMode.release);
        },icon:const Icon(Icons.stop),label:const Text('STOP')),
      ]),
      if(recorded!=null) Padding(padding:const EdgeInsets.only(top:8),
        child:Text('RECORDED LOOP READY • ${recorded!.path.split('/').last}',
          style:const TextStyle(color:green,fontSize:9))),
    ])),

    noiseControlCard(live:true),
    box(Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
      Expanded(child:roundToggle('PING-PONG L ↔ R',pingPong,Colors.purpleAccent,()=>_changeLive(()=>pingPong=!pingPong))),
      const SizedBox(width:10),
      Expanded(child:roundToggle('BYPASS',bypass,Colors.orangeAccent,()=>_changeLive(()=>bypass=!bypass))),
    ])),
    box(const Text('BASS and TREBLE controls adjust the low and high EQ bands.',style:TextStyle(color:Colors.white60,fontSize:10))),
  ]);

  Widget numberControl(String label,double value,double min,double max,String unit,double step,ValueChanged<double> onChanged){
    final shown=value.round().toString();
    void adjust(double direction){
      onChanged((value+direction*step).clamp(min,max).toDouble());
    }
    return SizedBox(width:146,child:Column(mainAxisSize:MainAxisSize.min,children:[
      SizedBox(height:20,child:Center(child:Text(label,maxLines:1,overflow:TextOverflow.ellipsis,
        style:const TextStyle(fontSize:10,fontWeight:FontWeight.w900,color:Colors.white,letterSpacing:.6)))),
      const SizedBox(height:5),
      Container(height:54,padding:const EdgeInsets.symmetric(horizontal:3),
        decoration:BoxDecoration(color:const Color(0xFF06121D),borderRadius:BorderRadius.circular(14),
          border:Border.all(color:green.withOpacity(.75),width:1.3),
          boxShadow:[BoxShadow(color:green.withOpacity(.13),blurRadius:10)]),
        child:Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
          _stepButton(Icons.remove,()=>adjust(-1)),
          Expanded(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
            FittedBox(fit:BoxFit.scaleDown,child:Text(shown,maxLines:1,
              style:const TextStyle(fontFamily:'monospace',fontSize:22,fontWeight:FontWeight.w900,
                color:Color(0xFF65FF24),shadows:[Shadow(color:green,blurRadius:8)]))),
            Text(unit,style:const TextStyle(fontSize:8,color:gold,fontWeight:FontWeight.bold)),
          ])),
          _stepButton(Icons.add,()=>adjust(1)),
        ]),
      ),
    ]));
  }

  Widget _stepButton(IconData icon,VoidCallback onPressed)=>SizedBox(
    width:34,height:42,child:IconButton(
      onPressed:onPressed, padding:EdgeInsets.zero, visualDensity:VisualDensity.compact,
      style:IconButton.styleFrom(backgroundColor:green.withOpacity(.16),
        foregroundColor:green,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10)),
        side:BorderSide(color:green.withOpacity(.45))),
      icon:Icon(icon,size:19),
    ),
  );

  Widget roundModeDial(){
    const labels=['S','M','L','SHORT LOOP'];
    const ranges=['12.5–50 ms','50–200 ms','200–800 ms','Record / Hold / Repeat'];
    return Column(children:[
      Wrap(spacing:7,runSpacing:8,alignment:WrapAlignment.center,children:[
        for(var i=0;i<labels.length;i++)
          SizedBox(width:i==3?150:66,child:OutlinedButton(
            onPressed:()=>_changeLive((){
              delayMode=i;
              dual=false;
              switch(i){
                case 0: delayTime=30; feedback=28; break;
                case 1: delayTime=200; feedback=30; break;
                case 2: delayTime=500; feedback=42; break;
                case 3: delayTime=200; feedback=55; break;
              }
              processed=null;
            }),
            style:OutlinedButton.styleFrom(
              backgroundColor:delayMode==i?green:const Color(0xFF071426),
              foregroundColor:delayMode==i?Colors.black:Colors.white,
              side:BorderSide(color:delayMode==i?green:const Color(0xFF174D80)),
              padding:const EdgeInsets.symmetric(horizontal:8,vertical:12),
              shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10))),
            child:Text(labels[i],textAlign:TextAlign.center,
              style:const TextStyle(fontSize:10,fontWeight:FontWeight.w900)))),
      ]),
      const SizedBox(height:10),
      Text(ranges[delayMode],style:const TextStyle(color:gold,fontSize:11,fontWeight:FontWeight.bold)),
      if(delayMode==3) const Padding(padding:EdgeInsets.only(top:5),
        child:Text('SHORT LOOP is a recorded phrase loop, not a long delay preset.',
          textAlign:TextAlign.center,style:TextStyle(color:Colors.white60,fontSize:9))),
    ]);
  }

  Widget roundToggle(String label,bool active,Color color,VoidCallback onTap)=>GestureDetector(
    onTap:onTap,
    child:Container(height:92,decoration:BoxDecoration(
      color:active?color.withOpacity(.18):const Color(0xFF09130F),
      borderRadius:BorderRadius.circular(46),
      border:Border.all(color:active?color:Colors.white24,width:active?2:1),
      boxShadow:active?[BoxShadow(color:color.withOpacity(.22),blurRadius:12)]:[]),
      child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
        Text(label,style:const TextStyle(fontSize:10,fontWeight:FontWeight.w900,letterSpacing:.6)),
        const SizedBox(height:3),
        Text(active?'01':'00',style:TextStyle(fontFamily:'monospace',fontSize:24,
          fontWeight:FontWeight.w900,color:active?color:Colors.white54)),
        Text(active?'ON':'OFF',style:const TextStyle(fontSize:8,color:Colors.white54,letterSpacing:1)),
      ]),
    ),
  );

  Widget filePage()=>scroll([
    title('PICK FILE • DIGITAL DELAY','Choose audio • Preview • Adjust effects • Apply & listen'),
    box(Row(children:[
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('TAP TEMPO',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),
        Text('$tapBpm BPM',style:const TextStyle(fontFamily:'monospace',fontSize:20,color:Color(0xFF65FF24),fontWeight:FontWeight.w900)),
      ])),
      FilledButton.icon(onPressed:tapTempo,icon:const Icon(Icons.touch_app),label:const Text('TAP'),
        style:FilledButton.styleFrom(backgroundColor:green,foregroundColor:Colors.black,shape:const StadiumBorder())),
    ])),
    box(Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Icon(Icons.audio_file,color:gold,size:38),
      Text(selected?.path.split('/').last??'NO FILE SELECTED',textAlign:TextAlign.center,maxLines:2,
        overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w900)),
      const SizedBox(height:5),
      Text('TOTAL LENGTH  ${_time(fileDuration)}',textAlign:TextAlign.center,
        style:const TextStyle(color:green,fontFamily:'monospace',fontSize:18,fontWeight:FontWeight.w900)),
      const SizedBox(height:9),
      action(Icons.folder_open,'PICK AUDIO FILE',()=>chooseAudio()),
      const SizedBox(height:8),
      Row(children:[
        Expanded(child:outlined(Icons.play_arrow,'PLAY ORIGINAL',()=>play(selected))),
        const SizedBox(width:6),
        Expanded(child:outlined(playbackPaused?Icons.play_arrow:Icons.pause,playbackPaused?'RESUME':'PAUSE',togglePause)),
        const SizedBox(width:6),
        Expanded(child:outlined(Icons.stop,'STOP',stop)),
      ]),
      Slider(value:fileDuration.inMilliseconds<=0?0:filePosition.inMilliseconds.clamp(0,fileDuration.inMilliseconds).toDouble(),
        min:0,max:fileDuration.inMilliseconds<=0?1:fileDuration.inMilliseconds.toDouble(),
        onChanged:fileDuration==Duration.zero?null:(v)=>player.seek(Duration(milliseconds:v.round()))),
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        Text(_time(filePosition),style:const TextStyle(color:gold,fontFamily:'monospace')),
        Text(_time(fileDuration),style:const TextStyle(color:Colors.white60,fontFamily:'monospace')),
      ]),
      sw('REPEAT / LOOP',loop,(v)async{setState(()=>loop=v);await player.setReleaseMode(v?ReleaseMode.loop:ReleaseMode.release);}),
    ])),
    box(Column(children:[
      const Text('FIVE MAIN DIGITAL CONTROLS',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),
      const SizedBox(height:14),
      Wrap(alignment:WrapAlignment.center,spacing:7,runSpacing:14,children:[
        numberControl('E.LEVEL',level,0,100,'%',1,(v)=>setState(() { level=v; processed=null; })),
        numberControl('FEEDBACK',feedback,0,92,'%',1,(v)=>setState(() { feedback=v; processed=null; })),
        numberControl('TIME / DELAY',delayTime,12.5,800,'ms',2,(v)=>setState(() { delayTime=v; processed=null; })),
        numberControl('BASS',eq[0],-12,12,'dB',1,(v)=>setState(() { eq[0]=v; processed=null; })),
        numberControl('TREBLE',eq[4],-12,12,'dB',1,(v)=>setState(() { eq[4]=v; processed=null; })),
      ]),
    ])),
    box(Column(children:[const Text('DELAY MODE',style:TextStyle(color:gold,fontWeight:FontWeight.w900)),const SizedBox(height:10),roundModeDial()])),
    noiseControlCard(),
    box(Row(children:[
      Expanded(child:roundToggle('PING-PONG L ↔ R',pingPong,Colors.purpleAccent,()=>setState(() { pingPong=!pingPong; processed=null; }))),
      const SizedBox(width:10),
      Expanded(child:roundToggle('BYPASS',bypass,Colors.orangeAccent,()=>setState(() { bypass=!bypass; processed=null; }))),
    ])),
    box(Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      FilledButton.icon(
        onPressed:working||selected==null?null:auditionEffect,
        icon:working?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.graphic_eq),
        label:Text(working?'PROCESSING AUDIO...':'APPLY EFFECT & LISTEN'),
        style:FilledButton.styleFrom(shape:const StadiumBorder(),padding:const EdgeInsets.symmetric(vertical:14))),
      const SizedBox(height:8),
      outlined(Icons.play_circle,'PLAY PROCESSED WAV',()=>play(processed)),
      const SizedBox(height:5),
      outlined(Icons.share,'EXPORT / SHARE WAV',()=>shareFile(processed)),
      if(processed!=null)Padding(padding:const EdgeInsets.only(top:8),
        child:Text('READY: ${processed!.path.split('/').last}',style:const TextStyle(color:green,fontSize:10))),
    ])),
    const Text('MP3, M4A, AAC, OGG and WAV are supported when the Android decoder can read the file. Effect output is always WAV.',
      style:TextStyle(color:Colors.white60,fontSize:10)),
  ]);

  Widget noiseControlCard({bool live=false}) {
    void update(VoidCallback change) {
      if (live) { _changeLive(change); } else { setState(() { change(); processed=null; }); }
    }
    return box(Column(children:[
      Row(children:[const Icon(Icons.graphic_eq,color:green,size:24),const SizedBox(width:8),
        Text(live?'ANC • LIVE MIC NOISE REDUCTION':'ANC • FILE NOISE REDUCTION',style:const TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:.6))]),
      const SizedBox(height:10),
      Row(children:[
        Expanded(child:roundToggle('ANC',noiseReduction,green,()=>update(()=>noiseReduction=!noiseReduction))),
        const SizedBox(width:10),
        Expanded(child:numberControl('ANC LEVEL',ancLevel,0,100,'%',1,(v)=>update(()=>ancLevel=v))),
      ]),
      const SizedBox(height:7),
      const SizedBox(height:6),
      Text(live?'ANC Level live mic noise filtering ko adjust karta hai; device hardware support alag ho sakta hai.':'File ANC ek software high-pass filter + noise gate hai, hardware ANC nahi. Isse low rumble/noise kam hota hai; voice/music ke kuch low frequencies bhi kam ho sakti hain. Ping-Pong stereo echo ko Left aur Right mein move karta hai.',
        style:TextStyle(color:Colors.white60,fontSize:9)),
    ]));
  }
  Widget settingsPage()=>scroll([
    title('SETTINGS','Playback and app information'),
    box(const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('APP VERSION 1.0',style:TextStyle(color:gold,fontWeight:FontWeight.bold)),
      SizedBox(height:8),Text('Audio processing: WAV file engine'),
      Text('Microphone: Android record permission'),
      Text('Playback volume can be adjusted below.'),
      Text('Developer: IDRISH'),
      SizedBox(height:8),Text('For best results, use WAV audio at 44.1 kHz.',style:TextStyle(color:Colors.white60,fontSize:11)),
    ])),
    box(Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      slider('PLAYBACK VOLUME',playbackVolume*100,0,100,'${(playbackVolume*100).round()}%',(v){setState(()=>playbackVolume=v/100);player.setVolume(v/100);}),
      const Text('Dark console theme is enabled.',style:TextStyle(color:Colors.white60,fontSize:11)),
    ])),
  ]);
  Widget slider(String name,double value,double min,double max,String read,ValueChanged<double> onChanged)=>Padding(
    padding:const EdgeInsets.only(bottom:7),child:Column(children:[
      Row(children:[Expanded(child:Text(name,style:const TextStyle(fontSize:11,fontWeight:FontWeight.bold,letterSpacing:.7))),Text(read,style:const TextStyle(color:gold,fontWeight:FontWeight.bold,fontSize:12))]),
      Slider(value:value.clamp(min,max).toDouble(),min:min,max:max,onChanged:onChanged),
    ]));
  Widget sw(String label,bool value,ValueChanged<bool> fn)=>Row(children:[Expanded(child:Text(label,style:const TextStyle(fontSize:11,fontWeight:FontWeight.bold))),Switch(value:value,activeColor:green,onChanged:fn)]);
  Widget mode(String label,bool active,VoidCallback fn)=>OutlinedButton(
    onPressed:fn,style:OutlinedButton.styleFrom(backgroundColor:active?green:Colors.transparent,foregroundColor:active?Colors.black:Colors.white,side:BorderSide(color:active?green:Colors.white30),padding:const EdgeInsets.symmetric(vertical:11)),
    child:Text(label,style:const TextStyle(fontSize:10,fontWeight:FontWeight.bold)));
  Widget action(IconData icon,String label,VoidCallback fn)=>SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:fn,icon:Icon(icon),label:Text(label),style:FilledButton.styleFrom(backgroundColor:green,foregroundColor:Colors.black,shape:const StadiumBorder(),padding:const EdgeInsets.symmetric(vertical:14))));
  Widget outlined(IconData icon,String label,VoidCallback fn)=>SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:fn,icon:Icon(icon),label:Text(label,style:const TextStyle(fontSize:10)),style:OutlinedButton.styleFrom(shape:const StadiumBorder(),padding:const EdgeInsets.symmetric(vertical:12))));
  Widget _pill(String s)=>Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:7),decoration:BoxDecoration(color:green.withOpacity(.16),borderRadius:BorderRadius.circular(20),border:Border.all(color:green.withOpacity(.5))),child:Text(s,style:const TextStyle(color:green,fontSize:9,fontWeight:FontWeight.bold)));
}