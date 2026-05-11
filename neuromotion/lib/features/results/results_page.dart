import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/clinical_result.dart';
import '../../services/api_service.dart';
import '../../widgets/metric_card.dart';

class ResultsPage extends StatefulWidget {
  const ResultsPage({super.key, required this.jobId, this.videoPath});

  final String jobId;
  final String? videoPath;

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  ClinicalResult? _result;
  VideoPlayerController? _videoController;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initVideo();
    _fetchResults();
  }

  Future<void> _initVideo() async {
    final path = widget.videoPath;
    if (path == null || !File(path).existsSync()) return;
    final controller = VideoPlayerController.file(File(path));
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _videoController = controller);
  }

  Future<void> _fetchResults() async {
    if (widget.jobId.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'No job ID provided.';
      });
      return;
    }
    try {
      final result = await ApiService.getResults(widget.jobId);
      if (!mounted) return;
      setState(() {
        _result = result;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clinical Assessment Results')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading results…'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Padding(
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
          ],
        ),
      );
    }

    final result = _result!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildVideoPanel(context),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: MetricCard(
                title: 'Gait Velocity',
                value: result.gaitVelocity.toStringAsFixed(3),
                unit: 'm/s',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricCard(
                title: 'Left Knee ROM',
                value: result.leftKneeRom.toStringAsFixed(1),
                unit: '°',
                accent: const Color(0xFF3366CC),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: MetricCard(
                title: 'Right Knee ROM',
                value: result.rightKneeRom.toStringAsFixed(1),
                unit: '°',
                accent: const Color(0xFF3366CC),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricCard(
                title: 'Left Stride Length',
                value: result.strideLength.toStringAsFixed(3),
                unit: 'm',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Knee Flexion — Gait Cycle',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                SizedBox(height: 220, child: _buildKneeChart(result)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assessment Summary',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  result.buildSummary(),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Job ID: ${widget.jobId}',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildVideoPanel(BuildContext context) {
    final controller = _videoController;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Processed Video Playback (3D Skeleton Overlay)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.black,
                  child: controller != null && controller.value.isInitialized
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            VideoPlayer(controller),
                            Positioned(
                              bottom: 10,
                              child: FilledButton.tonalIcon(
                                onPressed: () {
                                  controller.value.isPlaying
                                      ? controller.pause()
                                      : controller.play();
                                  setState(() {});
                                },
                                icon: Icon(
                                  controller.value.isPlaying
                                      ? Icons.pause_circle
                                      : Icons.play_circle,
                                ),
                                label: Text(
                                  controller.value.isPlaying ? 'Pause' : 'Play',
                                ),
                              ),
                            ),
                          ],
                        )
                      : const Center(
                          child: Text(
                            'No processed video available.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKneeChart(ClinicalResult result) {
    final spots = result.kneeCycleAngles
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        gridData: const FlGridData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFF4A90E2),
            barWidth: 3,
            dotData: const FlDotData(show: false),
          ),
        ],
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            axisNameWidget: const Text('°'),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (v, _) => Text(v.toInt().toString()),
            ),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: const Text('Gait Cycle %'),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) {
                if (v % 2 != 0) return const SizedBox.shrink();
                final pct = (v / 11 * 100).round();
                return Text('$pct%');
              },
            ),
          ),
        ),
      ),
    );
  }
}
