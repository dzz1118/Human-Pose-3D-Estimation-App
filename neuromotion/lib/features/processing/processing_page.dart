import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';

class ProcessingPage extends StatefulWidget {
  const ProcessingPage({super.key, required this.jobId, this.videoPath});

  final String jobId;
  final String? videoPath;

  @override
  State<ProcessingPage> createState() => _ProcessingPageState();
}

class _ProcessingPageState extends State<ProcessingPage> {
  static const _stages = [
    '2D Keypoint Extraction',
    '3D Pose Optimization',
    'Clinical Metric Computation',
  ];

  // Visual progress driven by elapsed time; navigation driven by backend status.
  static const _pollInterval = Duration(seconds: 3);
  static const _estimatedSeconds = 60.0; // rough estimate for progress bar

  Timer? _pollTimer;
  Timer? _progressTimer;

  double _progress = 0.0;
  String _backendStatus = 'queued';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startProgressAnimation();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _progressTimer?.cancel();
    super.dispose();
  }

  void _startProgressAnimation() {
    // Advance progress smoothly, but cap at 0.95 until backend confirms done.
    _progressTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted) return;
      setState(() {
        final cap = _backendStatus == 'done' ? 1.0 : 0.95;
        _progress = (_progress + (0.3 / _estimatedSeconds)).clamp(0.0, cap);
      });
    });
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
    // Also poll immediately.
    _poll();
  }

  Future<void> _poll() async {
    try {
      final status = await ApiService.getStatus(widget.jobId);
      final s = status['status'] as String? ?? 'queued';

      if (!mounted) return;
      setState(() => _backendStatus = s);

      if (s == 'done') {
        _pollTimer?.cancel();
        _progressTimer?.cancel();
        setState(() => _progress = 1.0);
        // Brief pause so the user sees 100 %.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        context.go('/results', extra: {
          'jobId': widget.jobId,
          'videoPath': widget.videoPath,
        });
      } else if (s == 'failed') {
        _pollTimer?.cancel();
        _progressTimer?.cancel();
        setState(() {
          _errorMessage = status['error'] as String? ?? 'Unknown error.';
        });
      }
    } catch (e) {
      // Network hiccup — will retry on next tick.
    }
  }

  int get _stageIndex {
    if (_progress < 0.35) return 0;
    if (_progress < 0.75) return 1;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Processing Failed')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Back to Dashboard'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Processing Video')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            const Center(
              child: SizedBox(
                height: 78,
                width: 78,
                child: CircularProgressIndicator(strokeWidth: 6),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'AI is analyzing 3D gait metrics…',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 24),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 12),
            Text(
              'Current Stage: ${_stages[_stageIndex]}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 14),
            ..._stages.asMap().entries.map(
                  (entry) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      entry.key < _stageIndex
                          ? Icons.check_circle
                          : entry.key == _stageIndex
                              ? Icons.autorenew
                              : Icons.radio_button_unchecked,
                      color: entry.key <= _stageIndex
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
                    title: Text(entry.value),
                  ),
                ),
            const SizedBox(height: 8),
            Text(
              'Job ID: ${widget.jobId}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            const Spacer(),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'This system uses high-precision 3D modeling and temporal '
                  'optimization to replace traditional visual-only gait assessment '
                  'with objective, quantifiable clinical metrics.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
