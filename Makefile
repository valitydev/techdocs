IMAGE_TAG := techdocs-dev
DOCKER ?= docker
DOCKER_BUILD_OPTIONS ?=

image:
	$(DOCKER) build -t "$(IMAGE_TAG)" $(DOCKER_BUILD_OPTIONS) .

build: image
	$(DOCKER) run -v $(PWD):/workspace "$(IMAGE_TAG):latest"

serve: image
	$(DOCKER) run -v $(PWD):/workspace -p 8000:8000 "$(IMAGE_TAG):latest" serve -a 0.0.0.0:8000
