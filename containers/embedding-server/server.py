# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
"""
Embedding server using FastEmbed (ONNX backend).

Provides both OpenAI-compatible and Ollama-compatible APIs:
  - POST /v1/embeddings   (OpenAI format, for Gap Indexer)
  - POST /api/embed        (Ollama format, for Kilo Code)
  - POST /api/embeddings   (Ollama format, legacy)
Uses ONNX inference (via FastEmbed) for fast, memory-efficient embeddings.
Default model: sentence-transformers/paraphrase-multilingual-mpnet-base-v2 (768d, German + English).

Environment variables:
    MODEL_ID   — FastEmbed model name (default: sentence-transformers/paraphrase-multilingual-mpnet-base-v2)
    PORT       — Server port (default: 7997)
"""

import json
import logging
import os
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
from typing import List

# Monkey-patch onnxruntime BEFORE fastembed imports it.
# The crash on ARM was caused by SimplifiedLayerNormFusion (EXTENDED opt).
# BASIC optimizations (constant folding, redundant node removal) are safe
# and give a significant speed boost (~2-3x faster inference).
import onnxruntime as ort
ort.set_default_logger_severity(3)  # suppress verbose ORT warnings

_OrigSession = ort.InferenceSession

class _PatchedSession(_OrigSession):
    """InferenceSession with safe BASIC optimizations for ARM."""
    def __init__(self, *args, **kwargs):
        opts = kwargs.get("sess_options") or ort.SessionOptions()
        opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_BASIC
        opts.intra_op_num_threads = 0  # Use all available cores
        opts.inter_op_num_threads = 1  # Single inter-op thread (we serialize anyway)
        opts.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        kwargs["sess_options"] = opts
        super().__init__(*args, **kwargs)

ort.InferenceSession = _PatchedSession

from fastembed import TextEmbedding  # noqa: E402

# Configuration
MODEL_ID = os.getenv("MODEL_ID", "sentence-transformers/paraphrase-multilingual-mpnet-base-v2")
PORT = int(os.getenv("PORT", "7997"))

# Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("embedding-server")

# Load model at startup with disabled graph optimizations
logger.info("Loading model: %s (graph optimizations disabled for ARM compat)", MODEL_ID)
t0 = time.time()
model = TextEmbedding(model_name=MODEL_ID)
load_time = time.time() - t0
logger.info("Model loaded in %.1fs", load_time)

# Warmup with a single embedding
list(model.embed(["warmup"]))
logger.info("Model ready")

# Serialize inference calls to prevent OOM from concurrent model.embed()
# on ARM ONNX — each call allocates ~200MB, parallel calls compound.
MAX_SERVER_BATCH = 16   # Texts per sub-batch (safe with small 512-token chunks)
_EMBED_TIMEOUT = 60     # Seconds before model.embed() is considered stuck
# Ingest holds lock for this many texts per acquisition — search can interrupt between
INGEST_LOCK_BATCH = 1   # 1 text per lock hold: worst-case search wait ≈ 100ms per text


class PriorityEmbedLock:
    """Lock that gives priority to search requests over ingest requests.

    Search callers (X-Priority: search) get immediate access when the lock
    is released; ingest callers yield while any search request is waiting.
    This prevents bulk ingestion from starving interactive search.

    Ref: docs/specs/search_ingestion_contention_spec.md §5.1
    """

    def __init__(self):
        self._lock = threading.Lock()
        self._search_waiting = threading.Event()  # Set when search is waiting

    def acquire_search(self, timeout: float = 30) -> bool:
        """Acquire for search — sets priority flag so ingest yields."""
        self._search_waiting.set()
        try:
            acquired = self._lock.acquire(timeout=timeout)
            return acquired
        finally:
            self._search_waiting.clear()

    def acquire_ingest(self, timeout: float = 300) -> bool:
        """Acquire for ingest — yields if search is waiting."""
        deadline = time.monotonic() + timeout
        while self._search_waiting.is_set():
            if time.monotonic() >= deadline:
                return False
            time.sleep(0.05)  # Yield to search
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        return self._lock.acquire(timeout=remaining)

    def release(self):
        """Release the lock."""
        self._lock.release()


