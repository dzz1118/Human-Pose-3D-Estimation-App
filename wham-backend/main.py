"""
NeuroMotion Backend — FastAPI wrapper around WHAM inference.

Startup
-------
1. cwd → BASE_DIR so WHAM's relative paths (configs/, checkpoints/, …) resolve.
2. WHAM_API is instantiated once; network + detector are kept in GPU memory.
3. A single-worker ThreadPoolExecutor serialises GPU jobs.

Endpoints
---------
GET  /health                  liveness + GPU info
POST /process_video           upload MP4, queue job, return job_id
GET  /status/{job_id}         poll status; done → includes pkl/json/video URLs
GET  /results/{job_id}        return full parsed JSON (only when done)
GET  /files/…                 static file server for output videos + data
"""

from __future__ import annotations

import os
import sys
import json
import uuid
import shutil
import datetime
import joblib
import traceback
from enum import Enum
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from typing import Any

import cv2
import numpy as np
import torch
from functools import partial
torch.load = partial(torch.load, weights_only=False)

from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse
from pydantic import BaseModel

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
BASE_DIR   = Path(__file__).resolve().parent.parent   # /home/dz/WHAM
UPLOAD_DIR = BASE_DIR / "backend" / "uploads"
OUTPUT_DIR = BASE_DIR / "output" / "api_jobs"

# SMPL joint regressor: (25, 6890) maps mesh vertices → 25 WHAM keypoints
_J_REG_PATH = BASE_DIR / "dataset" / "body_models" / "J_regressor_wham.npy"

UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Fix cwd so WHAM internal relative paths resolve correctly
os.chdir(BASE_DIR)
if str(BASE_DIR) not in sys.path:
    sys.path.insert(0, str(BASE_DIR))

# ---------------------------------------------------------------------------
# WHAM joint names (25-joint WHAM convention, index order)
# ---------------------------------------------------------------------------
WHAM_JOINT_NAMES: list[str] = [
    "pelvis",           # 0
    "left_hip",         # 1
    "right_hip",        # 2
    "spine1",           # 3
    "left_knee",        # 4
    "right_knee",       # 5
    "spine2",           # 6
    "left_ankle",       # 7
    "right_ankle",      # 8
    "spine3",           # 9
    "left_foot",        # 10
    "right_foot",       # 11
    "neck",             # 12
    "left_collar",      # 13
    "right_collar",     # 14
    "head",             # 15
    "left_shoulder",    # 16
    "right_shoulder",   # 17
    "left_elbow",       # 18
    "right_elbow",      # 19
    "left_wrist",       # 20
    "right_wrist",      # 21
    "left_hand",        # 22
    "right_hand",       # 23
    "jaw",              # 24
]

# ---------------------------------------------------------------------------
# Video FPS detection
# ---------------------------------------------------------------------------
def _get_video_fps(video_path: Path) -> float:
    cap = cv2.VideoCapture(str(video_path))
    fps = cap.get(cv2.CAP_PROP_FPS)
    cap.release()
    return fps if fps > 0 else 30.0


# ---------------------------------------------------------------------------
# Clinical gait metric computation
# ---------------------------------------------------------------------------
def _knee_angle(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> float:
    """Angle at vertex b (in degrees) formed by a→b→c."""
    v1 = a - b
    v2 = c - b
    cos_a = np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-8)
    return float(np.degrees(np.arccos(np.clip(cos_a, -1.0, 1.0))))


