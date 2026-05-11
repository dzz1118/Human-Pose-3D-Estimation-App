from pathlib import Path
from uuid import uuid4

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from processor import process_video

BASE_DIR = Path(__file__).resolve().parent
UPLOAD_DIR = BASE_DIR / 'uploads'
OUTPUT_DIR = BASE_DIR / 'outputs'

UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title='NeuroMotion Backend', version='0.1.0')

app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'],
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
)


@app.get('/health')
def health() -> dict[str, str]:
    return {'status': 'ok', 'service': 'neuromotion-backend'}


@app.post('/analyze')
async def analyze(file: UploadFile = File(...)) -> JSONResponse:
    if not file.filename:
        raise HTTPException(status_code=400, detail='Missing file name.')

    ext = Path(file.filename).suffix.lower()
    if ext not in {'.mp4', '.mov', '.avi', '.mkv', '.webm'}:
        raise HTTPException(status_code=400, detail='Unsupported video format.')

    job_id = uuid4().hex
    input_path = UPLOAD_DIR / f'{job_id}{ext}'

    with input_path.open('wb') as buffer:
        buffer.write(await file.read())

    result = process_video(job_id=job_id, input_path=input_path, output_dir=OUTPUT_DIR)
    return JSONResponse(content=result)
