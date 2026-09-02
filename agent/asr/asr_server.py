#!/usr/bin/env python3
"""Local ASR service — offline Paraformer + streaming Zipformer. Port 8091."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np
from fastapi import FastAPI, File, HTTPException, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse

from streaming_engine import (
    STREAMING_ENGINE,
    StreamingSession,
    get_streaming_recognizer,
    streaming_model_ready,
    warmup_streaming,
    _streaming_paths,
    _streaming_error,
)

ASR_HOST = os.environ.get("TY1100_ASR_HOST", "0.0.0.0")
ASR_PORT = int(os.environ.get("TY1100_ASR_PORT", "8091"))
ENGINE_NAME = "sherpa-onnx-paraformer-zh"

app = FastAPI(title="TY1100 Local ASR", version="2.0")
_recognizer = None
_model_error: str | None = None
_model_paths: dict[str, str] = {}

ALLOWED_SUFFIX = {".wav", ".mp3", ".m4a", ".aac", ".flac", ".ogg", ".webm", ".opus"}


def resolve_model_paths() -> tuple[Path, Path]:
    """Locate tokens.txt and paraformer .onnx (model.int8.onnx in official pack)."""
    env_dir = os.environ.get("TY1100_ASR_MODEL_DIR", "").strip()
    candidates: list[Path] = []
    if env_dir:
        candidates.append(Path(env_dir))
    base = Path(__file__).resolve().parent
    candidates.extend(
        [
            base / "models" / "sherpa-onnx-paraformer-zh-2023-09-14",
            base / "models" / "paraformer-zh",
        ]
    )

    def pick_onnx(root: Path) -> Path | None:
        preferred = [
            root / "model.int8.onnx",
            root / "model.onnx",
            root / "paraformer.onnx",
        ]
        for p in preferred:
            if p.is_file():
                return p
        for p in sorted(root.rglob("*.onnx")):
            if "test_wavs" in p.parts:
                continue
            return p
        return None

    for root in candidates:
        if not root.is_dir():
            continue
        tokens = root / "tokens.txt"
        if not tokens.is_file():
            nested = list(root.rglob("tokens.txt"))
            tokens = nested[0] if nested else tokens
        paraformer = pick_onnx(root)
        if tokens.is_file() and paraformer:
            return tokens, paraformer
    raise FileNotFoundError(
        "ASR model not found. Run: bash ~/agent/asr/install-asr.sh"
    )


def warmup() -> None:
    get_recognizer()


def get_recognizer():
    global _recognizer, _model_error, _model_paths
    if _recognizer is not None:
        return _recognizer
    if _model_error:
        raise RuntimeError(_model_error)
    try:
        import sherpa_onnx

        tokens, paraformer = resolve_model_paths()
        _model_paths = {"tokens": str(tokens), "paraformer": str(paraformer)}
        _recognizer = sherpa_onnx.OfflineRecognizer.from_paraformer(
            paraformer=str(paraformer),
            tokens=str(tokens),
            num_threads=max(1, (os.cpu_count() or 4) - 2),
            provider="cpu",
        )
        return _recognizer
    except Exception as e:
        _model_error = str(e)
        raise


def ffmpeg_to_wav16k(src: Path, dst: Path) -> None:
    cmd = [
        "ffmpeg", "-y", "-i", str(src),
        "-ar", "16000", "-ac", "1", "-f", "wav", str(dst),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "ffmpeg failed")[:400]
        raise RuntimeError(err)


def read_wave(wav_path: Path) -> tuple[np.ndarray, int]:
    """Load mono 16-bit PCM wav as float32 samples in [-1, 1] (sherpa-onnx examples)."""
    with wave.open(str(wav_path), "rb") as f:
        if f.getnchannels() != 1:
            raise RuntimeError(f"expected mono wav, got {f.getnchannels()} channels")
        if f.getsampwidth() != 2:
            raise RuntimeError(f"expected 16-bit wav, got {f.getsampwidth()} bytes/sample")
        samples = np.frombuffer(f.readframes(f.getnframes()), dtype=np.int16)
        return samples.astype(np.float32) / 32768.0, f.getframerate()


def transcribe_wav(wav_path: Path) -> str:
    recognizer = get_recognizer()
    samples, sample_rate = read_wave(wav_path)
    if sample_rate != 16000:
        raise RuntimeError(f"expected 16kHz wav, got {sample_rate}")
    stream = recognizer.create_stream()
    stream.accept_waveform(sample_rate, samples)
    recognizer.decode_stream(stream)
    return (stream.result.text or "").strip()


def offline_model_ready() -> bool:
    try:
        resolve_model_paths()
        return True
    except FileNotFoundError:
        return False


@app.get("/health")
def health():
    # Do not load models here — only report file/cache state (avoids OOM on edge device).
    ok = _recognizer is not None or offline_model_ready()
    err = _model_error if not ok else None
    if not ok and _model_error:
        err = _model_error

    stream_ok = _streaming_recognizer is not None or streaming_model_ready()
    stream_err = _streaming_error if not stream_ok else None

    return {
        "status": "ok" if ok else "error",
        "engine": ENGINE_NAME,
        "device": "cpu",
        "ready": ok,
        "error": err,
        "model": _model_paths,
        "streaming_ready": stream_ok,
        "streaming_engine": STREAMING_ENGINE if stream_ok else None,
        "streaming_error": stream_err,
        "streaming_model": _streaming_paths if _streaming_recognizer else {},
    }


@app.websocket("/ws/stream")
async def ws_stream(websocket: WebSocket):
    await websocket.accept()
    try:
        session = StreamingSession()
    except Exception as e:
        await websocket.send_json({"type": "error", "message": str(e)})
        await websocket.close(code=1011)
        return

    await websocket.send_json({"type": "ready", "engine": STREAMING_ENGINE})
    try:
        while True:
            msg = await websocket.receive()
            if msg.get("type") == "websocket.disconnect":
                break
            if "bytes" in msg and msg["bytes"]:
                result = session.feed_pcm16(msg["bytes"])
                await websocket.send_json({"type": "partial", "text": result["partial"]})
            elif "text" in msg and msg["text"]:
                data = json.loads(msg["text"])
                if data.get("type") == "stop":
                    text = session.finish()
                    await websocket.send_json({"type": "final", "text": text})
                    break
    except WebSocketDisconnect:
        pass
    finally:
        try:
            await websocket.close()
        except Exception:
            pass


@app.post("/transcribe")
async def transcribe(file: UploadFile = File(...)):
    if not file.filename:
        raise HTTPException(400, "filename required")
    suffix = Path(file.filename).suffix.lower() or ".wav"
    if suffix not in ALLOWED_SUFFIX:
        raise HTTPException(400, f"unsupported format: {suffix}")

    raw_bytes = await file.read()
    if not raw_bytes:
        raise HTTPException(400, "empty file")
    max_mb = int(os.environ.get("TY1100_ASR_MAX_MB", "200"))
    if len(raw_bytes) > max_mb * 1024 * 1024:
        raise HTTPException(413, f"file too large (max {max_mb}MB)")

    with tempfile.TemporaryDirectory(prefix="ty1100_asr_") as td:
        raw_path = Path(td) / f"input{suffix}"
        wav_path = Path(td) / "input.wav"
        raw_path.write_bytes(raw_bytes)
        try:
            ffmpeg_to_wav16k(raw_path, wav_path)
        except RuntimeError as e:
            raise HTTPException(400, f"audio convert failed: {e}") from e
        try:
            text = transcribe_wav(wav_path)
        except Exception as e:
            raise HTTPException(502, f"asr inference failed: {e}") from e

    return JSONResponse({
        "text": text,
        "engine": ENGINE_NAME,
        "chars": len(text),
        "filename": file.filename,
    })


def main():
    parser = argparse.ArgumentParser(description="TY1100 local ASR service")
    parser.add_argument("--host", default=ASR_HOST)
    parser.add_argument("--port", type=int, default=ASR_PORT)
    parser.add_argument("--warmup", action="store_true")
    args = parser.parse_args()
    if args.warmup:
        print("Loading offline Paraformer…")
        warmup()
        print("Offline model ready:", _model_paths)
        if streaming_model_ready():
            print("Loading streaming Zipformer…")
            warmup_streaming()
            print("Streaming model ready:", _streaming_paths)
        return
    import uvicorn
    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()
