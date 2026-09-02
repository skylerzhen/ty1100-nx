"""Online (streaming) ASR — sherpa-onnx Zipformer-zh on CPU."""

from __future__ import annotations

import os
from pathlib import Path

import numpy as np

STREAMING_ENGINE = "sherpa-onnx-streaming-zipformer-zh-14M"
STREAMING_MODEL_DIR = "sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23"

_streaming_recognizer = None
_streaming_error: str | None = None
_streaming_paths: dict[str, str] = {}


def _asr_base() -> Path:
    return Path(__file__).resolve().parent


def _pick_onnx(root: Path, role: str) -> Path | None:
    preferred = [
        root / f"{role}-epoch-99-avg-1.int8.onnx",
        root / f"{role}.int8.onnx",
        root / f"{role}-epoch-99-avg-1.onnx",
        root / f"{role}.onnx",
    ]
    for p in preferred:
        if p.is_file():
            return p
    matches = sorted(
        p for p in root.rglob(f"*{role}*.onnx")
        if p.is_file() and "test_wavs" not in p.parts
    )
    int8 = [p for p in matches if ".int8." in p.name or "int8" in p.name]
    if int8:
        return int8[0]
    return matches[0] if matches else None


def resolve_streaming_model_paths() -> tuple[Path, Path, Path, Path]:
    env_dir = os.environ.get("TY1100_ASR_STREAM_MODEL_DIR", "").strip()
    candidates: list[Path] = []
    if env_dir:
        candidates.append(Path(env_dir))
    base = _asr_base()
    candidates.append(base / "models" / STREAMING_MODEL_DIR)

    for root in candidates:
        if not root.is_dir():
            continue
        tokens = root / "tokens.txt"
        if not tokens.is_file():
            nested = list(root.rglob("tokens.txt"))
            tokens = nested[0] if nested else tokens
        encoder = _pick_onnx(root, "encoder")
        decoder = _pick_onnx(root, "decoder")
        joiner = _pick_onnx(root, "joiner")
        if tokens.is_file() and encoder and decoder and joiner:
            return tokens, encoder, decoder, joiner

    raise FileNotFoundError(
        f"Streaming model not found. Run: .\\scripts\\upload-asr-streaming-model.ps1"
    )


def streaming_model_ready() -> bool:
    try:
        resolve_streaming_model_paths()
        return True
    except FileNotFoundError:
        return False


def get_streaming_recognizer():
    global _streaming_recognizer, _streaming_error, _streaming_paths
    if _streaming_recognizer is not None:
        return _streaming_recognizer
    if _streaming_error:
        raise RuntimeError(_streaming_error)
    try:
        import sherpa_onnx

        tokens, encoder, decoder, joiner = resolve_streaming_model_paths()
        _streaming_paths = {
            "tokens": str(tokens),
            "encoder": str(encoder),
            "decoder": str(decoder),
            "joiner": str(joiner),
        }
        _streaming_recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
            tokens=str(tokens),
            encoder=str(encoder),
            decoder=str(decoder),
            joiner=str(joiner),
            num_threads=max(1, (os.cpu_count() or 4) - 2),
            provider="cpu",
            sample_rate=16000,
            feature_dim=80,
            decoding_method="greedy_search",
            enable_endpoint_detection=True,
            rule1_min_trailing_silence=2.4,
            rule2_min_trailing_silence=1.0,
            rule3_min_utterance_length=20,
        )
        return _streaming_recognizer
    except Exception as e:
        _streaming_error = str(e)
        raise


def warmup_streaming() -> None:
    get_streaming_recognizer()


class StreamingSession:
    """One browser mic session → one OnlineRecognizer stream."""

    def __init__(self) -> None:
        self.recognizer = get_streaming_recognizer()
        self.stream = self.recognizer.create_stream()
        self.committed: list[str] = []

    def _full_text(self, current: str) -> str:
        return "".join(self.committed) + (current or "")

    def feed_pcm16(self, pcm: bytes) -> dict:
        if not pcm:
            return {"partial": self._full_text(""), "segment": ""}
        samples = np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768.0
        return self.feed_samples(samples, 16000)

    def feed_samples(self, samples: np.ndarray, sample_rate: int) -> dict:
        self.stream.accept_waveform(sample_rate, samples)
        while self.recognizer.is_ready(self.stream):
            self.recognizer.decode_stream(self.stream)

        segment = (self.recognizer.get_result(self.stream).text or "").strip()
        endpoint = self.recognizer.is_endpoint(self.stream)
        if endpoint:
            if segment:
                self.committed.append(segment)
            self.recognizer.reset(self.stream)
            segment = ""

        return {
            "partial": self._full_text(segment),
            "segment": segment,
            "endpoint": endpoint,
        }

    def finish(self) -> str:
        tail = np.zeros(int(0.3 * 16000), dtype=np.float32)
        self.feed_samples(tail, 16000)
        while self.recognizer.is_ready(self.stream):
            self.recognizer.decode_stream(self.stream)
        last = (self.recognizer.get_result(self.stream).text or "").strip()
        if last:
            self.committed.append(last)
        return "".join(self.committed)
