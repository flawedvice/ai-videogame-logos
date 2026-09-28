from whisper import Whisper
from typing import Union
import numpy as np
import time
import re


def process_audio(
    audio_samples: np.ndarray, listener: Whisper
) -> tuple[Union[str, None], float]:

    start = time.perf_counter()

    transcript = listener.transcribe(
        audio_samples, fp16=False, verbose=True, language="en"
    ).get("text")

    text = ""
    if transcript is None:
        end = time.perf_counter()
        return None, end - start
    elif isinstance(transcript, str):
        text = transcript.lower()
    else:
        text = "".join(transcript).lower()

    end = time.perf_counter()
    return re.sub(r"[^a-z ]", " ", text).strip(), end - start
