import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(const DD8MaxApp());
}

class DD8MaxApp extends StatelessWidget {
  const DD8MaxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DD-8 MAX',
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const HomeScreen(),
    );
  }
}

class Naat {
  final String title;
  final String artist;
  final String file;
  Naat({required this.title, required this.artist, required this.file});
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AudioPlayer _player = AudioPlayer();
  int? _playingIndex;
  bool _isPlaying = false;

  final List<Naat> naats = [
    Naat(title: 'Mera Dil Badal De', artist: 'Shayar-e-Rasool', file: 'audio/naat1.mp3'),
    Naat(title: 'Ya Nabi Salam Alaika', artist: 'Shayar-e-Rasool', file: 'audio/naat2.mp3'),
    Naat(title: 'Madina Madina', artist: 'Shayar-e-Rasool', file: 'audio/naat3.mp3'),
    Naat(title: 'Sarkar Ka Dar', artist: 'Shayar-e-Rasool', file: 'audio/naat4.mp3'),
    Naat(title: 'Noor Wala Aaya Hai', artist: 'Shayar-e-Rasool', file: 'audio/naat5.mp3'),
  ];

  Future<void> _playPause(int index) async {
    if (_playingIndex == index && _isPlaying) {
      await _player.pause();
      setState(() => _isPlaying = false);
    } else {
      await _player.stop();
      await _player.play(AssetSource(naats[index].file));
      setState(() {
        _playingIndex = index;
        _isPlaying = true;
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/combo_bg.jpg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Container(color: Colors.black.withOpacity(0.55)),
          // Content
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const CircleAvatar(
                  radius: 55,
                  backgroundImage: AssetImage('assets/combo_bg.jpg'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'DD-8 MAX',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const Text(
                  'Shayar-e-Rasool Naat Collection',
                  style: TextStyle(color: Colors.amber, fontSize: 14),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.builder(
                    itemCount: naats.length,
                    itemBuilder: (context, index) {
                      final naat = naats[index];
                      final isThisPlaying = _playingIndex == index && _isPlaying;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isThisPlaying ? Colors.green : Colors.amber,
                            child: Icon(
                              isThisPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            naat.title,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            naat.artist,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.share, color: Colors.white70),
                            onPressed: () {},
                          ),
                          onTap: () => _playPause(index),
                        ),
                      );
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Made with ❤️ for Aashiq-e-Rasool',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