def _compute_clinical_metrics(
    joints3d: np.ndarray,
    trans_world: np.ndarray,
    fps: float = 30.0,
) -> dict:
    """
    Derive clinical gait metrics from WHAM joint positions.

    joints3d  : (T, 25, 3) — joint positions in camera space
    trans_world: (T,  3)   — root translation in world space (metres)
    fps        : video frame rate

    WHAM joint indices used
    -----------------------
    left_hip=1  left_knee=4  left_ankle=7  left_foot=10
    right_hip=2 right_knee=5 right_ankle=8 right_foot=11
    """
    T = joints3d.shape[0]
    duration = T / fps if fps > 0 else T / 30.0

    # ── gait velocity (m/s) ────────────────────────────────────────────────
    # horizontal displacement ignoring vertical (Y-up convention in WHAM world)
    horiz = trans_world[-1, [0, 2]] - trans_world[0, [0, 2]]
    gait_velocity = float(np.linalg.norm(horiz) / duration) if duration > 0 else 0.0

    # ── knee flexion angles per frame ──────────────────────────────────────
    left_angles = np.array([
        _knee_angle(joints3d[t, 1], joints3d[t, 4], joints3d[t, 7])
        for t in range(T)
    ])
    right_angles = np.array([
        _knee_angle(joints3d[t, 2], joints3d[t, 5], joints3d[t, 8])
        for t in range(T)
    ])

    left_rom  = float(left_angles.max()  - left_angles.min())
    right_rom = float(right_angles.max() - right_angles.min())

    # ── stride length (m) — approximate via foot vertical oscillation ──────
    left_foot_y = joints3d[:, 10, 1]
    foot_detrended = left_foot_y - left_foot_y.mean()
    zero_crossings = int(((foot_detrended[:-1] < 0) & (foot_detrended[1:] >= 0)).sum())
    num_strides = max(zero_crossings, 1)
    stride_length = float(np.linalg.norm(horiz) / num_strides)

    # ── knee cycle angles (12 equidistant points, 0→100 % gait cycle) ─────
    indices = np.linspace(0, T - 1, 12, dtype=int)
    knee_cycle_angles = left_angles[indices].round(1).tolist()

    return {
        "gait_velocity":      round(gait_velocity, 3),
        "left_knee_rom":      round(left_rom, 1),
        "right_knee_rom":     round(right_rom, 1),
        "stride_length":      round(stride_length, 3),
        "knee_cycle_angles":  knee_cycle_angles,
    }


# ---------------------------------------------------------------------------
# Job registry
# ---------------------------------------------------------------------------
class JobStatus(str, Enum):
    QUEUED     = "queued"
    PROCESSING = "processing"
    DONE       = "done"
    FAILED     = "failed"

jobs: dict[str, dict[str, Any]] = {}

# ---------------------------------------------------------------------------
# WHAM singleton + thread pool
# ---------------------------------------------------------------------------
wham_model = None
_J_regressor: np.ndarray | None = None   # loaded once from disk

_executor = ThreadPoolExecutor(max_workers=1)


# ---------------------------------------------------------------------------
# Rotation matrix → axis-angle (pure numpy, no extra deps)
# ---------------------------------------------------------------------------
def _rotmat_to_axis_angle(rotmat: np.ndarray) -> np.ndarray:
    """
    Convert rotation matrices to axis-angle vectors.

    Args:
        rotmat: (..., 3, 3)
    Returns:
        axis_angle: (..., 3)
    """
    batch = rotmat.shape[:-2]
    R = rotmat.reshape(-1, 3, 3)
    n = R.shape[0]

    # angle from trace: cos(θ) = (tr(R) - 1) / 2
    trace = R[:, 0, 0] + R[:, 1, 1] + R[:, 2, 2]
    cos_a = np.clip((trace - 1.0) / 2.0, -1.0, 1.0)
    angle = np.arccos(cos_a)                # (N,)

    # axis from skew-symmetric part
    axis = np.stack([
        R[:, 2, 1] - R[:, 1, 2],
        R[:, 0, 2] - R[:, 2, 0],
        R[:, 1, 0] - R[:, 0, 1],
    ], axis=-1)                             # (N, 3)

    sin_a = np.sin(angle)
    # avoid div-by-zero for near-zero angles
    safe_sin = np.where(sin_a < 1e-6, 1.0, sin_a)
    axis = axis / (2.0 * safe_sin[..., None])
    # zero-out axes for near-zero angles (identity rotation → zero vector)
    axis = np.where(sin_a[..., None] < 1e-6, 0.0, axis)

    aa = axis * angle[..., None]            # (N, 3)
    return aa.reshape(*batch, 3)


