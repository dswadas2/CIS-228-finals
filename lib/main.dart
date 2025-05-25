import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

void main() {
  runApp(const GestureMusicApp());
}

class GestureMusicApp extends StatefulWidget {
  const GestureMusicApp({super.key});

  @override
  GestureMusicAppState createState() => GestureMusicAppState();
}

class GestureMusicAppState extends State<GestureMusicApp> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<String> songNames = [];
  List<dynamic> songPaths = [];
  int currentSongIndex = -1;
  bool isPlaying = false;
  bool isLooping = false;
  bool isShuffling = false;
  double volume = 1.0;
  Duration duration = Duration.zero;
  Duration position = Duration.zero;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    _audioPlayer.durationStream.listen((d) {
      setState(() => duration = d ?? Duration.zero);
    });

    _audioPlayer.positionStream.listen((p) {
      setState(() => position = p);
    });

    // Auto-repeat logic
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && isLooping) {
        playSelectedSong(currentSongIndex); // Replay the current song
      } else if (state.processingState == ProcessingState.completed && isShuffling) {
        playRandomSong(); // Play a random song after completion
      }
    });
  }

  Future<void> pickFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
        withData: true, // Ensures files are accessible on Web
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          songNames = result.files.map((file) => file.name).toList();

          if (kIsWeb) {
            songPaths = result.files.map((file) => file.bytes).where((bytes) => bytes != null).toList();
          } else {
            songPaths = result.files.map((file) => file.path ?? "").where((path) => path.isNotEmpty).toList();
          }

          currentSongIndex = songPaths.isNotEmpty ? 0 : -1;
        });

        print("Songs loaded: ${songNames.length} tracks");

        if (songPaths.isNotEmpty) {
          playSelectedSong(currentSongIndex);
        }
      } else {
        print("No files selected.");
      }
    } catch (error) {
      print("File selection error: $error");
    }
  }

  Future<void> playSelectedSong(int index) async {
    try {
      if (songPaths.isEmpty || index < 0 || index >= songPaths.length) {
        print("Error: Invalid song index or no songs available.");
        return;
      }

      if (kIsWeb) {
        print("Playing audio on Web using just_audio_web.");
        final blobUrl = Uri.dataFromBytes(songPaths[index] as List<int>, mimeType: "audio/mp3").toString();
        await _audioPlayer.setUrl(blobUrl);
      } else {
        final file = File(songPaths[index]);
        if (!file.existsSync()) {
          print("Error: File does not exist!");
          return;
        }

        print("Loading: ${songNames[index]}");

        await _audioPlayer.setFilePath(file.path);
      }

      await _audioPlayer.setVolume(volume);
      await _audioPlayer.play();

      setState(() {
        currentSongIndex = index;
        isPlaying = true;
      });

      print("Playing: ${songNames[index]}");
    } catch (error) {
      print("Error playing file: $error");
    }
  }

  void playNextSong() {
    if (currentSongIndex < songPaths.length - 1) {
      playSelectedSong(currentSongIndex + 1);
    } else {
      print("No next song available.");
    }
  }

  void playPreviousSong() {
    if (currentSongIndex > 0) {
      playSelectedSong(currentSongIndex - 1);
    } else {
      print("No previous song available.");
    }
  }

  void playRandomSong() {
    if (songPaths.isNotEmpty) {
      int randomIndex = _random.nextInt(songPaths.length);
      playSelectedSong(randomIndex);
    }
  }

  void toggleShuffle() {
    setState(() {
      isShuffling = !isShuffling;
      print("Shuffle: $isShuffling");
    });
  }

  void toggleLoop() {
    setState(() {
      isLooping = !isLooping;
      print("Loop: $isLooping");
    });
  }

  void pauseAudio() async {
    await _audioPlayer.pause();
    setState(() => isPlaying = false);
  }

  void playAudio() async {
    if (currentSongIndex >= 0) {
      if (_audioPlayer.playerState.processingState == ProcessingState.ready) {
        await _audioPlayer.play();
        setState(() => isPlaying = true);
      }
    } else {
      print("No song selected.");
    }
  }

  void changeVolume(double newVolume) async {
    setState(() => volume = newVolume);
    await _audioPlayer.setVolume(newVolume);
  }

  void seekToPosition(double value) async {
    final newPosition = Duration(seconds: value.toInt());
    await _audioPlayer.seek(newPosition);
    setState(() => position = newPosition);

    print("Seeking to: ${position.toString().split('.').first}");
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.deepPurple,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Gesture Music Player", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.deepPurpleAccent,
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              ElevatedButton(
                onPressed: pickFiles,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                child: const Text("Select Music Files", style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 20),

              Expanded(
                child: ListView.builder(
                  itemCount: songNames.length,
                  itemBuilder: (context, index) {
                    return Card(
                      color: Colors.deepPurple[400],
                      child: ListTile(
                        title: Text(songNames[index], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                        onTap: () => playSelectedSong(index),
                        selected: index == currentSongIndex,
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(icon: const Icon(Icons.skip_previous, color: Colors.white), onPressed: playPreviousSong),
                  IconButton(icon: const Icon(Icons.play_arrow, color: Colors.white), onPressed: playAudio),
                  IconButton(icon: const Icon(Icons.pause, color: Colors.white), onPressed: pauseAudio),
                  IconButton(icon: const Icon(Icons.skip_next, color: Colors.white), onPressed: playNextSong),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
