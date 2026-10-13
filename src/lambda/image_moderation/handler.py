"""image_moderation: checks a generated image for unsafe/explicit content
with Amazon Rekognition's content moderation labels before it is returned
to the developer.
"""
import base64
import json
import os

import boto3

REGION = os.environ.get("REGION", "us-east-1")

rekognition = boto3.client(
    "rekognition",
    region_name=REGION,
    endpoint_url="http://localhost:4566",
    aws_access_key_id="test",
    aws_secret_access_key="test",
)


def lambda_handler(event, context):
    """Invoked directly by the coordinator Lambda (not through API Gateway).

    event = {"image_base64": "<base64-encoded generated image>"}
    returns {"flagged": bool, "moderation_score": float, "labels": [...]}
    """
    image_b64 = (event or {}).get("image_base64", "")
    if not image_b64:
        return {"flagged": False, "moderation_score": 0.0, "labels": []}

    image_bytes = base64.b64decode(image_b64)
    min_confidence = float(os.environ.get("MODERATION_CONFIDENCE_THRESHOLD", "70"))

    response = rekognition.detect_moderation_labels(
        Image={"Bytes": image_bytes},
        MinConfidence=min_confidence,
    )

    labels = [
        {"name": label.get("Name"), "confidence": label.get("Confidence", 0.0)}
        for label in response.get("ModerationLabels", [])
    ]
    moderation_score = max((label["confidence"] for label in labels), default=0.0)

    return {
        "flagged": len(labels) > 0,
        "moderation_score": moderation_score,
        "labels": labels,
    }


if __name__ == "__main__":
    sample = base64.b64encode(b"not-a-real-image").decode("utf-8")
    print(json.dumps(lambda_handler({"image_base64": sample}, None)))