# ---------------------------------------------------------------------------
# Core: WHAM results → frontend JSON
# ---------------------------------------------------------------------------
def wham_results_to_json(
    results: dict,
    job_id: str,
    j_regressor: np.ndarray,
    fps: float = 30.0,
) -> dict:
    """
    Convert raw WHAM output (NumPy arrays) to a JSON-serialisable dict.

    WHAM_API per-subject keys
    -------------------------
    poses_body        (T, 23, 3, 3)  body joint rotation matrices (no root)
    poses_root_cam    (T,  1, 3, 3)  root rotation in camera space
    poses_root_world  (T,  1, 3, 3)  root rotation in world space
    betas             (10,)          SMPL shape parameters
    verts_cam         (T, 6890, 3)   mesh vertices in camera space
    trans_world       (T, 3)         root translation in world space
    frame_id          list[int]      source frame indices
    """
    subjects_out = []

    for subj_id, data in results.items():
        # ── rotation matrices ──────────────────────────────────────────────
        poses_body: np.ndarray = data["poses_body"]         # (T, 23, 3, 3)
        poses_root_cam: np.ndarray = data["poses_root_cam"] # (T, 1, 3, 3) or (T, 3, 3)

        if poses_body.ndim == 4:
            T = poses_body.shape[0]
        else:
            poses_body = poses_body[None]
            T = 1

        # squeeze joint-1 dim if present
        if poses_root_cam.ndim == 4:
            poses_root_cam = poses_root_cam.squeeze(1)      # → (T, 3, 3)

        # ── axis-angle conversion ──────────────────────────────────────────
        aa_body = _rotmat_to_axis_angle(poses_body)         # (T, 23, 3)
        aa_root = _rotmat_to_axis_angle(poses_root_cam)     # (T, 3)

        # ── 3-D joint positions from mesh vertices ─────────────────────────
        verts_cam: np.ndarray = data["verts_cam"]           # (T, 6890, 3) or (1, T, 6890, 3)
        if verts_cam.ndim == 4:
            verts_cam = verts_cam.squeeze(0)                # → (T, 6890, 3)

        # j_regressor: (25, 6890) → joints: (T, 25, 3)
        joints3d = np.einsum("jv,tvd->tjd", j_regressor, verts_cam)

        # ── translations ───────────────────────────────────────────────────
        trans_world: np.ndarray = data["trans_world"]       # (T, 3)

        # ── betas ──────────────────────────────────────────────────────────
        betas: np.ndarray = data["betas"]                   # (10,)

        clinical = _compute_clinical_metrics(joints3d, trans_world, fps)

        subjects_out.append({
            "id":           int(subj_id),
            "num_frames":   int(T),
            "frame_ids":    [int(f) for f in data["frame_id"]],
            "betas":        betas.astype(float).round(6).tolist(),
            # (T, 3) root axis-angle in camera space
            "poses_root_cam": aa_root.astype(float).round(6).tolist(),
            # (T, 23, 3) body joint axis-angles
            "poses_body":   aa_body.astype(float).round(6).tolist(),
            # (T, 3) world root translation [metres]
            "trans_world":  trans_world.astype(float).round(6).tolist(),
            # (T, 25, 3) 3-D joint positions in camera space [metres]
            "joints3d_cam": joints3d.astype(float).round(6).tolist(),
            # joint name list matching the joints3d_cam index order
            "joint_names":  WHAM_JOINT_NAMES,
            # clinical gait metrics derived from joint positions
            "clinical_metrics": clinical,
        })

    return {
        "meta": {
            "job_id":       job_id,
            "num_subjects": len(subjects_out),
            "created_at":   datetime.datetime.utcnow().isoformat() + "Z",
            "coord_convention": (
                "joints3d_cam in WHAM camera space (Y-up). "
                "trans_world / poses_root_world in global world space."
            ),
        },
        "subjects": subjects_out,
    }


