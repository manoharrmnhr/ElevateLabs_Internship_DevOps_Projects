# ─────────────────────────────────────────────────────────────────
#  Makefile — Common development & deployment commands
#  Usage: make <target>
# ─────────────────────────────────────────────────────────────────

DOCKERHUB_USER ?= YOUR_DOCKERHUB_USERNAME
IMAGE          := $(DOCKERHUB_USER)/cicd-flask-app
TAG            := latest

.PHONY: help install lint test build run push deploy clean stop logs

help:  ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

install:  ## Install Python dependencies
	pip install -r app/requirements.txt

lint:  ## Run flake8 linter
	flake8 app/ --max-line-length=100
	black --check --line-length 100 app/

test:  ## Run pytest with coverage
	pytest app/tests/ --tb=short -v --cov=app --cov-report=term-missing

build:  ## Build Docker image locally
	docker build -t $(IMAGE):$(TAG) .

run:  ## Run app via Docker Compose
	docker-compose up --build

stop:  ## Stop Docker Compose services
	docker-compose down

push:  ## Push image to Docker Hub
	docker push $(IMAGE):$(TAG)

deploy:  ## Deploy to local Minikube
	bash scripts/deploy-local.sh $(DOCKERHUB_USER)

logs:  ## Tail Kubernetes pod logs
	kubectl logs -l app=cicd-flask-app --follow

clean:  ## Remove local Docker images and stop Minikube
	docker-compose down --rmi local
	minikube stop
