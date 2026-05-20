# NeuroMotion

AI-powered clinical gait analysis application built for **North Shore Private Hospital**.
UTS Capstone Project — Flutter mobile app + FastAPI backend powered by [WHAM](https://github.com/yohanshin/WHAM) monocular 3D pose estimation.

---

## Overview

NeuroMotion lets clinicians record a patient walking on video and receive quantitative gait metrics:

- **3D pose estimation** via WHAM (monocular video → SMPL body mesh, 25 joints)
- **Clinical metrics**: gait velocity, knee ROM (left & right), stride length, per-frame knee flexion angles
- **Asynchronous pipeline**: upload video → receive `job_id` → poll status → fetch results

---

## Repository Structure

```
Capstone_app/
├── neuromotion/              # Flutter app (iOS · Android · Web · Desktop)
│   └── lib/
│       ├── features/         # capture · dashboard · processing · results pages
│       ├── models/           # ClinicalResult data model
│       ├── services/         # ApiService — HTTP calls to wham-backend
│       └── widgets/          # Shared UI components
│
└── wham-backend/             # FastAPI backend — real WHAM inference (runs in WSL2 / Linux)
    ├── main.py               # All API endpoints
    └── README.md             # Startup Guide: WSL2 setup, GPU, checkpoints, networking
```

---

## Getting Started

### Frontend — Flutter

```bash
cd neuromotion
flutter pub get
flutter run
```

Targets: Android, iOS, Web, Windows, macOS, Linux (Flutter 3.x / Dart ≥ 3.3).

The backend URL is configured in `neuromotion/lib/services/api_service.dart`:

```dart
static const String baseUrl = 'http://localhost:8000';
```

### Backend — WHAM FastAPI

The backend requires a Linux environment (WSL2 on Windows is supported) with a CUDA-capable GPU and the WHAM model weights.

See **[wham-backend/README.md](wham-backend/README.md)** for the full setup guide — conda environment, checkpoint installation, WSL2 networking, and startup commands.

Quick start (inside WSL2):

```bash
cd <your-wham-path>
conda activate wham
pip install -r backend/requirements.txt
uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
```

API docs available at `http://localhost:8000/docs` once the backend is running.

> On first startup WHAM loads model weights (~1–2 minutes). Wait until `/health` returns `"model_ready": true` before sending requests.

---

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Liveness probe — returns GPU status and `model_ready` flag |
| POST | `/process_video` | Upload an MP4; queues a WHAM job, returns `job_id` immediately |
| GET | `/status/{job_id}` | Poll job status (`queued` → `processing` → `done` / `failed`) |
| GET | `/results/{job_id}` | Fetch full JSON results (only when `status == done`) |
| GET | `/files/{job_id}/output.mp4` | Rendered overlay video |
| GET | `/docs` | Swagger UI |

### Async flow

```
POST /process_video  →  { "job_id": "..." }
        ↓  poll every ~3 s
GET  /status/{job_id}  →  { "status": "done", "video_url": "/files/..." }
        ↓
GET  /results/{job_id}  →  full JSON result
```

---

## Result JSON Structure

`GET /results/{job_id}` returns:

```json
{
  "meta": {
    "job_id": "...",
    "num_subjects": 1,
    "created_at": "2025-01-01T00:00:00Z",
    "coord_convention": "joints3d_cam in WHAM camera space (Y-up). trans_world in global world space."
  },
  "subjects": [
    {
      "id": 0,
      "num_frames": 120,
      "frame_ids": [...],
      "betas": [...],
      "poses_root_cam": [...],
      "poses_body": [...],
      "trans_world": [...],
      "joints3d_cam": [...],
      "joint_names": ["pelvis", "left_hip", "right_hip", "..."],
      "clinical_metrics": {
        "gait_velocity": 1.23,
        "left_knee_rom": 58.4,
        "right_knee_rom": 55.1,
        "stride_length": 1.42,
        "knee_cycle_angles": [12.0, 24.5, 38.1, "..."]
      }
    }
  ]
}
```

### `clinical_metrics` fields

| Field | Unit | Description |
|-------|------|-------------|
| `gait_velocity` | m/s | Horizontal root displacement ÷ clip duration |
| `left_knee_rom` | deg | Left knee flexion range (max − min) over the clip |
| `right_knee_rom` | deg | Right knee flexion range (max − min) over the clip |
| `stride_length` | m | Estimated from left foot vertical oscillation cycles |
| `knee_cycle_angles` | deg | Left knee flexion at 12 equidistant points across the gait cycle (0–100 %) |

---

## Team

UTS Capstone — NeuroMotion team.
Built for North Shore Private Hospital clinical gait analysis.
