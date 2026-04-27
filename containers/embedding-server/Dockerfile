FROM python:3.11-slim

WORKDIR /app

# Install curl for healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Install FastEmbed (ONNX-based embeddings)
RUN pip install --no-cache-dir "fastembed>=0.4.0"

COPY server.py .

# ─── Pre-download embedding model during build ─────────────────────────────
# FastEmbed downloads models lazily from HuggingFace on first use (~1GB).
# On slow connections this takes 30+ minutes, causing Kilo's codebase indexing
# to fail at startup. Pre-downloading bakes the model into the image layer.
# The cache directory /app/.cache is also used as the runtime volume mount.
#
# To change the model: edit EMBEDDING_MODEL_ID in .env and rebuild.
ARG EMBEDDING_MODEL_ID=sentence-transformers/paraphrase-multilingual-mpnet-base-v2
ENV FASTEMBED_CACHE_PATH=/app/.cache
RUN python -c "from fastembed import TextEmbedding; m = TextEmbedding('${EMBEDDING_MODEL_ID}', cache_dir='/app/.cache'); r = list(m.embed(['warmup'])); print(f'Model ready: {len(r[0])}d vectors')"

EXPOSE 7997

CMD ["python", "-u", "server.py"]
