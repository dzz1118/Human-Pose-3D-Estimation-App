import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/api_service.dart';
import '../../widgets/calibration_overlay.dart';

enum CaptureView { front, side }

class CapturePage extends StatefulWidget {
  const CapturePage({super.key});

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isReady = false;
  bool _isRecording = false;
  bool _isUploading = false;
  CaptureView _selectedView = CaptureView.front;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      await _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      await _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isReady = true;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera initialization failed. Please check permissions.'),
        ),
      );
    }
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      if (_isRecording) {
        final file = await controller.stopVideoRecording();
        setState(() => _isRecording = false);
        await _handleCompletedVideo(file);
      } else {
        await controller.prepareForVideoRecording();
        await controller.startVideoRecording();
        setState(() => _isRecording = true);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recording failed. Please try again.')),
      );
    }
  }

  Future<void> _handleCompletedVideo(XFile file) async {
    final savedPath = await _saveToLocal(file);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upload Confirmation'),
        content: const Text(
          'Video saved locally. Upload to server for 3D gait analysis?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Upload Now'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Upload video and navigate to processing page with real job_id.
    setState(() => _isUploading = true);
    try {
      final jobId = await ApiService.uploadVideo(File(savedPath));
      if (!mounted) return;
      context.push('/processing', extra: {
        'jobId': jobId,
        'videoPath': savedPath,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<String> _saveToLocal(XFile file) async {
    final dir = await getApplicationDocumentsDirectory();
    final now = DateTime.now().millisecondsSinceEpoch;
    final targetPath = '${dir.path}/assessment_$now.mp4';
    await File(file.path).copy(targetPath);
    return targetPath;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assessment Capture')),
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<CaptureView>(
                  segments: const [
                    ButtonSegment<CaptureView>(
                      value: CaptureView.front,
                      label: Text('Front View'),
                      icon: Icon(Icons.front_hand_outlined),
                    ),
                    ButtonSegment<CaptureView>(
                      value: CaptureView.side,
                      label: Text('Side View'),
                      icon: Icon(Icons.view_sidebar_outlined),
                    ),
                  ],
                  selected: {_selectedView},
                  onSelectionChanged: (selection) {
                    setState(() => _selectedView = selection.first);
                  },
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      color: Colors.black,
                      child: _isReady && _controller != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                CameraPreview(_controller!),
                                const CalibrationOverlay(),
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  bottom: 12,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'Please align the patient inside the silhouette '
                                      'with shoulder/hip/ankle guides.',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: (_isReady && !_isUploading) ? _toggleRecording : null,
                  icon: Icon(
                    _isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                  ),
                  label: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? Colors.red : null,
                  ),
                ),
              ),
            ],
          ),
          // Upload overlay
          if (_isUploading)
            const ColoredBox(
              color: Color(0x88000000),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Uploading video…',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
