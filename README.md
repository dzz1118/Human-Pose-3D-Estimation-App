# NeuroMotion Capstone App

AI-powered gait analysis mobile application built for **North Shore Private Hospital**.
Flutter frontend + FastAPI backend — video upload → pose estimation → clinical metrics.

---

## Repository Structure

```
Capstone_app/
├── neuromotion/              # Flutter app (iOS / Android / Web)
│   ├── lib/
│   │   ├── features/         # capture · dashboard · processing · results pages
│   │   ├── models/           # ClinicalResult data model
│   │   ├── services/         # ApiService (HTTP calls to backend)
│   │   └── widgets/          # Shared UI components
│   └── pubspec.yaml
│
└── neuromotion-backend/      # Python FastAPI backend
    ├── main.py               # /health · /analyze endpoints
    ├── processor.py          # Video processing (stub → replace with WHAM)
    └── requirements.txt
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

### Backend — FastAPI

```bash
cd neuromotion-backend
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

API docs available at `http://localhost:8000/docs` once running.

---

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check |
| POST | `/analyze` | Upload video, receive gait metrics JSON |

---

## Notes

- **WHAM model inference** (`processor.py`) is currently a stub returning mock data.
  Real model weights and inference setup require separate configuration — contact the project lead.
- `uploads/` and `outputs/` directories are git-ignored; they are created automatically at runtime.
- No `.env` file is required for the stub backend. Add one when integrating real API keys or model paths.

---

## Team

Capstone project — feel free to open issues or PRs on this repo.
