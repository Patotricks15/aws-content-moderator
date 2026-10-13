"""coordinator (Coordinates AWS AI services): the REST API's entry point.

Flow:
1. detect toxic content in the user's text prompt by invoking the
   toxicity_detection Lambda (Amazon Comprehend), updating the running
   toxic score — if the prompt itself is toxic, the request is blocked
   before any image is generated;
2. invoke the Stable Diffusion model endpoint (pre-built ML solution running
   on a SageMaker-style inference endpoint) to generate an image from the
   prompt;
3. check the generated image for unsafe content by invoking the
   image_moderation Lambda (Amazon Rekognition), updating the toxic score
   again;
4. if both checks pass, return the generated (moderated) image back through
   the REST API to the web app; otherwise return a blocked response.
"""
import base64
import json
import os

import boto3

REGION = os.environ.get("REGION", "us-east-1")
TOXICITY_DETECTION_FUNCTION_NAME = os.environ["TOXICITY_DETECTION_FUNCTION_NAME"]
IMAGE_MODERATION_FUNCTION_NAME = os.environ["IMAGE_MODERATION_FUNCTION_NAME"]
MODEL_ENDPOINT_NAME = os.environ["MODEL_ENDPOINT_NAME"]

lambda_client = boto3.client(
    "lambda",
    region_name=REGION,
    endpoint_url="http://localhost:4566",
    aws_access_key_id="test",
    aws_secret_access_key="test",
)

sagemaker_runtime = boto3.client(
    "sagemaker-runtime",
    region_name=REGION,
    endpoint_url="http://localhost:4566",
    aws_access_key_id="test",
    aws_secret_access_key="test",
)


def _invoke(function_name, payload):
    response = lambda_client.invoke(
        FunctionName=function_name,
        InvocationType="RequestResponse",
        Payload=json.dumps(payload).encode("utf-8"),
    )
    return json.loads(response["Payload"].read())


def _generate_image(prompt):
    """Calls the Stable Diffusion model endpoint to run inference on the prompt."""
    response = sagemaker_runtime.invoke_endpoint(
        EndpointName=MODEL_ENDPOINT_NAME,
        ContentType="application/json",
        Accept="application/json",
        Body=json.dumps({"text_prompts": [{"text": prompt}]}),
    )
    payload = json.loads(response["Body"].read())
    return payload.get("generated_image_base64", "")


def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "Request body must be valid JSON."})

    prompt = body.get("prompt")
    if not prompt:
        return _response(400, {"error": "'prompt' is required."})

    toxic_score = 0.0

    # Step 1: toxicity detection on the text prompt (Amazon Comprehend).
    toxicity_result = _invoke(TOXICITY_DETECTION_FUNCTION_NAME, {"text": prompt})
    toxic_score = max(toxic_score, toxicity_result.get("toxicity_score", 0.0))

    if toxicity_result.get("toxic"):
        return _response(
            422,
            {
                "blocked": True,
                "reason": "toxic_prompt",
                "toxic_score": toxic_score,
                "details": toxicity_result.get("labels", []),
            },
        )

    # Step 2: run inference on the Stable Diffusion model endpoint.
    generated_image_base64 = _generate_image(prompt)

    # Step 3: image moderation on the generated image (Amazon Rekognition).
    moderation_result = _invoke(
        IMAGE_MODERATION_FUNCTION_NAME, {"image_base64": generated_image_base64}
    )
    toxic_score = max(toxic_score, moderation_result.get("moderation_score", 0.0) / 100.0)

    if moderation_result.get("flagged"):
        return _response(
            422,
            {
                "blocked": True,
                "reason": "unsafe_image",
                "toxic_score": toxic_score,
                "details": moderation_result.get("labels", []),
            },
        )

    # Step 4: both checks passed — return the moderated image to the web app.
    return _response(
        200,
        {
            "blocked": False,
            "prompt": prompt,
            "toxic_score": toxic_score,
            "image_base64": generated_image_base64,
        },
    )


def _response(status_code, payload):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(payload),
    }
