"""Sentiment model wrapper.

The rest of the app only calls `predict(text)` and reads `MODEL_NAME`.
To swap VADER for DistilBERT later, change only this file — the handler,
the API contract and the frontend stay the same.
"""

from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer

MODEL_NAME = "vader"

# VADER's standard thresholds on the compound score (-1 .. +1).
POSITIVE_THRESHOLD = 0.05
NEGATIVE_THRESHOLD = -0.05

# Loaded once per Lambda container (at cold start), then reused.
_analyzer = SentimentIntensityAnalyzer()


def predict(text: str) -> tuple[str, float]:
    """Return (label, score).

    label: "POSITIVE" | "NEGATIVE" | "NEUTRAL"  (always uppercase, per contract)
    score: 0.0 .. 1.0, how strongly the text leans towards that label.
    """
    compound = _analyzer.polarity_scores(text)["compound"]

    if compound >= POSITIVE_THRESHOLD:
        label, score = "POSITIVE", abs(compound)
    elif compound <= NEGATIVE_THRESHOLD:
        label, score = "NEGATIVE", abs(compound)
    else:
        # Close to zero = confidently neutral.
        label, score = "NEUTRAL", 1.0 - abs(compound)

    return label, round(score, 4)
