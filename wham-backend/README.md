# NeuroMotion Backend — Startup Guide

## Environment Overview

| Component | Location |
|---|---|
| Backend (FastAPI + WHAM) | WSL2 — Ubuntu 24.04 |
| Frontend (Flutter app) | Windows host `E:\Capstone_app\neuromotion` |
| Backend listening address | `0.0.0.0:8000` |
| Frontend Base URL for backend | `http://localhost:8000` |

---

## WSL2 Networking

### Current Mode: NAT (default)

WSL2 uses NAT networking by default. Windows 11 has a built-in automatic loopback proxy,
so **browsers and frontends on the Windows side can access WSL2 services directly via `localhost:8000`**
without any port-forwarding configuration.

> **Requirement**: uvicorn must bind to `0.0.0.0`, not `127.0.0.1`.
> Binding to `127.0.0.1` only listens on the WSL internal loopback — Windows cannot reach it.

### Optional Upgrade: Mirrored Networking Mode (recommended)

Your environment (WSL 2.6.3 + Windows 11 26200) fully supports Mirrored mode.
Once enabled, WSL2 and Windows share the same network stack, behaving more like native Linux —
no relay proxy dependency, and no access failures caused by WSL IP changes.

**How to enable** (run in Windows PowerShell):

```powershell
# Create or append to %USERPROFILE%\.wslconfig
Add-Content "$env:USERPROFILE\.wslconfig" "`n[wsl2]`nnetworkingMode=mirrored"

# Restart WSL for the config to take effect
wsl --shutdown
```

After enabling, the frontend Base URL remains unchanged: `http://localhost:8000`.

---

## Installing Dependencies

```bash
# Run in WSL terminal
cd <your-wham-path>

# Activate your conda/venv environment (existing WHAM environment)
conda activate wham   # or: source venv/bin/activate

# Install additional backend dependencies
pip install -r backend/requirements.txt
```

---

## Starting the Backend

```bash
cd <your-wham-path>

uvicorn backend.main:app \
    --host 0.0.0.0 \
    --port 8000 \
    --reload
```

| Flag | Description |
|---|---|
| `--host 0.0.0.0` | Listen on all interfaces so the Windows side can connect |
| `--port 8000` | Fixed port matching the frontend Base URL |
| `--reload` | Dev mode — auto-restarts on code changes; remove for production |

> **Note**: On first startup, WHAM loads model weights (~1–2 minutes).
> During this time `/health` will return `"model_ready": false` — wait until it becomes `true` before sending requests.

### Verifying the Service

In a Windows browser or PowerShell:

```powershell
# Open directly in browser
http://localhost:8000/health

# Or in PowerShell
Invoke-RestMethod http://localhost:8000/health
```

Expected response:

```json
{
  "status": "ok",
  "model_ready": true,
  "device": "cuda",
  "gpu": { "name": "...", "memory_total": "... GB", "memory_used": "... GB" }
}
```

---

## Frontend Configuration

The frontend is a **Flutter app** located at `E:\Capstone_app\neuromotion`.

The backend base URL is configured in one place:

```
neuromotion/lib/services/api_service.dart
```

```dart
static const String baseUrl = 'http://localhost:8000';
```

Change this constant if the backend runs on a different host or port.
The Flutter `ApiService` calls `/process_video`, `/status/{job_id}`, and `/results/{job_id}` using the async polling flow described in the API Quick Reference below.

---

## API Quick Reference

| Method | Path | Description |
|---|---|---|
| GET | `/health` | Liveness probe + GPU status |
| POST | `/process_video` | Upload an MP4, returns `job_id` |
| GET | `/status/{job_id}` | Poll job status |
| GET | `/results/{job_id}` | Get full JSON results (only when done) |
| GET | `/files/{job_id}/output.mp4` | Rendered output video (static file) |
| GET | `/docs` | Auto-generated Swagger docs |

---

## Troubleshooting

**`localhost:8000` times out from Windows**

1. Confirm uvicorn is bound to `0.0.0.0`, not `127.0.0.1`
2. Check whether Windows Firewall is blocking port 8000:
   ```powershell
   netsh advfirewall firewall add rule name="WSL2 Backend 8000" `
       dir=in action=allow protocol=TCP localport=8000
   ```
3. If the issue persists, use the WSL2 actual IP (changes on every restart):
   ```bash
   # Query the current IP from within WSL
   ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d/ -f1
   ```

**CUDA Out of Memory**

The backend returns a specific error message with current GPU memory usage.
Workaround: upload shorter video clips, or close other GPU-consuming processes first.

**Model stuck at `model_ready: false`**

Check the uvicorn terminal output — usually caused by a missing checkpoint path or CUDA initialization failure.
Confirm that `checkpoints/wham_vit_bedlam_w_3dpw.pth.tar` exists.