_embed_lock = PriorityEmbedLock()


class EmbeddingHandler(BaseHTTPRequestHandler):
    """Handle OpenAI-compatible /v1/embeddings requests."""

    def do_POST(self) -> None:
        # Read priority header: "search" gets lock priority, anything else = ingest
        self._priority = self.headers.get("X-Priority", "ingest").lower()
        if self.path == "/v1/embeddings":
            self._handle_openai_embeddings()
        elif self.path in ("/api/embed", "/api/embeddings"):
            self._handle_ollama_embeddings()
        else:
            self._send_error(404, "Not found")

    def _parse_body(self) -> dict | None:
        try:
            length = int(self.headers.get("Content-Length", 0))
            return json.loads(self.rfile.read(length))
        except (json.JSONDecodeError, ValueError) as exc:
            self._send_error(400, f"Invalid JSON: {exc}")
            return None

    def _embed_subbatch(self, batch: List[str]) -> List[list]:
        """Run model.embed() on a sub-batch with a hard timeout.

        Returns a list of embedding vectors. Raises TimeoutError if
        the ONNX runtime hangs for longer than _EMBED_TIMEOUT seconds.
        """
        result = [None]
        error = [None]

        def _run():
            try:
                result[0] = [e.tolist() for e in model.embed(batch)]
            except Exception as exc:
                error[0] = exc

        t = threading.Thread(target=_run, daemon=True)
        t.start()
        t.join(timeout=_EMBED_TIMEOUT)

        if t.is_alive():
            # Thread is stuck in ONNX native code — cannot be killed from Python.
            # The orphaned thread holds ONNX resources, corrupting state so that
            # subsequent model.embed() calls may also hang.  The only reliable
            # recovery is to restart the process; Docker restart policy handles it.
            logger.critical(
                "model.embed() stuck for %ds on %d texts — restarting process",
                _EMBED_TIMEOUT, len(batch),
            )
            os._exit(1)  # Hard exit; Docker will restart the container

        if error[0] is not None:
            raise error[0]
        return result[0]

    def _embed(self, texts: List[str]) -> tuple:
        """Embed texts, return (embeddings, elapsed_ms).

        Uses _embed_lock (PriorityEmbedLock) to serialize inference.
        Search requests (X-Priority: search) get lock priority over
        ingest requests, preventing bulk ingestion from starving
        interactive search.

        Ingest acquires the lock once per INGEST_LOCK_BATCH texts so search
        can interrupt between text batches (worst-case wait ≈ 1 text inference
        time, ~50–150ms on ARM). Search acquires the lock for the full query
        at once and is guaranteed to preempt any waiting ingest.
        """
        is_search = getattr(self, '_priority', 'ingest') == 'search'
        t0 = time.time()
        all_embeddings = []

        # For search: embed all texts under one lock acquisition (small query, fast)
        # For ingest: embed INGEST_LOCK_BATCH texts per lock hold so search can preempt
        lock_batch_size = MAX_SERVER_BATCH if is_search else INGEST_LOCK_BATCH

        for i in range(0, len(texts), lock_batch_size):
            batch = texts[i:i + lock_batch_size]
            if is_search:
                acquired = _embed_lock.acquire_search(timeout=45)
            else:
                acquired = _embed_lock.acquire_ingest(timeout=300)
            if not acquired:
                logger.error(
                    "Embed lock timeout (priority=%s) — another inference is stuck",
                    'search' if is_search else 'ingest',
                )
                raise TimeoutError("Embed lock acquisition timeout")
            try:
                all_embeddings.extend(self._embed_subbatch(batch))
            except Exception:
                logger.exception("model.embed() failed for sub-batch %d", i)
                raise
            finally:
                _embed_lock.release()
        elapsed_ms = (time.time() - t0) * 1000
        logger.info(
            "Embedded %d texts in %.0fms (%.0fms/text, priority=%s)",
            len(texts), elapsed_ms, elapsed_ms / max(len(texts), 1),
            'search' if is_search else 'ingest',
        )
        return all_embeddings, elapsed_ms

    def _handle_openai_embeddings(self) -> None:
        """OpenAI-compatible: POST /v1/embeddings"""
        body = self._parse_body()
        if body is None:
            return

        input_data = body.get("input", "")
        if isinstance(input_data, str):
            input_data = [input_data]
        if not input_data:
            self._send_error(400, "Empty input")
            return

        try:
            embeddings, _ = self._embed(input_data)
            self._send_json(200, {
                "object": "list",
                "data": [
                    {"object": "embedding", "index": i, "embedding": emb}
                    for i, emb in enumerate(embeddings)
                ],
                "model": body.get("model", MODEL_ID),
                "usage": {"prompt_tokens": 0, "total_tokens": 0},
            })
        except (BrokenPipeError, ConnectionResetError):
            logger.warning("Client disconnected before response could be sent")
        except TimeoutError as e:
            self._send_error(503, str(e))

    def _handle_ollama_embeddings(self) -> None:
        """Ollama-compatible: POST /api/embed or /api/embeddings"""
        body = self._parse_body()
        if body is None:
            return

        # Ollama accepts 'input' (string or list) or 'prompt' (string)
        input_data = body.get("input", body.get("prompt", ""))
        if isinstance(input_data, str):
            input_data = [input_data]
        if not input_data:
            self._send_error(400, "Empty input")
            return

        embeddings, _ = self._embed(input_data)
        # Ollama response format
        self._send_json(200, {
            "model": body.get("model", MODEL_ID),
            "embeddings": embeddings,
        })

    def do_HEAD(self) -> None:
        # Some clients check availability with HEAD
        if self.path == "/" or self.path == "/health":
            self.send_response(200)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self) -> None:
        if self.path == "/" or self.path == "":
            # Ollama root discovery — Kilo Code checks this first
            self._send_plain(200, "Ollama is running")
        elif self.path == "/api/version":
            self._send_json(200, {"version": "0.6.1"})
        elif self.path == "/health":
            self._send_json(200, {"status": "ok", "model": MODEL_ID})
        elif self.path == "/v1/models":
            self._send_json(200, {
                "object": "list",
                "data": [
                    {"id": MODEL_ID, "object": "model", "owned_by": "fastembed"},
                    {"id": "nomic-embed-text", "object": "model", "owned_by": "fastembed"},
                ],
            })
        elif self.path == "/api/tags":
            # Ollama model listing — include aliases Kilo Code may look for
            self._send_json(200, {
                "models": [
                    {
                        "name": "nomic-embed-text:latest",
                        "model": "nomic-embed-text:latest",
                        "size": 0, "digest": "",
                        "details": {"family": "fastembed", "parameter_size": "137M"},
                    },
                    {
                        "name": MODEL_ID,
                        "model": MODEL_ID,
                        "size": 0, "digest": "",
                        "details": {"family": "fastembed", "parameter_size": "137M"},
                    },
                ],
            })
        else:
            self._send_error(404, "Not found")

    def _send_json(self, code: int, data: dict) -> None:
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")  # Allow Kilo webview
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_plain(self, code: int, text: str) -> None:
        body = text.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Access-Control-Allow-Origin", "*")  # Allow Kilo webview
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_error(self, code: int, message: str) -> None:
        self._send_json(code, {"error": {"message": message, "code": code}})

    def do_OPTIONS(self) -> None:
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Priority")
        self.end_headers()


class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", PORT), EmbeddingHandler)
    logger.info("Serving on port %d", PORT)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Shutting down")
        server.server_close()
