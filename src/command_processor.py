from custom_types import (
    Vocabulary,
    VocabularyVectors,
    Elapsed,
    NormalizedMatches,
    PipelineResponse,
)
from typing import List, Union, Tuple, Literal, Annotated
from listener import process_audio
from whisper import Whisper
from logging import Logger
import spacy.language
import numpy as np
import Levenshtein
import time
import json


def filter(
    sentence: str, nlp: spacy.language.Language, execute=False
) -> tuple[Union[None, List[str]], float]:
    start = time.perf_counter()
    if sentence == "":
        end = time.perf_counter()
        return None, end - start

    if execute:
        doc = nlp(sentence)
        accepted_pos = ("VERB", "ADJ", "NOUN")
        keywords = [token.text for token in doc if token.pos_ in accepted_pos]
    else:
        keywords = sentence.split(" ")
    end = time.perf_counter()
    return (keywords if len(keywords) else None, end - start)


def normalize(
    input_word: str,
    nlp: spacy.language.Language,
    vocabulary: VocabularyVectors,
    logger: Logger,
    similarity_threshold=0.75,
) -> Tuple[Union[Tuple[str, str], None], str, float]:
    start = time.perf_counter()
    word = input_word.lower().strip()
    match_by: Literal["literal", "levenshtein", "embedding", "no_match"]

    # Check literal vocabulary
    for vocab in vocabulary.keys():
        if word == vocab:
            logger.info("Got literal")
            match_by = "literal"
            end = time.perf_counter()
            return (word, f"{word} ({vocab})"), match_by, end - start

    # Get matches with minimal typos using Levenshtein distance
    for vocab in vocabulary.keys():
        if Levenshtein.distance(word, vocab, score_cutoff=2) < 2:
            logger.info("Got Levenshtein similar")
            match_by = "levenshtein"
            end = time.perf_counter()
            return (word, vocab), match_by, end - start

    logger.info("Comparing vocabulary vectors")
    vector = np.asarray(nlp(word).vector, dtype=np.float32)
    best_match = None
    max_similarity = -1.0

    # Compare against vocabulary
    for known_w, known_v in vocabulary.items():
        if vector.shape == (0,):
            continue

        # Calculate cosine similarity (https://en.wikipedia.org/wiki/Cosine_similarity)
        similarity = np.dot(vector, known_v) / (
            np.linalg.norm(vector) * np.linalg.norm(known_v)
        )

        if similarity > max_similarity:
            max_similarity = similarity
            best_match = known_w

    # Apply similarity threshold
    end = time.perf_counter()
    if max_similarity > similarity_threshold and best_match:
        match_by = "embedding"
        return (word, best_match), match_by, end - start
    else:
        # No suitable matches were found
        match_by = "no_match"
        return None, match_by, end - start


def command_parse(
    sentence: str,
    nlp: spacy.language.Language,
    vocabulary_mapping: Vocabulary,
    vocabulary_vectors: VocabularyVectors,
    logger: Logger,
    elapsed: Union[Elapsed, None] = None,
    start_time=0.0,
    threshold=0.75,
):
    if not start_time:
        start_time = time.perf_counter()
    if elapsed is None:
        elapsed = {"filter": 0.0, "overall": 0.0, "normalize": 0.0}

    keywords, elapsed_filter = filter(sentence, nlp)
    elapsed["filter"] = elapsed_filter
    logger.debug(f"Filtered keywords: {", ".join(keywords) if keywords else "None"}")

    if keywords is None:
        end = time.perf_counter()
        elapsed["overall"] = end - start_time
        return None, elapsed

    elapsed_normalize = 0.0
    match_tuples: List[Tuple[Tuple[str, str], str]] = []
    for kw in keywords:
        match_tuple, match_by, elapsed_normalize_word = normalize(
            kw, nlp, vocabulary_vectors, logger, threshold
        )
        elapsed_normalize += elapsed_normalize_word
        if match_tuple is not None:
            match_tuples.append((match_tuple, match_by))

    normalized_matches: NormalizedMatches = []
    for match_tuple, match_by in match_tuples:
        for normalized, synonyms in vocabulary_mapping.items():
            original, match = match_tuple
            if match == normalized:
                normalized_matches.append((normalized, original, match_by))
            elif match in synonyms:
                normalized_matches.append((normalized, original, match_by))
                break

    logger.debug(
        f"command_parse:\nMatches: {json.dumps(match_tuples)}\nNormalized: {json.dumps(normalized_matches)}"
    )
    elapsed["normalize"] = elapsed_normalize
    return normalized_matches, elapsed


def pipeline(
    audio_samples: np.ndarray,
    listener: Whisper,
    nlp: spacy.language.Language,
    vocabulary_mappings: Vocabulary,
    vocabulary_vectors: VocabularyVectors,
    logger: Logger,
    threshold=0.75,
) -> PipelineResponse:

    elapsed: Elapsed = {"overall": 0.0, "listen": 0.0, "filter": 0.0, "normalize": 0.0}

    start = time.perf_counter()

    try:
        sentence, elapsed_listen = process_audio(
            audio_samples=audio_samples, listener=listener
        )

        logger.debug(f'process_audio output: "{sentence}"')

        elapsed["listen"] = elapsed_listen
        if sentence is None:
            logger.debug("Sentence is None. Exiting pipeline")
            end = time.perf_counter()
            elapsed["overall"] = end - start

            return {"sentence": None, "matches": None, "pipeline_latency": elapsed}

    except Exception as e:
        logger.error(e)
        raise Exception("Error when processing the audio samples at the pipeline")

    matches, elapsed = command_parse(
        sentence,
        nlp=nlp,
        vocabulary_mapping=vocabulary_mappings,
        vocabulary_vectors=vocabulary_vectors,
        elapsed=elapsed,
        logger=logger,
        start_time=start,
        threshold=threshold,
    )
    logger.debug(f'command_parse output: "{json.dumps(matches)}"')

    end = time.perf_counter()
    elapsed["overall"] = end - start

    if matches and len(matches):

        return {"sentence": sentence, "matches": matches, "pipeline_latency": elapsed}
    else:
        return {"sentence": None, "matches": None, "pipeline_latency": elapsed}
