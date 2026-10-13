"""Generates docs/architecture.drawio for the Generative AI Content Moderator
project using drawpyo.

Run with: python3 scripts/generate_diagram.py

Uses AWS4 shapes that ship natively with every draw.io/diagrams.net renderer
(desktop, web, VS Code and GitHub's built-in .drawio viewer), so no external
shape library needs to be downloaded to open the file.
"""
import os

import drawpyo

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")

AWS4_BASE = (
    "sketch=0;outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;"
    "dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;"
    "fontSize=11;fontStyle=0;aspect=fixed;pointerEvents=1;"
)

GENERIC_BOX_STYLE = (
    "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFF2CC;strokeColor=#D6B656;"
    "fontSize=10;fontColor=#7F6000;align=center;"
)


def aws_style(icon_name, fill_color):
    """Builds an AWS4 resourceIcon style string."""
    return f"{AWS4_BASE}fillColor={fill_color};shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{icon_name};"


def add_node(page, name, x, y, icon_name, fill_color, width=64, height=64):
    node = drawpyo.diagram.Object(page=page, value=name)
    node.position = (x, y)
    node.geometry.width = width
    node.geometry.height = height
    node.apply_style_string(aws_style(icon_name, fill_color))
    return node


def add_generic_box(page, name, x, y, width=120, height=64):
    node = drawpyo.diagram.Object(page=page, value=name)
    node.position = (x, y)
    node.geometry.width = width
    node.geometry.height = height
    node.apply_style_string(GENERIC_BOX_STYLE)
    return node


def add_edge(page, source, target, label=None):
    edge = drawpyo.diagram.Edge(page=page, source=source, target=target, label=label)
    edge.waypoints = "orthogonal"
    edge.endArrow = "block"
    edge.startArrow = "none"
    edge.strokeColor = "#545B64"
    return edge


def build_diagram():
    file = drawpyo.File()
    file.file_name = "architecture.drawio"
    file.file_path = OUTPUT_DIR

    page = drawpyo.Page(file=file)
    page.name = "Generative AI Content Moderator"

    developer = add_node(page, "Developer", 40, 260, "client", "#232F3E")

    distribute_content = add_generic_box(page, "Distribute content\n(CDN)", 220, 260)
    web_app = add_node(page, "Web app", 400, 260, "client", "#232F3E")
    static_web_app = add_node(page, "Static web app\n(S3)", 220, 420, "bucket", "#7AA116")

    rest_api = add_node(page, "REST API\n(API Gateway)", 580, 260, "api_gateway", "#E7157B")
    coordinator = add_node(
        page, "Coordinates AWS\nAI services\n(Lambda)", 760, 260, "lambda_function", "#ED7100"
    )

    image_moderation = add_node(
        page, "Image moderation\n(Rekognition)", 960, 140, "rekognition_2", "#01A88D"
    )
    toxicity_detection = add_node(
        page, "Toxicity detection\n(Comprehend)", 960, 380, "machine_learning", "#01A88D"
    )

    model_endpoint = add_node(
        page, "Model endpoint", 760, 460, "machine_learning", "#01A88D"
    )
    pre_built_ml = add_generic_box(page, "Pre-built ML solutions\n(Stable Diffusion model)", 940, 540)

    add_edge(page, developer, web_app, "Interacts with")
    add_edge(page, web_app, distribute_content, "Get web app assets / content")
    add_edge(page, distribute_content, static_web_app)

    add_edge(page, web_app, rest_api, "Prompt to create an image")
    add_edge(page, rest_api, coordinator, "Invoke / Moderated image")

    add_edge(page, coordinator, image_moderation, "Check generated image")
    add_edge(page, image_moderation, coordinator, "Updates toxic score")

    add_edge(page, coordinator, toxicity_detection, "Detect toxic content")
    add_edge(page, toxicity_detection, coordinator, "Updates toxic score")

    add_edge(page, coordinator, model_endpoint, "Run inferences")
    add_edge(page, model_endpoint, pre_built_ml, "Deploys")
    add_edge(page, pre_built_ml, coordinator, "Generated image (text prompt)")

    add_edge(page, rest_api, web_app, "Returns moderated image")

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    file.write()
    print(f"Wrote {os.path.join(OUTPUT_DIR, file.file_name)}")


if __name__ == "__main__":
    build_diagram()
