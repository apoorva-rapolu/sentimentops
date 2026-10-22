IMAGE ?= sentimentops-app:local
PORT  ?= 9000
URL   := http://localhost:$(PORT)/2015-03-31/functions/function/invocations

.PHONY: install test build run-local stop invoke-health invoke-predict invoke-bad

install:            ## install dev dependencies (run once)
	pip install -r requirements-dev.txt

test:               ## unit tests, no AWS access needed
	python -m pytest -q tests

build:              ## build the Lambda container image
	docker build --platform linux/amd64 -t $(IMAGE) .

run-local: build    ## run the image with the built-in Lambda Runtime Interface Emulator
	docker run --rm -d --name sentimentops-local -p $(PORT):8080 \
		-e MODEL_VERSION=vader-local -e LOG_LEVEL=INFO $(IMAGE)
	@echo "Running. Try: make invoke-predict"

stop:
	docker stop sentimentops-local

invoke-health:
	curl -s $(URL) -d @events/health.json; echo

invoke-predict:
	curl -s $(URL) -d @events/predict.json; echo

invoke-bad:
	curl -s $(URL) -d @events/bad_request.json; echo
