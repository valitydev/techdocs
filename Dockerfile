FROM docker.io/alpine:3.17

RUN apk update && apk add \
    plantuml \
    graphviz \
    fontconfig \
    font-opensans \
    python3 \
    py3-pip

RUN pip install \
    mkdocs \
    mkdocs-material \
    pymdown-extensions \
    plantuml-markdown \
    mkdocs-autolinks-plugin \
    mkdocs-htmlproofer-plugin

RUN mkdir -p /workspace
WORKDIR /workspace

CMD mkdocs build
