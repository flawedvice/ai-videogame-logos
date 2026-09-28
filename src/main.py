from config import (
    get_nlp,
    get_listener,
    vectorize_vocabulary,
    get_logger,
    AVAILABLE_MODELS,
)
from custom_types import Model, Vocabulary, VocabularyVectors
from fastapi.middleware.cors import CORSMiddleware
from scipy.signal import resample_poly
from command_processor import pipeline
from fastapi import FastAPI, Request
from typing import Union
import numpy as np
import uvicorn
import time

app = FastAPI()

origins = ["http://localhost:*", "http://127.0.0.1:*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


logger = get_logger()
logger.info("Instantiated custom logger")

default_model: Model = "small"
listener = get_listener(default_model)
logger.info(f"Instantiated Whisper listener using {default_model} default model")

nlp = get_nlp()
logger.info(f"Instantiated SpaCy's en_core_web_sm model")


vocabulary: Union[Vocabulary, None] = {
    "scan": ["check", "look", "inspect"],
    "stop": ["quiet", "halt"],
    "move": ["run", "walk", "go"],
    "jump": ["up"],
    "stand": ["rise"],
    "crouch": ["down", "duck", "low"],
    "left": ["back"],
    "right": ["forward"],
    "attack": ["shoot", "hit"],
    "interact": ["use", "open", "close", "pick"],
    "door": ["doors", "gate"],
    "enemy": ["foe", "creature"],
}
vocabulary_vectors: Union[VocabularyVectors, None] = vectorize_vocabulary(
    vocabulary=vocabulary, vectorizer=nlp
)
logger.info("Generated default vocabulary")

logger.info("Server ready for new connections")


@app.get("/ping")
async def ping_server():
    return {
        "status": "OK",
        "method": "GET",
        "endpoint": "/ping",
        "message": "Hello from server",
    }


@app.post("/listen")
async def listen_audio(request: Request):
    start = time.perf_counter()
    if not vocabulary or not vocabulary_vectors:
        end = time.perf_counter()
        return {
            "status": "ERROR",
            "method": "POST",
            "endpoint": "/listen",
            "message": "Must establish a vocabulary first.",
            "response_time": end - start,
        }

    byte_data = await request.body()
    src_rate = int(request.headers.get("x-sample-rate", 48000))
    is_stereo = request.headers.get("x-stereo", "true").lower() == "true"
    header_model = request.headers.get("x-model", default_model)

    # Allow player to use different models
    model = header_model if header_model in AVAILABLE_MODELS else default_model
    session_listener = listener if model == default_model else get_listener(model)
    logger.info(f"Using Whisper's {model} model")

    # Godot usually sends 16-bit PCM as integers:
    audio_samples = np.frombuffer(byte_data, dtype=np.int16)

    # Downmix stereo -> mono
    if is_stereo:
        audio_mono = audio_samples.reshape(-1, 2).mean(axis=1)
    else:
        audio_mono = audio_samples.astype(np.float64)

    # Convert to float32 (normalize to [-1.0, 1.0]) for Whisper
    audio_mono = (audio_mono / 32768.0).astype(np.float32)

    # Resample to 16kHz for Whisper
    if src_rate != 16000:
        audio_mono = resample_poly(audio_mono, 16000, src_rate).astype(np.float32)

    if np.isnan(audio_mono).any():
        logger.error("CRITICAL: NaN values detected in audio samples!")
        return {"status": "ERROR", "message": "Invalid audio data (NaNs)"}

    logger.info("Got audio data. Processing in pipeline...")
    results = pipeline(
        audio_samples=audio_mono,
        listener=session_listener,
        nlp=nlp,
        vocabulary_mappings=vocabulary,
        vocabulary_vectors=vocabulary_vectors,
        logger=logger,
        threshold=0.6,
    )
    logger.info(f"Got pipeline's results in {results["pipeline_latency"]["overall"]}s")

    end = time.perf_counter()

    return {
        "status": "OK",
        "method": "POST",
        "endpoint": "/listen",
        "metadata": {
            "received": f"{len(byte_data)} bytes",
            "source_rate": src_rate,
            "samples": len(audio_mono),
            "duration": f"{len(audio_mono)/16000:.2f}s",
            "model": model,
        },
        "results": results,
        "response_time": end - start,
    }


@app.get("/vocabulary")
def get_vocabulary():
    return {
        "status": "OK",
        "method": "GET",
        "endpoint": "/vocabulary",
        "vocabulary": vocabulary,
    }


@app.post("/vocabulary")
def update_vocabulary(vocab: Vocabulary):
    start = time.perf_counter()
    global vocabulary
    global vocabulary_vectors

    vocabulary = vocab
    vocabulary_vectors = vectorize_vocabulary(vocabulary=vocabulary, vectorizer=nlp)

    end = time.perf_counter()
    logger.debug("Successfully updated vocabulary")

    return {
        "status": "OK",
        "endpoint": "/vocabulary",
        "method": "POST",
        "message": "Updated vocabulary",
        "vocabulary": vocabulary,
        "response_time": end - start,
    }


def serve():
    """Serve the API using uvicorn"""
    uvicorn.run(app, port=8000, host="0.0.0.0", access_log=False)


if __name__ == "__main__":
    serve()
