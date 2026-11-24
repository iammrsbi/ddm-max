import 'dart:io';
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
  double level=80,feedback=38,delayTime=320,mix=45;
  final List<double> eq=[0,0,0,0,0];
  bool bypass=false,pingPong=false,dual=false,loop=false,recording=false,working=false,liveMonitoring=false;
  static const MethodChannel liveChannel=MethodChannel('ddm.max/live_audio');
  final AudioPlayer player=AudioPlayer();
  final AudioRecorder recorder=AudioRecorder();
  File? selected,processed,recorded;
  final List<File> library=[];
  String? recordingPath;

  @override void dispose(){liveChannel.invokeMethod('stop');player.dispose();recorder.dispose();super.dispose();}

  void note(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  Future<void> chooseAudio({bool forLibrary=false}) async {
    try {
      final r=await FilePicker.platform.pickFiles(type:FileType.audio);
      if(r==null||r.files.single.path==null)return;
      final f=File(r.files.single.path!);
      setState((){if(forLibrary){if(!library.any((x)=>x.path==f.path))library.add(f);}else{selected=f;processed=null;}});
      note('Audio file select ho gayi.');
    }catch(e){note('File select error: $e');}
  }
  Future<void> play(File? f) async {
    if(f==null){note('Pehle audio file select karo.');return;}
    try{await player.stop();await player.setReleaseMode(loop?ReleaseMode.loop:ReleaseMode.release);await player.play(DeviceFileSource(f.path));}
    catch(e){note('Play error: $e');}
  }
  Future<void> stop() async {await player.stop();}
  Future<void> process(File? source) async {
    if(source==null){note('Pehle audio file select ya record karo.');return;}
    setState(()=>working=true);
    try{
      final d=await getApplicationDocumentsDirectory();
      final out=await WavEchoEngine.render(input:source,outputDirectory:Directory('${d.path}/DDM-MAX'),
        delayMs:delayTime.round(),feedback:feedback/100,mix:mix/100,level:level/100,
        eq:eq,pingPong:pingPong,dual:dual,bypass:bypass);
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
      await liveChannel.invokeMethod('start', {'delayMs':delayTime.round(),'feedback':feedback/100,'mix':mix/100,'level':level/100});
      if(mounted)setState(()=>liveMonitoring=true);
      note('Live mic delay chalu. Headphones use karo.');
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
  @override Widget build(BuildContext context){
    final pages=[delayPage(),filePage(),eqPage(),recordPage(),libraryPage(),settingsPage()];
    return Scaffold(
      body:Stack(fit:StackFit.expand,children:[
        Image.asset('assets/combo_bg.jpg',fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(color:const Color(0xFF07110E))),
        Container(color:const Color(0xE607100D)),
        SafeArea(child:Column(children:[header(),Expanded(child:pages[tab])])),
      ]),
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),
        backgroundColor:const Color(0xFF0B1713),indicatorColor:green.withOpacity(.22),
        destinations:const[
          NavigationDestination(icon:Icon(Icons.graphic_eq),label:'Delay'),
          NavigationDestination(icon:Icon(Icons.audio_file),label:'File Echo'),
          NavigationDestination(icon:Icon(Icons.tune),label:'EQ'),
          NavigationDestination(icon:Icon(Icons.mic),label:'Record'),
          NavigationDestination(icon:Icon(Icons.library_music),label:'Naat'),
          NavigationDestination(icon:Icon(Icons.settings),label:'Settings'),
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
    title('DIGITAL DELAY','Controls are applied when processing an audio file or recording.'),
    box(Column(children:[
      Row(children:[Expanded(child:mode('SINGLE DELAY',!dual,()=>setState(()=>dual=false))),const SizedBox(width:8),Expanded(child:mode('DUAL DELAY',dual,()=>setState(()=>dual=true)))]),
      Row(children:[Expanded(child:sw('PING-PONG',pingPong,(v)=>setState(()=>pingPong=v))),Expanded(child:sw('BYPASS',bypass,(v)=>setState(()=>bypass=v)))]),
      slider('LEVEL',level,0,100,'${level.round()}%',(v)=>setState(()=>level=v)),
      slider('FEEDBACK',feedback,0,92,'${feedback.round()}%',(v)=>setState(()=>feedback=v)),
      slider('TIME',delayTime,40,1200,'${delayTime.round()} ms',(v)=>setState(()=>delayTime=v)),
      slider('EFFECT MIX',mix,0,100,'${mix.round()}%',(v)=>setState(()=>mix=v)),
    ])),
    box(Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Text('PROCESS SOURCE AUDIO',style:TextStyle(color:gold,fontWeight:FontWeight.bold)),
      const SizedBox(height:8),Text(selected?.path.split('/').last??'No source selected',style:const TextStyle(color:Colors.white70)),
      FilledButton.icon(onPressed:()=>setState(()=>tab=1),icon:const Icon(Icons.audio_file),label:const Text('OPEN FILE ECHO')),
      OutlinedButton.icon(onPressed:()=>setState(()=>tab=3),icon:const Icon(Icons.mic),label:const Text('OPEN LIVE MIC / RECORD')),
    ])),
  ]);
  Widget filePage()=>scroll([
    title('FILE ECHO','Select audio, process effects and save/share WAV output.'),
    box(Column(children:[
      const Icon(Icons.audio_file,size:48,color:gold),const SizedBox(height:8),
      Text(selected?.path.split('/').last??'NO AUDIO SELECTED',textAlign:TextAlign.center),
      const SizedBox(height:8),action(Icons.folder_open,'CHOOSE AUDIO FILE',()=>chooseAudio()),
      const SizedBox(height:8),sw('REPEAT / LOOP PLAYBACK',loop,(v)=>setState(()=>loop=v)),
      Row(children:[Expanded(child:outlined(Icons.play_arrow,'PLAY ORIGINAL',()=>play(selected))),const SizedBox(width:8),Expanded(child:outlined(Icons.stop,'STOP',stop))]),
    ])),
    box(Column(children:[
      slider('DELAY TIME',delayTime,40,1200,'${delayTime.round()} ms',(v)=>setState(()=>delayTime=v)),
      slider('FEEDBACK',feedback,0,92,'${feedback.round()}%',(v)=>setState(()=>feedback=v)),
      slider('EFFECT MIX',mix,0,100,'${mix.round()}%',(v)=>setState(()=>mix=v)),
      slider('OUTPUT LEVEL',level,0,100,'${level.round()}%',(v)=>setState(()=>level=v)),
      FilledButton.icon(onPressed:working?null:()=>process(selected),icon:working?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.auto_awesome),label:Text(working?'PROCESSING...':'PROCESS & SAVE ECHO')),
      const SizedBox(height:7),outlined(Icons.play_circle,'PLAY PROCESSED',()=>play(processed)),
      outlined(Icons.share,'SHARE / EXPORT WAV',()=>shareFile(processed)),
      if(processed!=null)Text('Saved: ${processed!.path}',style:const TextStyle(color:green,fontSize:10)),
    ])),
    const Text('Supported input: PCM 16-bit mono/stereo WAV. Other formats can be selected but may need WAV conversion.',style:TextStyle(color:Colors.white54,fontSize:10)),
  ]);
  Widget eqPage()=>scroll([
    title('5-BAND EQUALIZER','EQ is applied to the next processed audio output.'),
    box(Column(children:[
      Row(children:[Expanded(child:mode('FLAT',eq.every((v)=>v==0),()=>setState(()=>eq.fillRange(0,5,0)))),const SizedBox(width:7),Expanded(child:mode('NAAT VOICE',false,()=>setState((){eq[0]=1;eq[1]=1;eq[2]=3;eq[3]=4;eq[4]=2;})))]),
      slider('BASS • 100 Hz',eq[0],-12,12,'${eq[0].round()} dB',(v)=>setState(()=>eq[0]=v)),
      slider('LOW MID • 350 Hz',eq[1],-12,12,'${eq[1].round()} dB',(v)=>setState(()=>eq[1]=v)),
      slider('MID • 1 kHz',eq[2],-12,12,'${eq[2].round()} dB',(v)=>setState(()=>eq[2]=v)),
      slider('HIGH MID • 3.5 kHz',eq[3],-12,12,'${eq[3].round()} dB',(v)=>setState(()=>eq[3]=v)),
      slider('TREBLE • 9 kHz',eq[4],-12,12,'${eq[4].round()} dB',(v)=>setState(()=>eq[4]=v)),
      Row(children:[Expanded(child:mode('BASS BOOST',false,()=>setState((){eq[0]=8;eq[1]=3;}))),const SizedBox(width:8),Expanded(child:mode('CLEAR VOCAL',false,()=>setState((){eq[2]=3;eq[3]=6;eq[4]=3;})))]),
      const SizedBox(height:8),const Text('EQ values are used by PROCESS & SAVE ECHO on the File Echo or Record tab.',style:TextStyle(color:Colors.white60,fontSize:10)),
    ])),
    FilledButton.icon(onPressed:()=>setState(()=>tab=1),icon:const Icon(Icons.audio_file),label:const Text('GO TO FILE ECHO')),
  ]);
  Widget recordPage()=>scroll([
    title('LIVE MIC & RECORDING','Record from phone microphone, then process with delay and EQ.'),
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
    const Text('Mic capture and recording are implemented. This version records first and applies effects after recording; realtime zero-latency live echo monitoring is not yet available.',style:TextStyle(color:Colors.white54,fontSize:10)),
  ]);
  Widget libraryPage()=>scroll([
    title('NAAT COLLECTION','Add audio tracks from your phone and play them here.'),
    box(Column(children:[
      const Icon(Icons.library_music,size:48,color:gold),const Text('MY NAAT COLLECTION',style:TextStyle(fontWeight:FontWeight.bold)),
      const SizedBox(height:8),action(Icons.add,'ADD NAAT AUDIO',()=>chooseAudio(forLibrary:true)),
    ])),
    if(library.isEmpty)box(const Text('Abhi collection khaali hai. ADD NAAT AUDIO se apni files add karo.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white60))),
    ...library.map((f)=>box(Row(children:[
      const Icon(Icons.music_note,color:gold),const SizedBox(width:8),Expanded(child:Text(f.path.split('/').last,maxLines:2,overflow:TextOverflow.ellipsis)),
      IconButton(onPressed:()=>play(f),icon:const Icon(Icons.play_arrow,color:green)),
      IconButton(onPressed:()=>shareFile(f),icon:const Icon(Icons.share)),
    ]))),
  ]);
  Widget settingsPage()=>scroll([
    title('SETTINGS','DDM-MAX app options'),
    box(const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('APP VERSION 1.0',style:TextStyle(color:gold,fontWeight:FontWeight.bold)),
      SizedBox(height:8),Text('Audio processing: WAV file engine'),
      Text('Microphone: Android record permission'),
      Text('Developer: IDRISH'),
      SizedBox(height:8),Text('For best results, use WAV audio at 44.1 kHz.',style:TextStyle(color:Colors.white60,fontSize:11)),
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