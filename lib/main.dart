import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:async';

void main() {
  runApp(const GestureMusicApp());
}

class GestureMusicApp extends StatefulWidget {
  const GestureMusicApp({super.key});

  @override
  GestureMusicAppState createState() => GestureMusicAppState();
}

class GestureMusicAppState extends State<GestureMusicApp> {
  late AudioPlayer _audioPlayer;
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
  
  // Gesture detection variables
  StreamSubscription<UserAccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<AccelerometerEvent>? _regularAccelerometerSubscription;
  DateTime _lastGestureTime = DateTime.now();
  static const int gestureDelay = 500; // Reduced to 500ms for better responsiveness
  
  // Debug variables
  bool _debugMode = true;
  String _lastGestureDebug = "None";
  bool _sensorAvailable = false;
  String _sensorType = "None";

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    
    _initializeGestureDetection();
    _initializeAudioPlayer();
  }

  void _initializeGestureDetection() {
    // Cancel any existing subscriptions
    _accelerometerSubscription?.cancel();
    _regularAccelerometerSubscription?.cancel();
    
    // Try user accelerometer first
    _accelerometerSubscription = userAccelerometerEvents.listen(
      (UserAccelerometerEvent event) {
        if (!_sensorAvailable) {
          setState(() {
            _sensorAvailable = true;
            _sensorType = "User Accelerometer";
          });
        }
        _handleUserAccelerometerGesture(event);
      },
      onError: (error) {
        print("User Accelerometer error: $error");
        setState(() {
          _sensorType = "User Accelerometer Failed";
        });
        _accelerometerSubscription?.cancel();
        _tryRegularAccelerometer();
      },
      cancelOnError: true,
    );
    
    // Give user accelerometer a chance, then try regular accelerometer as fallback
    Future.delayed(Duration(seconds: 2), () {
      if (!_sensorAvailable) {
        _tryRegularAccelerometer();
      }
    });
  }
  
  void _tryRegularAccelerometer() {
    print("Trying regular accelerometer as fallback...");
    _regularAccelerometerSubscription = accelerometerEvents.listen(
      (AccelerometerEvent event) {
        if (!_sensorAvailable) {
          setState(() {
            _sensorAvailable = true;
            _sensorType = "Regular Accelerometer";
          });
        }
        _handleRegularAccelerometerGesture(event);
      },
      onError: (error) {
        print("Regular Accelerometer error: $error");
        setState(() {
          _sensorType = "No Accelerometer Available";
          _lastGestureDebug = "Sensor not available - try touch controls";
        });
      },
      cancelOnError: false,
    );
  }

  void _handleUserAccelerometerGesture(UserAccelerometerEvent event) {
    _handleGestureCommon(event.x, event.y, event.z);
  }
  
  void _handleRegularAccelerometerGesture(AccelerometerEvent event) {
    _handleGestureCommon(event.x, event.y, event.z);
  }
  
  void _handleGestureCommon(double x, double y, double z) {
    // Prevent rapid gesture triggers
    DateTime now = DateTime.now();
    if (now.difference(_lastGestureTime).inMilliseconds < gestureDelay) {
      return;
    }
    
    // Calculate total acceleration (magnitude)
    double totalAcceleration = sqrt(x * x + y * y + z * z);
    
    if (_debugMode) {
      print("Accelerometer: X=${x.toStringAsFixed(2)}, Y=${y.toStringAsFixed(2)}, Z=${z.toStringAsFixed(2)}, Total=${totalAcceleration.toStringAsFixed(2)}");
    }

    // Lower thresholds for better sensitivity
    // Detect shake gesture (strong acceleration in any direction)
    if (totalAcceleration > 12.0) { // Reduced from 15.0
      _lastGestureTime = now;
      setState(() {
        _lastGestureDebug = "Shake detected (${totalAcceleration.toStringAsFixed(2)})";
      });
      print("Strong shake detected - toggling play/pause");
      _togglePlayPause();
      return;
    }

    // Detect directional gestures with lower thresholds
    if (x.abs() > 4.0) { // Reduced from 6.0
      _lastGestureTime = now;
      if (x > 4.0) {
        setState(() {
          _lastGestureDebug = "Tilt right (${x.toStringAsFixed(2)})";
        });
        print("Phone tilted right - next song");
        playNextSong();
      } else {
        setState(() {
          _lastGestureDebug = "Tilt left (${x.toStringAsFixed(2)})";
        });
        print("Phone tilted left - previous song");
        playPreviousSong();
      }
    } else if (y.abs() > 4.0) { // Added Y-axis detection
      _lastGestureTime = now;
      if (y > 4.0) {
        setState(() {
          _lastGestureDebug = "Tilt forward (${y.toStringAsFixed(2)})";
        });
        print("Phone tilted forward - playing");
        playAudio();
      } else {
        setState(() {
          _lastGestureDebug = "Tilt backward (${y.toStringAsFixed(2)})";
        });
        print("Phone tilted backward - pausing");
        pauseAudio();
      }
    } else if (z.abs() > 4.0) { // Reduced from 8.0
      _lastGestureTime = now;
      if (z > 4.0) {
        setState(() {
          _lastGestureDebug = "Face up (${z.toStringAsFixed(2)})";
        });
        print("Phone face up - playing");
        playAudio();
      } else {
        setState(() {
          _lastGestureDebug = "Face down (${z.toStringAsFixed(2)})";
        });
        print("Phone face down - pausing");
        pauseAudio();
      }
    }
  }

  void _togglePlayPause() {
    if (isPlaying) {
      pauseAudio();
    } else {
      playAudio();
    }
  }

  void _initializeAudioPlayer() {
    _audioPlayer.durationStream.listen((d) {
      if (mounted) {
        setState(() => duration = d ?? Duration.zero);
      }
    });

    _audioPlayer.positionStream.listen((p) {
      if (mounted) {
        setState(() => position = p);
      }
    });

    // Auto-repeat logic
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (isLooping) {
          playSelectedSong(currentSongIndex);
        } else if (isShuffling) {
          playRandomSong();
        } else {
          // Auto-play next song if available
          if (currentSongIndex < songPaths.length - 1) {
            playNextSong();
          }
        }
      }
    });
  }

  Future<void> pickFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
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
          await playSelectedSong(0);
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

      print("Loading: ${songNames[index]}");

      if (kIsWeb) {
        final bytes = songPaths[index] as List<int>;
        final blobUrl = Uri.dataFromBytes(bytes, mimeType: "audio/mp3").toString();
        await _audioPlayer.setUrl(blobUrl);
      } else {
        final filePath = songPaths[index] as String;
        final file = File(filePath);
        if (!file.existsSync()) {
          print("Error: File does not exist at path: $filePath");
          return;
        }
        await _audioPlayer.setFilePath(filePath);
      }

      await _audioPlayer.setVolume(volume);
      await _audioPlayer.play();

      setState(() {
        currentSongIndex = index;
        isPlaying = true;
      });

      print("Now playing: ${songNames[index]}");
    } catch (error) {
      print("Error playing file: $error");
    }
  }

  void playNextSong() {
    if (songPaths.isEmpty) {
      print("No songs available.");
      return;
    }
    
    if (currentSongIndex < songPaths.length - 1) {
      playSelectedSong(currentSongIndex + 1);
      print("Playing next track...");
    } else {
      print("Already at last song.");
    }
  }

  void playPreviousSong() {
    if (songPaths.isEmpty) {
      print("No songs available.");
      return;
    }
    
    if (currentSongIndex > 0) {
      playSelectedSong(currentSongIndex - 1);
      print("Playing previous track...");
    } else {
      print("Already at first song.");
    }
  }

  void playRandomSong() {
    if (songPaths.isNotEmpty) {
      int randomIndex = _random.nextInt(songPaths.length);
      playSelectedSong(randomIndex);
      print("Playing random song...");
    }
  }

  void toggleShuffle() {
    setState(() {
      isShuffling = !isShuffling;
      if (isShuffling) isLooping = false; // Disable loop when shuffle is enabled
      print("Shuffle: $isShuffling");
    });
  }

  void toggleLoop() {
    setState(() {
      isLooping = !isLooping;
      if (isLooping) isShuffling = false; // Disable shuffle when loop is enabled
      print("Loop: $isLooping");
    });
  }

  void playAudio() async {
    if (currentSongIndex >= 0 && songPaths.isNotEmpty) {
      await _audioPlayer.play();
      setState(() => isPlaying = true);
      print("Playing audio...");
    } else {
      print("No song selected or available.");
    }
  }

  void pauseAudio() async {
    await _audioPlayer.pause();
    setState(() => isPlaying = false);
    print("Audio paused.");
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
    _accelerometerSubscription?.cancel();
    _regularAccelerometerSubscription?.cancel();
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
          title: const Text("Gesture Music Player", 
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.deepPurpleAccent,
          actions: [
            IconButton(
              icon: Icon(isShuffling ? Icons.shuffle_on : Icons.shuffle, 
                color: isShuffling ? Colors.orange : Colors.white),
              onPressed: toggleShuffle,
            ),
            IconButton(
              icon: Icon(isLooping ? Icons.repeat_one : Icons.repeat, 
                color: isLooping ? Colors.orange : Colors.white),
              onPressed: toggleLoop,
            ),
            IconButton(
              icon: Icon(_debugMode ? Icons.bug_report : Icons.bug_report_outlined,
                color: _debugMode ? Colors.green : Colors.white),
              onPressed: () {
                setState(() {
                  _debugMode = !_debugMode;
                });
              },
            ),
          ],
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

              // Debug info
              if (_debugMode)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text("Debug Mode", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text("Sensor: $_sensorType", style: TextStyle(fontSize: 14, color: Colors.white70)),
                      Text("Available: ${_sensorAvailable ? 'Yes' : 'No'}", style: TextStyle(fontSize: 14, color: _sensorAvailable ? Colors.green : Colors.red)),
                      Text("Last Gesture: $_lastGestureDebug", style: TextStyle(fontSize: 14, color: Colors.white70)),
                      Text("Check console for detailed accelerometer data", style: TextStyle(fontSize: 12, color: Colors.white60)),
                    ],
                  ),
                ),

              // Gesture instructions
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  children: [
                    Text("Gesture Controls:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text("• Shake strongly: Play/Pause", style: TextStyle(fontSize: 14, color: Colors.white70)),
                    Text("• Tilt left: Previous song", style: TextStyle(fontSize: 14, color: Colors.white70)),
                    Text("• Tilt right: Next song", style: TextStyle(fontSize: 14, color: Colors.white70)),
                    Text("• Tilt forward: Play", style: TextStyle(fontSize: 14, color: Colors.white70)),
                    Text("• Tilt backward: Pause", style: TextStyle(fontSize: 14, color: Colors.white70)),
                    Text("• Face up: Play", style: TextStyle(fontSize: 14, color: Colors.white70)),
                    Text("• Face down: Pause", style: TextStyle(fontSize: 14, color: Colors.white70)),
                  ],
                ),
              ),

              // Currently playing info
              if (currentSongIndex >= 0 && currentSongIndex < songNames.length)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 15),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text("Now Playing:", style: TextStyle(fontSize: 14, color: Colors.white70)),
                      Text(
                        songNames[currentSongIndex],
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

              const Text("Progress", style: TextStyle(fontSize: 18, color: Colors.white)),
              Slider(
                value: duration.inSeconds > 0 ? position.inSeconds.toDouble() : 0.0,
                min: 0.0,
                max: duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0,
                onChanged: seekToPosition,
                activeColor: Colors.deepPurpleAccent,
                inactiveColor: Colors.grey,
              ),

              Text(
                "${position.toString().split('.').first} / ${duration.toString().split('.').first}",
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),

              const SizedBox(height: 10),

              // Volume control
              Row(
                children: [
                  const Icon(Icons.volume_down, color: Colors.white),
                  Expanded(
                    child: Slider(
                      value: volume,
                      min: 0.0,
                      max: 1.0,
                      onChanged: changeVolume,
                      activeColor: Colors.deepPurpleAccent,
                      inactiveColor: Colors.grey,
                    ),
                  ),
                  const Icon(Icons.volume_up, color: Colors.white),
                ],
              ),

              Expanded(
                child: ListView.builder(
                  itemCount: songNames.length,
                  itemBuilder: (context, index) {
                    return Card(
                      color: index == currentSongIndex ? Colors.deepPurple[300] : Colors.deepPurple[400],
                      child: ListTile(
                        leading: index == currentSongIndex 
                          ? Icon(isPlaying ? Icons.play_arrow : Icons.pause, color: Colors.white)
                          : const Icon(Icons.music_note, color: Colors.white70),
                        title: Text(
                          songNames[index], 
                          style: TextStyle(
                            fontSize: 16, 
                            fontWeight: index == currentSongIndex ? FontWeight.bold : FontWeight.normal,
                            color: Colors.white
                          )
                        ),
                        onTap: () => playSelectedSong(index),
                        selected: index == currentSongIndex,
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous, color: Colors.white, size: 32), 
                    onPressed: playPreviousSong
                  ),
                  IconButton(
                    icon: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow, 
                      color: Colors.white, 
                      size: 40
                    ), 
                    onPressed: _togglePlayPause
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, color: Colors.white, size: 32), 
                    onPressed: playNextSong
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}