from typing import Literal, Union, List
from compute_wer import Calculator
import pandas as pd
import requests
import time
import wave
import json
import sys
import os

sys.path.insert(
    0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
)

from config import AVAILABLE_MODELS
from custom_types import Model

calculator = Calculator(
    to_char=False,  # Character-level WER
    case_sensitive=False,  # Case-sensitive matching
    remove_tag=True,  # Remove tags from text
    ignore_punctuation=True,  # Ignore punctuation (except single quotes)
    max_wer=float("inf"),  # Maximum WER threshold
)


def process_audio(audio_filepath: str):
    with wave.open(audio_filepath) as f:
        audio_data: wave.Wave_read = f

        frames = audio_data.getnframes()

        channels = audio_data.getnchannels()
        stereo = True if channels == 2 else False

        sample_rate = audio_data.getframerate()

        data = audio_data.readframes(frames)

    return (stereo, sample_rate, data)


def send_post(stereo: bool, sample_rate: int, data: bytes, model: Model = "base"):
    url = "http://localhost:8000/listen"
    headers = {
        "Content-Type": "application/octet-stream",
        "Content-Length": str(len(data)),
        "X-Sample-Rate": str(sample_rate),
        "X-Stereo": str(stereo),
        "X-Model": model,
        "Cache-Control": "no-cache",
        "Cache-Control": "no-store",
    }

    res = requests.post(url, data=data, headers=headers)

    # Return tuple of OK status and content
    return res.ok, res.json() if res.ok else res.content


def compute_statistics(reference: str, hypothesis: str):
    wer = calculator.calculate(reference=reference, hypothesis=hypothesis)
    overall_wer, _ = calculator.overall()
    return overall_wer.wer


def save_results(
    results: List, format: Union[Literal["csv"], Literal["json"]] = "json"
):
    if format == "csv":
        df_data = []
        for result in results:
            latency = result["response"]["results"]["pipeline_latency"]
            metadata = result["response"]["metadata"]

            data = {
                "instance": result["instance"],
                "reference": result["reference"],
                "hypothesis": result["hypothesis"],
                "wer": result["wer"],
                "overall_latency (s)": latency["overall"],
                "listen_latency (s)": latency["listen"],
                "filter_latency (s)": latency["filter"],
                "normalize_latency (s)": latency["normalize"],
                "response_time (s)": result["response"]["response_time"],
                "file_size": int(metadata["received"][:-6]),
                "sample_rate": metadata["source_rate"],
                "samples": metadata["samples"],
                "duration (s)": float(metadata["duration"][:-1]),
                "model": metadata["model"],
            }
            df_data.append(data)

        df = pd.DataFrame(df_data)
        df.to_csv(os.path.join("tests", "results.csv"))
    else:
        filepath = os.path.join("tests", "results.json")
        with open(filepath, "w") as f:
            json.dump(results, fp=f)


def main():
    wav_dir = os.path.join("tests", "audios")
    wav_filepaths = [os.path.join(wav_dir, name) for name in os.listdir(wav_dir)]

    start = time.perf_counter()
    results = []
    for model in AVAILABLE_MODELS:
        for audio_path in wav_filepaths:
            audio_filename = audio_path.split(os.sep)[-1][:-4]

            # Get audio data
            stereo, sample_rate, data = process_audio(audio_path)

            # Get API response
            ok, response = send_post(
                stereo=stereo, sample_rate=sample_rate, data=data, model=model
            )

            if not ok or isinstance(response, bytes):
                raise Exception(str(response))

            reference_transcription = audio_filename
            hypothesis_transcription = response.get("results").get("sentence")
            result = {
                "instance": audio_filename + ".wav",
                "files": {
                    "audio_path": audio_path,
                },
                "response": response,
                "reference": reference_transcription,
                "hypothesis": hypothesis_transcription,
                "wer": (
                    compute_statistics(
                        reference_transcription, hypothesis_transcription
                    )
                    if hypothesis_transcription
                    else None
                ),
            }
            results.append(result)

    save_results(results, format="csv")
    save_results(results, format="json")
    end = time.perf_counter()
    print("Testing duration (s): ", end - start)


if __name__ == "__main__":
    main()
