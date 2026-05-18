import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class InstantCameraScreen extends StatefulWidget {
  const InstantCameraScreen({super.key});

  @override
  State<InstantCameraScreen> createState() => _InstantCameraScreenState();
}

class _InstantCameraScreenState extends State<InstantCameraScreen> with SingleTickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isCameraInitialized = false;
  bool _isRecording = false;

  File? _capturedFile;
  bool _isVideo = false;
  VideoPlayerController? _videoController;

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (_isRecording) {
          _stopVideoRecording();
        }
      }
    });

    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        // Prefer back camera initially
        _selectedCameraIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
        if (_selectedCameraIndex == -1) _selectedCameraIndex = 0;
        await _setupCameraController(_cameras[_selectedCameraIndex]);
      }
    } catch (e) {
      debugPrint("Error initializing camera: $e");
    }
  }

  Future<void> _setupCameraController(CameraDescription cameraDesc) async {
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
      await Future.delayed(const Duration(milliseconds: 300));
    }

    final newController = CameraController(
      cameraDesc,
      ResolutionPreset.high,
      enableAudio: true,
    );

    try {
      await newController.initialize();
      if (mounted) {
        setState(() {
          _controller = newController;
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("Error setting up camera controller: $e");
    }
  }

  Future<void> _toggleCamera() async {
    if (_cameras.length < 2 || _isRecording) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    setState(() => _isCameraInitialized = false);
    await _setupCameraController(_cameras[_selectedCameraIndex]);
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isRecording) return;
    try {
      final XFile file = await _controller!.takePicture();
      setState(() {
        _capturedFile = File(file.path);
        _isVideo = false;
      });
    } catch (e) {
      debugPrint("Error taking picture: $e");
    }
  }

  Future<void> _startVideoRecording() async {
    if (_controller == null || !_controller!.value.isInitialized || _isRecording) return;
    try {
      await _controller!.startVideoRecording();
      setState(() => _isRecording = true);
      _animationController.reset();
      _animationController.forward();
    } catch (e) {
      debugPrint("Error starting video recording: $e");
    }
  }

  Future<void> _stopVideoRecording() async {
    if (_controller == null || !_controller!.value.isRecordingVideo || !_isRecording) return;
    try {
      _animationController.stop();
      final XFile file = await _controller!.stopVideoRecording();
      final videoFile = File(file.path);
      
      _videoController = VideoPlayerController.file(videoFile)
        ..initialize().then((_) {
          _videoController!.setLooping(true);
          _videoController!.play();
          setState(() {
            _capturedFile = videoFile;
            _isVideo = true;
            _isRecording = false;
          });
        });
    } catch (e) {
      debugPrint("Error stopping video recording: $e");
      setState(() => _isRecording = false);
    }
  }

  void _retake() {
    _videoController?.dispose();
    _videoController = null;
    setState(() {
      _capturedFile = null;
      _isVideo = false;
    });
  }

  void _confirm() {
    if (_capturedFile == null) return;
    Navigator.pop(context, {
      'file': _capturedFile,
      'isVideo': _isVideo,
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _controller?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_capturedFile != null) {
      return _buildPreviewScreen();
    }
    return _buildCameraScreen();
  }

  Widget _buildCameraScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_isCameraInitialized && _controller != null && _controller!.value.previewSize != null)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.previewSize!.height,
                  height: _controller!.value.previewSize!.width,
                  child: CameraPreview(_controller!),
                ),
              ),
            )
          else
            Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor)),

          // Top actions
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                    if (_cameras.length > 1)
                      IconButton(
                        icon: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 28),
                        onPressed: _toggleCamera,
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom shutter button
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32.0),
                child: GestureDetector(
                  onTap: _takePicture,
                  onLongPressStart: (_) => _startVideoRecording(),
                  onLongPressEnd: (_) => _stopVideoRecording(),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Progress ring for video
                      SizedBox(
                        width: 90,
                        height: 90,
                        child: AnimatedBuilder(
                          animation: _animationController,
                          builder: (context, child) => CircularProgressIndicator(
                            value: _isRecording ? _animationController.value : 0.0,
                            strokeWidth: 6,
                            valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                            backgroundColor: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                      // Shutter button inside
                      Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isRecording ? Colors.red : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Instruction overlay
          if (!_isRecording && _capturedFile == null)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 135.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      "Tap for photo, hold for video",
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreviewScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SizedBox.expand(
            child: _isVideo && _videoController != null
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _videoController!.value.size.width,
                      height: _videoController!.value.size.height,
                      child: VideoPlayer(_videoController!),
                    ),
                  )
                : Image.file(_capturedFile!, fit: BoxFit.cover),
          ),

          // Top actions
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),

          // Bottom confirm / retake buttons
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 32.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      icon: const Icon(Icons.refresh, size: 22),
                      label: const Text("Retake", style: TextStyle(fontSize: 16)),
                      onPressed: _retake,
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      icon: const Icon(Icons.send, size: 22),
                      label: const Text("Send", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      onPressed: _confirm,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
