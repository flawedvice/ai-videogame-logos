from typing import Literal, Union, Dict, List, TypedDict, Tuple, Annotated
from numpy.typing import NDArray
import numpy as np

Model = Annotated[
    Union[Literal["tiny"], Literal["base"], Literal["small"], Literal["medium"]],
    "Whisper models available",
]

""" type Vocabulary = Dict[Union[Literal["actions"], Literal["descriptors"]], List[str]] """
type Vocabulary = Dict[str, List[str]]

type VocabularyVectors = Dict[str, NDArray[np.float32]]

type Elapsed = Dict[
    Union[
        Literal["overall"], Literal["listen"], Literal["filter"], Literal["normalize"]
    ],
    float,
]


NormalizedMatches = Annotated[
    List[Tuple[str, str, str]],
    "Normalized tuples of normalized word, original vocabulary counterpart, and how it matched.",
]


class PipelineResponse(TypedDict):
    """
    sentence: Whole sentence detected by Whisper. Might be None.
    matches: List of tuples, where each tuple represents the normalized game keyword and the actual match. Might be None.
    pipeline_latency: Elapsed time in seconds for every step of the pipeline.
    """

    sentence: Union[str, None]
    matches: Union[NormalizedMatches, None]
    pipeline_latency: Elapsed
