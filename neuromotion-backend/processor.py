import json
import time
from pathlib import Path
from typing import Any


def process_video(job_id: str, input_path: Path, output_dir: Path) -> dict[str, Any]:
    """Simulates WHAM-based gait analysis and writes output JSON.

    Replace this function with actual model inference + post-processing.
    """
    # Simulate cloud/model processing latency
    time.sleep(2)

    result = {
        'jobId': job_id,
        'inputVideo': str(input_path),
        'processedVideo': str(output_dir / f'{job_id}_overlay.mp4'),
        'metrics': {
            'gaitVelocity': 0.608,
            'leftKneeRom': 74.6,
            'leftStrideLength': 0.749,
        },
        'kneeCycleAngles': [42.0, 47.2, 54.5, 62.8, 70.1, 74.6, 72.9, 68.4, 60.7, 53.3, 47.8, 44.0],
        'summary': (
            'Gait velocity is 0.608 m/s, left knee ROM is 74.6 deg, '
            'and left stride length is 0.749 m.'
        ),
        'stages': ['2D Keypoint Extraction', '3D Pose Optimization', 'Clinical Metric Computation'],
    }

    output_json_path = output_dir / f'{job_id}.json'
    output_json_path.write_text(json.dumps(result, ensure_ascii=True, indent=2), encoding='utf-8')
    return result
