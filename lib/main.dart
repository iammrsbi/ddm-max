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
const green = Color(0xFF00BFFF), gold = Color(0xFFFFC857), panel = Color(0xB0081424);

class DDMMaxApp extends StatelessWidget {
  const DDMMaxApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner:false, title:'DDM-MAX',
    theme:ThemeData(brightness:Brightness.dark,scaffoldBackgroundColor:const Color(0xFF07110E),
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
  int delayMode=0;
  static const List<String> delayModeNames=['STANDARD','ANALOG','TAPE','WARM','MOD','DUAL'];
  Duration fileDuration=Duration.zero, filePosition=Duration.zero;
  bool playbackPaused=false;
  double level=80,feedback=38,delayTime=320,mix=45;
  final List<double> eq=[0,0,0,0,0];
  String eqPreset='FLAT';
  bool bypass=false,pingPong=false,dual=false,loop=false,recording=false,working=false,liveMonitoring=false;
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
        try { await source.copy(destination.path); } catch (_) {}
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
        type: FileType.audio, allowMultiple: false, withReadStream: true, withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = await _copyPickedAudio(result.files.single);

      await player.stop();
      setState(() {
        selected = file; processed = null;
        fileDuration = Duration.zero; filePosition = Duration.zero; playbackPaused = false;
      });
      try {
        await player.setSource(DeviceFileSource(file.path));
        final duration = await player.getDuration();
        if (mounted && duration != null) setState(() => fileDuration = duration);
      } catch (_) {
        note('File import ho gayi. Preview codec support nahi mila; APPLY EFFECT try karo.');
      }
      note('File import ho gayi. Original preview chalao, phir controls set karke APPLY & LISTEN dabao.');
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
  Future<void> auditionEffect() async { await process(selected); final output=processed; if(output!=null) await play(output); }

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
      note('Effect apply ho gaya. WAV file ready hai — ab Play Processed dabao.');
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
        Image.asset('assets/combo_bg.jpg',fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(color:const Color(0xFF07110E))),
        Container(color:const Color(0x5507100D)),
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
      Text('DDM-MAX',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900,letterSpacing:2)),
      Text('DIGITAL DELAY • NAAT AUDIO SYSTEM',style:TextStyle(fontSize:9,color:gold,letterSpacing:1.1)),
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
      const Text('FIVE DIGITAL CONTROLS',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),
      const SizedBox(height:12),
      Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
        Expanded(child:roundDial('E.LEVEL',level,0,100,'${level.round()}','%',(v)=>_changeLive(()=>level=v))),
        const SizedBox(width:8),
        Expanded(child:roundDial('F.BACK',feedback,0,92,'${feedback.round()}','%',(v)=>_changeLive(()=>feedback=v))),
      ]),
      const SizedBox(height:12),
      Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
        Expanded(child:roundDial('TIME',delayTime,40,1200,'${delayTime.round()}','ms',(v)=>_changeLive(()=>delayTime=v))),
        const SizedBox(width:8),
        Expanded(child:roundDial('BASS',eq[0],-12,12,'${eq[0].round()}','dB',(v)=>_changeLive(()=>eq[0]=v))),
      ]),
    ])),
    box(Row(children:[Expanded(child:roundDial('TREBLE',eq[4],-12,12,'${eq[4].round()}','dB',(v)=>_changeLive(()=>eq[4]=v))),const SizedBox(width:12),Expanded(child:roundModeDial())])),
    noiseControlCard(live:true),
    box(Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
      Expanded(child:roundToggle('PING-PONG',pingPong,Colors.purpleAccent,()=>_changeLive(()=>pingPong=!pingPong))),
      const SizedBox(width:10),
      Expanded(child:roundToggle('BYPASS',bypass,Colors.orangeAccent,()=>_changeLive(()=>bypass=!bypass))),
    ])),
    box(const Text('BASS and TREBLE controls adjust the low and high EQ bands.',style:TextStyle(color:Colors.white60,fontSize:10))),
  ]);

  Widget roundDial(String label,double value,double min,double max,String number,String unit,ValueChanged<double> onChanged){
    final progress=((value-min)/(max-min)).clamp(0.0,1.0).toDouble();
    return Center(child:GestureDetector(
      onVerticalDragUpdate:(details)=>onChanged((value-details.delta.dy*(max-min)/150).clamp(min,max).toDouble()),
      child:SizedBox(width:142,height:142,child:Stack(alignment:Alignment.center,children:[
        SizedBox(width:132,height:132,child:CircularProgressIndicator(
          value:progress,strokeWidth:5,backgroundColor:Colors.white12,
          valueColor:AlwaysStoppedAnimation<Color>(green))),
        Container(width:116,height:116,decoration:BoxDecoration(
          shape:BoxShape.circle,
          gradient:const RadialGradient(colors:[Color(0xFF1A3028),Color(0xFF050B08)]),
          border:Border.all(color:gold.withOpacity(.75),width:1.4),
          boxShadow:[BoxShadow(color:green.withOpacity(.20),blurRadius:13)]),
          child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
            Text(label,style:const TextStyle(fontSize:10,fontWeight:FontWeight.w900,color:Colors.white,letterSpacing:.8)),
            const SizedBox(height:4),
            FittedBox(child:Text(number,style:const TextStyle(fontFamily:'monospace',fontSize:28,
              fontWeight:FontWeight.w900,color:Color(0xFF65FF24),
              shadows:[Shadow(color:green,blurRadius:12)]))),
            Text(unit,style:const TextStyle(color:gold,fontSize:10,fontWeight:FontWeight.bold)),
            const SizedBox(height:3),
            const Text('DRAG',style:TextStyle(color:Colors.white38,fontSize:8,letterSpacing:1)),
          ])),
      ])),
    ));
  }

  Widget roundModeDial(){
    final name=delayModeNames[delayMode];
    return Center(child:GestureDetector(
      onTap:()=>_changeLive(() { delayMode=(delayMode+1)%delayModeNames.length; dual=delayMode==5; }),
      child:Container(width:132,height:132,decoration:BoxDecoration(
        shape:BoxShape.circle,gradient:const RadialGradient(colors:[Color(0xFF243B34),Color(0xFF050B08)]),
        border:Border.all(color:Colors.lightBlueAccent,width:2),
        boxShadow:[BoxShadow(color:Colors.lightBlueAccent.withOpacity(.20),blurRadius:14)]),
        child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
          const Text('MODE',style:TextStyle(fontSize:10,fontWeight:FontWeight.w900,color:Colors.white,letterSpacing:1)),
          const SizedBox(height:4),
          Text((delayMode+1).toString().padLeft(2,'0'),style:const TextStyle(fontFamily:'monospace',
            fontSize:29,fontWeight:FontWeight.w900,color:Color(0xFF65FF24),
            shadows:[Shadow(color:green,blurRadius:12)])),
          Text(name,style:const TextStyle(color:gold,fontSize:9,fontWeight:FontWeight.w900)),
          const SizedBox(height:3),
          const Text('TAP TO CHANGE',style:TextStyle(color:Colors.white38,fontSize:8,letterSpacing:.7)),
        ]),
      ),
    ));
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
      const Text('FIVE DIGITAL CONTROLS',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),
      const SizedBox(height:12),
      Row(children:[
        Expanded(child:roundDial('E.LEVEL',level,0,100,'${level.round()}','%',(v)=>setState(() { level=v; processed=null; }))),
        const SizedBox(width:8),
        Expanded(child:roundDial('F.BACK',feedback,0,92,'${feedback.round()}','%',(v)=>setState(() { feedback=v; processed=null; }))),
      ]),
      const SizedBox(height:12),
      Row(children:[
        Expanded(child:roundDial('TIME',delayTime,40,1200,'${delayTime.round()}','ms',(v)=>setState(() { delayTime=v; processed=null; }))),
        const SizedBox(width:8),
        Expanded(child:roundDial('BASS',eq[0],-12,12,'${eq[0].round()}','dB',(v)=>setState(() { eq[0]=v; processed=null; }))),
      ]),
    ])),
    box(Row(children:[Expanded(child:roundDial('TREBLE',eq[4],-12,12,'${eq[4].round()}','dB',(v)=>setState(() { eq[4]=v; processed=null; }))),const SizedBox(width:12),Expanded(child:roundModeDial())])),
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
      const Row(children:[Icon(Icons.graphic_eq,color:green,size:24),SizedBox(width:8),
        Text('ANC • MIC NOISE REDUCTION',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:.6))]),
      const SizedBox(height:10),
      Row(children:[
        Expanded(child:roundToggle('ANC',noiseReduction,green,()=>update(()=>noiseReduction=!noiseReduction))),
        const SizedBox(width:10),
        Expanded(child:roundDial('ANC LEVEL',ancLevel,0,100,'${ancLevel.round()}','%',(v)=>update(()=>ancLevel=v))),
      ]),
      const SizedBox(height:7),
      const SizedBox(height:6),
      const Text('ANC Level noise reduction strength ko adjust karta hai. Hardware support device ke hisaab se badal sakta hai. Ping-Pong stereo echo ko Left aur Right mein move karta hai.',
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