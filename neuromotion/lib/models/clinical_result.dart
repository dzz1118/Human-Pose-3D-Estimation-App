class ClinicalResult {
  ClinicalResult({
    required this.leftKneeRom,
    required this.rightKneeRom,
    required this.gaitVelocity,
    required this.strideLength,
    required this.kneeCycleAngles,
  });

  final double leftKneeRom;
  final double rightKneeRom;
  final double gaitVelocity;
  final double strideLength;
  final List<double> kneeCycleAngles;

  factory ClinicalResult.fromJson(Map<String, dynamic> json) {
    return ClinicalResult(
      leftKneeRom: (json['leftKneeRom'] as num).toDouble(),
      rightKneeRom: (json['rightKneeRom'] as num).toDouble(),
      gaitVelocity: (json['gaitVelocity'] as num).toDouble(),
      strideLength: (json['strideLength'] as num).toDouble(),
      kneeCycleAngles: (json['kneeCycleAngles'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(),
    );
  }

  /// Parse from the WHAM backend `/results/{job_id}` response.
  factory ClinicalResult.fromWhamJson(Map<String, dynamic> json) {
    final subjects = json['subjects'] as List<dynamic>;
    if (subjects.isEmpty) {
      throw Exception('WHAM result contains no subjects.');
    }
    final m = (subjects[0] as Map<String, dynamic>)['clinical_metrics']
        as Map<String, dynamic>;
    return ClinicalResult(
      leftKneeRom: (m['left_knee_rom'] as num).toDouble(),
      rightKneeRom: (m['right_knee_rom'] as num).toDouble(),
      gaitVelocity: (m['gait_velocity'] as num).toDouble(),
      strideLength: (m['stride_length'] as num).toDouble(),
      kneeCycleAngles: (m['knee_cycle_angles'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(),
    );
  }

  static ClinicalResult mock() {
    return ClinicalResult.fromJson({
      'leftKneeRom': 76,
      'rightKneeRom': 74,
      'gaitVelocity': 1.12,
      'strideLength': 0.68,
      'kneeCycleAngles': [
        38,
        44,
        53,
        61,
        71,
        78,
        75,
        68,
        57,
        49,
        43,
        39,
      ],
    });
  }

  String buildSummary() {
    final avgRom = (leftKneeRom + rightKneeRom) / 2;
    final romDiff = (leftKneeRom - rightKneeRom).abs();

    final romStatus = avgRom >= 74 && avgRom <= 78
        ? 'knee ROM is within the near-normal range (74-78°)'
        : 'knee ROM is outside the ideal range';

    final symmetryStatus = romDiff <= 5
        ? 'left-right symmetry is good'
        : 'there is notable left-right asymmetry; targeted weak-side training is recommended';

    final speedStatus = gaitVelocity >= 1.0
        ? 'gait speed recovery is encouraging'
        : 'gait speed remains slow; continued gait-focused rehabilitation is recommended';

    return 'The patient shows that $romStatus, $symmetryStatus, and $speedStatus. Overall recovery progress is positive.';
  }
}