# ---------------------------------------------------------------------------
# Background inference task
# ---------------------------------------------------------------------------
def _classify_error(exc: Exception) -> tuple[str, str]:
    """Return (error_type, human_readable_message)."""
    # CUDA OOM — Python 3.10+ has OutOfMemoryError; older versions raise RuntimeError
    oom = isinstance(exc, torch.cuda.OutOfMemoryError) or (
        isinstance(exc, RuntimeError) and "out of memory" in str(exc).lower()
    )
    if oom:
        mem_alloc = (
            f"{torch.cuda.memory_allocated() / 1e9:.1f} GB allocated, "
            f"{torch.cuda.max_memory_reserved() / 1e9:.1f} GB reserved"
        )
        return (
            "cuda_out_of_memory",
            f"GPU ran out of memory during inference ({mem_alloc}). "
            "Try a shorter clip, lower-resolution video, or free other GPU processes.",
        )
    return "inference_error", str(exc)


def _run_wham(job_id: str, video_path: Path, output_dir: Path) -> None:
    """Blocking WHAM inference — runs inside the single-worker thread pool."""
    jobs[job_id]["status"] = JobStatus.PROCESSING
    try:
        output_dir.mkdir(parents=True, exist_ok=True)

        results, _tracking, _slam = wham_model(
            video=str(video_path),
            output_dir=str(output_dir),
            run_global=False,   # set True when DPVO/SLAM is available
            visualize=True,     # writes output_dir/output.mp4
        )

        # ── persist raw pkl ────────────────────────────────────────────────
        pkl_path = output_dir / "wham_output.pkl"
        joblib.dump(results, pkl_path)

        # ── parse to frontend JSON ─────────────────────────────────────────
        video_fps = _get_video_fps(video_path)
        parsed = wham_results_to_json(results, job_id, _J_regressor, fps=video_fps)
        json_path = output_dir / "wham_output.json"
        json_path.write_text(
            json.dumps(parsed, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )

        # ── check for rendered video ───────────────────────────────────────
        video_out = output_dir / "output.mp4"
        video_url = (
            f"/files/{job_id}/output.mp4" if video_out.exists() else None
        )

        jobs[job_id].update({
            "status":        JobStatus.DONE,
            "output_dir":    str(output_dir),
            "pkl_path":      str(pkl_path),
            "json_path":     str(json_path),
            "video_url":     video_url,
            "subject_ids":   list(results.keys()),
            "num_subjects":  len(results),
        })

    except Exception as exc:
        torch.cuda.empty_cache()            # release GPU memory after OOM
        error_type, error_msg = _classify_error(exc)
        jobs[job_id].update({
            "status":     JobStatus.FAILED,
            "error_type": error_type,
            "error":      error_msg,
            "traceback":  traceback.format_exc(),
        })


# ---------------------------------------------------------------------------
# Lifespan: load model + joint regressor once at startup
# ---------------------------------------------------------------------------
@asynccontextmanager
async def lifespan(app: FastAPI):
    global wham_model, _J_regressor

    from wham_api import WHAM_API          # import after cwd is set
    wham_model = WHAM_API()

    _J_regressor = np.load(str(_J_REG_PATH)).astype(np.float32)  # (25, 6890)

    yield
    _executor.shutdown(wait=False)


# ---------------------------------------------------------------------------
# App + middleware
# ---------------------------------------------------------------------------
app = FastAPI(title="NeuroMotion API", version="0.3.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://localhost:5173",
        "http://localhost:8080",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:5173",
        "http://127.0.0.1:8080",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Static file server — frontend accesses output videos at /files/{job_id}/output.mp4
app.mount(
    "/files",
    StaticFiles(directory=str(OUTPUT_DIR), html=False),
    name="output_files",
)


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------
class SubmitResponse(BaseModel):
    job_id: str
    status: str
    message: str
    video_path: str


class StatusResponse(BaseModel):
    job_id: str
    status: str
    # done
    output_dir:   str | None = None
    pkl_path:     str | None = None
    json_path:    str | None = None
    video_url:    str | None = None   # relative URL, e.g. /files/{job_id}/output.mp4
    subject_ids:  list[int] | None = None
    num_subjects: int | None = None
    # failed
    error_type:   str | None = None
    error:        str | None = None
    traceback:    str | None = None


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.get("/health")
def health_check():
    """Liveness probe — reports GPU info and model readiness."""
    gpu_info = {}
    if torch.cuda.is_available():
        gpu_info = {
            "name":          torch.cuda.get_device_name(0),
            "memory_total":  f"{torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB",
            "memory_used":   f"{torch.cuda.memory_allocated(0) / 1e9:.2f} GB",
        }
    return {
        "status":      "ok",
        "model_ready": wham_model is not None,
        "device":      "cuda" if torch.cuda.is_available() else "cpu",
        "gpu":         gpu_info,
        "base_dir":    str(BASE_DIR),
        "output_dir":  str(OUTPUT_DIR),
    }


@app.post("/process_video", response_model=SubmitResponse)
async def process_video(file: UploadFile = File(...)):
    """
    Accept an MP4 upload and queue a WHAM inference job.
    Returns immediately with job_id — poll /status/{job_id} for progress.
    """
    if wham_model is None:
        raise HTTPException(503, "WHAM model not yet ready. Retry in a moment.")

    if file.content_type and not file.content_type.startswith("video/"):
        raise HTTPException(
            415,
            f"Expected a video file, received '{file.content_type}'.",
        )

    job_id = str(uuid.uuid4())
    job_upload_dir = UPLOAD_DIR / job_id
    job_upload_dir.mkdir(parents=True, exist_ok=True)

    suffix = Path(file.filename).suffix if file.filename else ".mp4"
    video_path = job_upload_dir / f"input{suffix}"

    try:
        with video_path.open("wb") as fh:
            shutil.copyfileobj(file.file, fh)
    finally:
        await file.close()

    jobs[job_id] = {
        "status":     JobStatus.QUEUED,
        "video_path": str(video_path),
    }

    output_dir = OUTPUT_DIR / job_id
    _executor.submit(_run_wham, job_id, video_path, output_dir)

    return SubmitResponse(
        job_id=job_id,
        status=JobStatus.QUEUED,
        message=f"Job queued. Poll /status/{job_id} for updates.",
        video_path=str(video_path),
    )


@app.get("/status/{job_id}", response_model=StatusResponse)
def get_status(job_id: str):
    """Poll job status. When done, response includes json_path and video_url."""
    if job_id not in jobs:
        raise HTTPException(404, f"Job '{job_id}' not found.")

    info = jobs[job_id]
    return StatusResponse(
        job_id=job_id,
        **{k: v for k, v in info.items() if k != "video_path"},
    )


@app.get("/results/{job_id}")
def get_results(job_id: str):
    """
    Return the full parsed WHAM output as JSON.
    Only available when the job status is 'done'.
    """
    if job_id not in jobs:
        raise HTTPException(404, f"Job '{job_id}' not found.")

    info = jobs[job_id]

    if info["status"] == JobStatus.FAILED:
        raise HTTPException(
            422,
            {
                "message":    "Job failed.",
                "error_type": info.get("error_type"),
                "error":      info.get("error"),
            },
        )

    if info["status"] != JobStatus.DONE:
        raise HTTPException(
            409,
            f"Job is still '{info['status']}'. Results not yet available.",
        )

    json_path = Path(info["json_path"])
    if not json_path.exists():
        raise HTTPException(500, "Result JSON file missing from disk.")

    return JSONResponse(content=json.loads(json_path.read_text(encoding="utf-8")))
