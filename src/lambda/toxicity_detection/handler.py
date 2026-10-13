"""toxicity_detection: detects toxic content in the user-supplied prompt with
Amazon Comprehend before it is ever used to generate an image.
"""
import json
import os

import boto3

REGION = os.environ.get("REGION", "us-east-1")

comprehend = boto3.client(
    "comprehend",
    region_name=REGION,
    endpoint_url="http://localhost:4566",
    aws_access_key_id="test",
    aws_secret_access_key="test",
)


def lambda_handler(event, context):
    """Invoked directly by the coordinator Lambda (not through API Gateway).

    event = {"text": "<prompt>"}
    returns {"toxic": bool, "toxicity_score": float, "labels": [...]}
    """
    text = (event or {}).get("text", "").strip()
    if not text:
        return {"toxic": False, "toxicity_score": 0.0, "labels": []}

    response = comprehend.detect_toxic_content(
        TextSegments=[{"Text": text}],
        LanguageCode="en",
    )

    labels = []
    toxicity_score = 0.0
    for result in response.get("ResultList", []):
        for label in result.get("Labels", []):
            labels.append({"name": label.get("Name"), "score": label.get("Score", 0.0)})
            toxicity_score = max(toxicity_score, label.get("Score", 0.0))

    return {
        "toxic": toxicity_score >= float(os.environ.get("TOXICITY_THRESHOLD", "0.5")),
        "toxicity_score": toxicity_score,
        "labels": labels,
    }


if __name__ == "__main__":
    print(json.dumps(lambda_handler({"text": "a friendly red fox in a forest"}, None)))
