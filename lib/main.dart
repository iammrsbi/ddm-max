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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'wav_echo_engine.dart';

void main() => runApp(const DDMMaxApp());
const green = Color(0xFF20C878), gold = Color(0xFFFFC857), panel = Color(0xDD101B18);

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
  File? selected,processed,recorded;
  List<File> library=[];
  double playbackVolume=1.0,ancLevel=65;
  String? recordingPath;

  @override void initState(){super.initState();_loadLibrary(); player.onDurationChanged.listen((d){if(mounted)setState(()=>fileDuration=d);}); player.onPositionChanged.listen((p){if(mounted)setState(()=>filePosition=p);}); player.onPlayerStateChanged.listen((st){if(mounted)setState(()=>playbackPaused=st!=PlayerState.playing);}); player.onPlayerComplete.listen((_){if(mounted)setState(()=>filePosition=fileDuration);});}
  Future<void> _loadLibrary() async {
    final prefs=await SharedPreferences.getInstance();
    final paths=prefs.getStringList('ddm_naat_library')??[];
    if(mounted)setState(()=>library=paths.where((p)=>File(p).existsSync()).map((p)=>File(p)).toList());
  }
  @override void dispose(){liveChannel.invokeMethod('stop');player.dispose();recorder.dispose();super.dispose();}

  void note(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  Future<void> chooseAudio({bool forLibrary=false}) async {
    try {
      final r=await FilePicker.platform.pickFiles(type:FileType.audio,allowMultiple:false,withReadStream:true);
      if(r==null||r.files.isEmpty)return;
      final picked=r.files.single;
      File f;
      if(picked.path!=null){
        f=File(picked.path!);
      }else if(picked.readStream!=null){
        final d=await getApplicationDocumentsDirectory();
        final imports=Directory('${d.path}/DDM-MAX/Imported');
        await imports.create(recursive:true);
        final safe=picked.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'),'_');
        f=File('${imports.path}/${DateTime.now().millisecondsSinceEpoch}_$safe');
        await picked.readStream!.pipe(f.openWrite());
      }else{
        note('Phone se file ka path nahi mila. Dobara file select karo.');
        return;
      }
      setState((){if(forLibrary){if(!library.any((x)=>x.path==f.path))library.add(f);}else{selected=f;processed=null;fileDuration=Duration.zero;filePosition=Duration.zero;}});
      if(!forLibrary){try{await player.stop();await player.setSource(DeviceFileSource(f.path));fileDuration=await player.getDuration()??Duration.zero;}catch(_){} if(mounted)setState((){});}
      if(forLibrary){final prefs=await SharedPreferences.getInstance();await prefs.setStringList('ddm_naat_library',library.map((x)=>x.path).toList());}
      note('Audio file select ho gayi.');
    }catch(e){note('File select error: $e');}
  }
  Future<void> play(File? f) async {
    if(f==null){note('Pehle audio file select karo.');return;}
    try{await player.stop();await player.setVolume(playbackVolume);await player.setReleaseMode(loop?ReleaseMode.loop:ReleaseMode.release);await player.play(DeviceFileSource(f.path));}
    catch(e){note('Play error: $e');}
  }
  Future<void> togglePause() async {try {if(player.state==PlayerState.playing){await player.pause();}else{await player.resume();}}catch(e){note('Playback control error: $e');}}
  String _time(Duration d){final m=d.inMinutes.remainder(60).toString().padLeft(2,'0');final sec=d.inSeconds.remainder(60).toString().padLeft(2,'0');final h=d.inHours;return h>0?'$h:$m:$sec':'$m:$sec';}
  Future<void> auditionEffect() async {await process(selected);if(processed!=null)await play(processed);}

  Future<void> stop() async {await player.stop();}
  Future<void> process(File? source) async {
    if(source==null){note('Pehle audio file select ya record karo.');return;}
    setState(()=>{working=true;processed=null;});
    try{
      final d=await getApplicationDocumentsDirectory();
      final out=await WavEchoEngine.render(input:source,outputDirectory:Directory('${d.path}/DDM-MAX'),
        delayMs:delayTime.round(),feedback:feedback/100,mix:mix/100,level:level/100,
        eq:eq,pingPong:pingPong,dual:dual,bypass:bypass,noiseReduction:noiseReduction,noiseGate:noiseGate,ancLevel:ancLevel/100);
      if(!mounted)return;
      setState(()=>processed=out);note('Processed WAV save ho gayi.');
    }catch(e){note('Processing error: $e');}
    finally{if(mounted)setState(()=>working=false);}
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
      final caps=await liveChannel.invokeMapMethod<String,dynamic>('start', {'delayMs':delayTime.round(),'feedback':feedback/100,'mix':mix/100,'level':level/100,'noiseReduction':noiseReduction,'noiseGate':noiseGate,'ancLevel':ancLevel/100,'dual':dual,'pingPong':pingPong,'bypass':bypass,'eq':eq});
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
    'dual':dual,'pingPong':pingPong,'bypass':bypass,'eq':eq,
  });
  Future<void> _updateLiveEngine() async {
    if(!liveMonitoring)return;
    try{await liveChannel.invokeMethod('update',_liveConfig());}
    catch(e){note('Live control update error: $e');}
  }
  void _changeLive(VoidCallback change){setState(change);_updateLiveEngine();}
  Future<void> _openHadaiqBook({required bool pdf}) async {
    final uri=Uri.parse(pdf
      ?'https://data2.dawateislami.net/Data/Books/Download/hi/pdf/2015/290-1.pdf?fn=hadaiq-e-bakhshish'
      :'https://www.dawateislami.net/bookslibrary/hi/hadaiq-e-bakhshish');
    try{final ok=await launchUrl(uri,mode:LaunchMode.externalApplication);if(!ok)note('Book link open nahi hua. Internet check karo.');}
    catch(e){note('Book open error: $e');}
  }
  @override Widget build(BuildContext context){
    final pages=[delayPage(),filePage()];
    return Scaffold(
      body:Stack(fit:StackFit.expand,children:[
        Image.asset('assets/combo_bg.jpg',fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(color:const Color(0xFF07110E))),
        Container(color:const Color(0xE607100D)),
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
    decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(17),border:Border.all(color:Colors.white.withOpacity(.13))),child:c);
  Widget delayPage()=>scroll([
    title('LIVE MIC','Real-time digital delay • headphones recommended'),
    box(Column(children:[
      const Icon(Icons.mic,color:gold,size:42),
      Text(liveMonitoring?'LIVE EFFECT RUNNING':'MICROPHONE STANDBY',style:TextStyle(color:liveMonitoring?green:gold,fontWeight:FontWeight.w900,letterSpacing:1.2)),
      const SizedBox(height:10),
      SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:toggleLiveMonitor,icon:Icon(liveMonitoring?Icons.stop_circle:Icons.play_circle_fill),label:Text(liveMonitoring?'STOP LIVE MIC':'START LIVE MIC'),style:FilledButton.styleFrom(backgroundColor:liveMonitoring?Colors.redAccent:green,foregroundColor:Colors.black,padding:const EdgeInsets.symmetric(vertical:15)))),
    ])),
    box(Column(children:[
      Row(children:[
        Expanded(child:ledMetric('DELAY TIME','${delayTime.round()}','ms',delayTime,40,1200,(v)=>_changeLive(()=>delayTime=v))),
        const SizedBox(width:7),
        Expanded(child:ledMetric('FEEDBACK','${feedback.round()}','%',feedback,0,92,(v)=>_changeLive(()=>feedback=v))),
      ]),
      const SizedBox(height:8),
      Row(children:[
        Expanded(child:ledMetric('LEVEL','${level.round()}','%',level,0,100,(v)=>_changeLive(()=>level=v))),
        const SizedBox(width:7),
        Expanded(child:ledMetric('MIX','${mix.round()}','%',mix,0,100,(v)=>_changeLive(()=>mix=v))),
      ]),
    ])),
    noiseControlCard(),
    box(Column(children:[
      Row(children:[Expanded(child:neonMode('SINGLE DELAY',!dual,green,()=>_changeLive(()=>dual=false))),const SizedBox(width:7),Expanded(child:neonMode('DUAL DELAY',dual,Colors.lightBlueAccent,()=>_changeLive(()=>dual=true)))]),
      const SizedBox(height:8),
      Row(children:[Expanded(child:neonMode('PING-PONG',pingPong,Colors.purpleAccent,()=>_changeLive(()=>pingPong=!pingPong))),const SizedBox(width:7),Expanded(child:neonMode('BYPASS',bypass,Colors.orangeAccent,()=>_changeLive(()=>bypass=!bypass)))]),
    ])),
    box(Column(children:[
      const Text('5-BAND EQ',style:TextStyle(color:gold,fontWeight:FontWeight.w900)),
      for(int i=0;i<5;i++) slider(['BASS 100 Hz','LOW MID 350 Hz','MID 1 kHz','HIGH MID 3.5 kHz','TREBLE 9 kHz'][i],eq[i],-12,12,'${eq[i].round()} dB',(v)=>_changeLive(()=>eq[i]=v)),
    ])),
  ]);

    Widget ledMetric(String label,String value,String unit,double current,double min,double max,ValueChanged<double> changed)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:7,vertical:10),
    decoration:BoxDecoration(color:const Color(0xF4081710),borderRadius:BorderRadius.circular(14),border:Border.all(color:green.withOpacity(.85),width:1.3),boxShadow:[BoxShadow(color:green.withOpacity(.18),blurRadius:10)]),
    child:Column(children:[
      Text(label,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w900,color:Colors.white,letterSpacing:.8)),
      const SizedBox(height:4),
      FittedBox(fit:BoxFit.scaleDown,child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
        Text(value,style:const TextStyle(fontFamily:'monospace',fontSize:30,fontWeight:FontWeight.w900,color:Color(0xFF65FF24),shadows:[Shadow(color:green,blurRadius:12)])),
        Padding(padding:const EdgeInsets.only(bottom:5,left:3),child:Text(unit,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold))),
      ])),
      Slider(value:current.clamp(min,max).toDouble(),min:min,max:max,onChanged:changed),
    ]),
  );
  Widget neonMode(String label,bool active,Color color,VoidCallback fn)=>SizedBox(width:double.infinity,height:54,child:OutlinedButton(
    onPressed:fn,
    style:OutlinedButton.styleFrom(backgroundColor:active?color.withOpacity(.2):Colors.black54,foregroundColor:active?color:Colors.white,side:BorderSide(color:active?color:Colors.white30,width:active?2:1),shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(13)),shadowColor:color,elevation:active?8:0),
    child:Text(label,textAlign:TextAlign.center,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w900,letterSpacing:.7)),
  ));
  Widget filePage()=>scroll([
    title('PICK FILE • AUDIO EDITOR','Upload, edit, audition effects, play/pause and save.'),
    box(Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Icon(Icons.audio_file,color:gold,size:42),
      Text(selected?.path.split('/').last??'NO FILE SELECTED',textAlign:TextAlign.center,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w900)),
      const SizedBox(height:6),
      Text('FILE LENGTH  ${_time(fileDuration)}',textAlign:TextAlign.center,style:const TextStyle(color:green,fontFamily:'monospace',fontSize:18,fontWeight:FontWeight.w900)),
      const SizedBox(height:8),
      action(Icons.folder_open,'PICK AUDIO FILE',()=>chooseAudio()),
      const SizedBox(height:8),
      Row(children:[
        Expanded(child:outlined(Icons.play_arrow,'PLAY ORIGINAL',()=>play(selected))),
        const SizedBox(width:5),
        Expanded(child:outlined(playbackPaused?Icons.play_arrow:Icons.pause,playbackPaused?'RESUME':'PAUSE',togglePause)),
        const SizedBox(width:5),
        Expanded(child:outlined(Icons.stop,'STOP',stop)),
      ]),
      Slider(value:fileDuration.inMilliseconds<=0?0:filePosition.inMilliseconds.clamp(0,fileDuration.inMilliseconds).toDouble(),min:0,max:fileDuration.inMilliseconds<=0?1:fileDuration.inMilliseconds.toDouble(),onChanged:fileDuration==Duration.zero?null:(v)=>player.seek(Duration(milliseconds:v.round()))),
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(_time(filePosition),style:const TextStyle(color:gold,fontFamily:'monospace')),Text(_time(fileDuration),style:const TextStyle(color:Colors.white60,fontFamily:'monospace'))]),
      sw('REPEAT / LOOP',loop,(v)async{setState(()=>loop=v);await player.setReleaseMode(v?ReleaseMode.loop:ReleaseMode.release);}),
    ])),
    box(Column(children:[
      const Text('DIGITAL DELAY • EFFECT CONTROLS',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:1)),
      slider('DELAY TIME',delayTime,40,1200,'${delayTime.round()} ms',(v)=>setState(()=>delayTime=v)),
      slider('FEEDBACK',feedback,0,92,'${feedback.round()}%',(v)=>setState(()=>feedback=v)),
      slider('EFFECT MIX',mix,0,100,'${mix.round()}%',(v)=>setState(()=>mix=v)),
      slider('OUTPUT LEVEL',level,0,100,'${level.round()}%',(v)=>setState(()=>level=v)),
      Row(children:[Expanded(child:neonMode('SINGLE',!dual,green,()=>setState(()=>dual=false))),const SizedBox(width:6),Expanded(child:neonMode('DUAL',dual,Colors.lightBlueAccent,()=>setState(()=>dual=true)))]),
      const SizedBox(height:6),
      Row(children:[Expanded(child:neonMode('PING-PONG',pingPong,Colors.purpleAccent,()=>setState(()=>pingPong=!pingPong))),const SizedBox(width:6),Expanded(child:neonMode('BYPASS',bypass,Colors.orangeAccent,()=>setState(()=>bypass=!bypass)))]),
    ])),
    box(Column(children:[
      const Text('5-BAND EQ',style:TextStyle(color:gold,fontWeight:FontWeight.w900)),
      for(int i=0;i<5;i++) slider(['BASS 100 Hz','LOW MID 350 Hz','MID 1 kHz','HIGH MID 3.5 kHz','TREBLE 9 kHz'][i],eq[i],-12,12,'${eq[i].round()} dB',(v)=>setState(()=>eq[i]=v)),
      sw('NOISE REDUCTION FILTER',noiseReduction,(v)=>setState(()=>noiseReduction=v)),
      sw('NOISE GATE',noiseGate,(v)=>setState(()=>noiseGate=v)),
    ])),
    box(Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      FilledButton.icon(onPressed:working||selected==null?null:auditionEffect,icon:working?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.headphones),label:Text(working?'PROCESSING...':'AUDITION CURRENT EFFECT')),
      const SizedBox(height:7),
      outlined(Icons.play_circle,'PLAY PROCESSED FILE',()=>play(processed)),
      outlined(Icons.share,'SHARE / EXPORT PROCESSED WAV',()=>shareFile(processed)),
      if(processed!=null)Text('Output: ${processed!.path.split('/').last}',style:const TextStyle(color:green,fontSize:10)),
    ])),
    const Text('Effect processing currently supports PCM 16-bit mono/stereo WAV. Other formats may play, but must be converted to WAV before applying effects.',style:TextStyle(color:Colors.orangeAccent,fontSize:10)),
  ]);

    Widget eqPage()=>scroll([
    title('5-BAND EQUALIZER','EQ is applied to the next processed audio output.'),
    box(Column(children:[
      Row(children:[Expanded(child:mode('FLAT',eqPreset=='FLAT',()=>_changeLive((){eq.fillRange(0,5,0);eqPreset='FLAT';}))),const SizedBox(width:7),Expanded(child:mode('NAAT VOICE',eqPreset=='NAAT VOICE',()=>_changeLive((){eq[0]=1;eq[1]=1;eq[2]=3;eq[3]=4;eq[4]=2;eqPreset='NAAT VOICE';})))]),
      slider('BASS • 100 Hz',eq[0],-12,12,'${eq[0].round()} dB',(v)=>_changeLive(() {eq[0]=v;eqPreset='CUSTOM';})),
      slider('LOW MID • 350 Hz',eq[1],-12,12,'${eq[1].round()} dB',(v)=>_changeLive(() {eq[1]=v;eqPreset='CUSTOM';})),
      slider('MID • 1 kHz',eq[2],-12,12,'${eq[2].round()} dB',(v)=>_changeLive(() {eq[2]=v;eqPreset='CUSTOM';})),
      slider('HIGH MID • 3.5 kHz',eq[3],-12,12,'${eq[3].round()} dB',(v)=>_changeLive(() {eq[3]=v;eqPreset='CUSTOM';})),
      slider('TREBLE • 9 kHz',eq[4],-12,12,'${eq[4].round()} dB',(v)=>_changeLive(() {eq[4]=v;eqPreset='CUSTOM';})),
      Row(children:[Expanded(child:mode('BASS BOOST',eqPreset=='BASS BOOST',()=>_changeLive((){eq[0]=8;eq[1]=3;eqPreset='BASS BOOST';}))),const SizedBox(width:8),Expanded(child:mode('CLEAR VOCAL',eqPreset=='CLEAR VOCAL',()=>_changeLive((){eq[2]=3;eq[3]=6;eq[4]=3;eqPreset='CLEAR VOCAL';})))]),
      const SizedBox(height:8),const Text('EQ values are used by PROCESS & SAVE ECHO on the File Echo or Record tab.',style:TextStyle(color:Colors.white60,fontSize:10)),
    ])),
    FilledButton.icon(onPressed:()=>setState(()=>tab=1),icon:const Icon(Icons.audio_file),label:const Text('GO TO FILE ECHO')),
  ]);
  Widget recordPage()=>scroll([
    title('LIVE MIC & RECORDING','Mic noise reduction, noise gate, live echo and recording.'),
    noiseControlCard(),
    box(Column(children:[
      Icon(recording?Icons.fiber_manual_record:Icons.mic,size:64,color:recording?Colors.redAccent:gold),
      Text(recording?'RECORDING NOW':'MICROPHONE READY',style:const TextStyle(fontWeight:FontWeight.bold,letterSpacing:1)),
      const SizedBox(height:12),
      SizedBox(width:double.infinity,child:OutlinedButton.icon(
        onPressed:recording?null:toggleLiveMonitor,
        icon:Icon(liveMonitoring?Icons.stop_circle:Icons.hearing),
        label:Text(liveMonitoring?'STOP LIVE MIC EFFECT':'START LIVE MIC EFFECT'),
      )),
      const SizedBox(height:8),
      SizedBox(width:double.infinity,child:FilledButton.icon(
        style:FilledButton.styleFrom(backgroundColor:recording?Colors.red.shade700:green,foregroundColor:Colors.black),
        onPressed:recording?stopRecording:() async {if(liveMonitoring) await toggleLiveMonitor(); await startRecording();},
        icon:Icon(recording?Icons.stop:Icons.fiber_manual_record),label:Text(recording?'STOP & SAVE RECORDING':'START RECORDING'))),
      const SizedBox(height:8),Text(recorded?.path.split('/').last??'No recording saved yet',style:const TextStyle(color:Colors.white60,fontSize:11)),
      Row(children:[Expanded(child:outlined(Icons.play_arrow,'PLAY RECORDING',()=>play(recorded))),const SizedBox(width:7),Expanded(child:outlined(Icons.stop,'STOP',stop))]),
      FilledButton.icon(onPressed:working||recorded==null?null:()=>process(recorded),icon:const Icon(Icons.graphic_eq),label:const Text('PROCESS RECORDING WITH EFFECTS')),
      outlined(Icons.share,'SHARE PROCESSED RECORDING',()=>shareFile(processed)),
    ])),
    const Text('Mic noise reduction uses speech filtering and a noise gate. It reduces background noise; it is not the same as hardware ANC in headphones.',style:TextStyle(color:Colors.white54,fontSize:10)),
  ]);
  Widget noiseControlCard()=>box(Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const Row(children:[Icon(Icons.graphic_eq,color:green,size:25),SizedBox(width:8),Text('ANC • MIC NOISE CONTROL',style:TextStyle(color:gold,fontWeight:FontWeight.w900,letterSpacing:.7))]),
    const SizedBox(height:5),
    sw('ANC / NOISE REDUCTION',noiseReduction,(v)=>_changeLive(()=>noiseReduction=v)),
    slider('ANC LEVEL',ancLevel,0,100,'${ancLevel.round()}%',(v)=>_changeLive(()=>ancLevel=v)),
    sw('NOISE GATE',noiseGate,(v)=>_changeLive(()=>noiseGate=v)),
    const Text('Software mic noise reduction • 0–100%',style:TextStyle(color:Colors.white60,fontSize:10)),
  ]));
  Widget libraryPage()=>scroll([
    title('NAAT COLLECTION','Hadaiq-e-Bakhshish Hindi book aur apni Naat audio files.'),
    box(Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Row(children:[Icon(Icons.menu_book,color:gold,size:34),SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('हदाइक़े बख़्शिश',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900,color:gold)),
        Text('Imam Ahmad Raza Khan • Hindi • 498 pages',style:TextStyle(fontSize:10,color:Colors.white70)),
      ]))]),
      const SizedBox(height:10),
      Row(children:[
        Expanded(child:FilledButton.icon(onPressed:()=>_openHadaiqBook(pdf:false),icon:const Icon(Icons.menu_book),label:const Text('READ ONLINE'))),
        const SizedBox(width:8),
        Expanded(child:OutlinedButton.icon(onPressed:()=>_openHadaiqBook(pdf:true),icon:const Icon(Icons.picture_as_pdf),label:const Text('OPEN / DOWNLOAD PDF'))),
      ]),
      const Text('Official Dawat-e-Islami Hindi edition. Internet connection required.',style:TextStyle(fontSize:10,color:Colors.white54)),
    ])),
    title('MY NAAT AUDIO','Add and play your own Naat recordings.'),
    box(Column(children:[
      const Icon(Icons.library_music,size:48,color:gold),const Text('MY NAAT COLLECTION',style:TextStyle(fontWeight:FontWeight.bold)),
      const SizedBox(height:8),action(Icons.add,'ADD NAAT AUDIO',()=>chooseAudio(forLibrary:true)),
    ])),
    if(library.isEmpty)box(const Text('Abhi collection khaali hai. ADD NAAT AUDIO se apni files add karo.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white60))),
    ...library.map((f)=>box(Row(children:[
      const Icon(Icons.music_note,color:gold),const SizedBox(width:8),Expanded(child:Text(f.path.split('/').last,maxLines:2,overflow:TextOverflow.ellipsis)),
      IconButton(onPressed:()=>play(f),icon:const Icon(Icons.play_arrow,color:green)),
      IconButton(onPressed:()=>shareFile(f),icon:const Icon(Icons.share)),
      IconButton(onPressed:()async{setState(()=>library.remove(f));final prefs=await SharedPreferences.getInstance();await prefs.setStringList('ddm_naat_library',library.map((x)=>x.path).toList());},icon:const Icon(Icons.delete_outline,color:Colors.redAccent)),
    ]))),
  ]);
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
  Widget action(IconData icon,String label,VoidCallback fn)=>SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:fn,icon:Icon(icon),label:Text(label),style:FilledButton.styleFrom(backgroundColor:green,foregroundColor:Colors.black)));
  Widget outlined(IconData icon,String label,VoidCallback fn)=>SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:fn,icon:Icon(icon),label:Text(label,style:const TextStyle(fontSize:10))));
  Widget _pill(String s)=>Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:7),decoration:BoxDecoration(color:green.withOpacity(.16),borderRadius:BorderRadius.circular(20),border:Border.all(color:green.withOpacity(.5))),child:Text(s,style:const TextStyle(color:green,fontSize:9,fontWeight:FontWeight.bold)));
}