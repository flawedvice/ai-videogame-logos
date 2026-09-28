from custom_types import Model, VocabularyVectors
from typing import Dict, List
import numpy as np
import logging
import whisper
import spacy


def get_nlp():
    """
    Loads SpaCy's NLP small English model.
    Returns a reference to said model.
    """
    nlp = spacy.load("en_core_web_sm")
    return nlp


AVAILABLE_MODELS: List[Model] = ["tiny", "base", "small", "medium"]


def get_listener(
    model: Model = "base",
):
    """
    Loads the Whisper model.
    Returns a reference to said model.
    """
    listener = whisper.load_model(model)
    return listener


def vectorize_vocabulary(
    vocabulary: Dict[str, List[str]], vectorizer: spacy.language.Language
):
    """
    Generates vector embeddings for recognizable vocabulary words.
    """
    vocabulary_vectors: VocabularyVectors = dict()
    unique_words = set()
    for category, words in vocabulary.items():
        unique_words.add(category)
        for w in words:
            unique_words.add(w)

    for word in unique_words:
        vector = np.asarray(vectorizer(word).vector, dtype=np.float32)
        vocabulary_vectors[word] = vector

    return vocabulary_vectors


def get_logger():
    """
    Custom logger for debugging and outputting information.
    """
    logging.basicConfig(
        level=logging.DEBUG,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )
    logger = logging.getLogger("game_logs")
    return logger
