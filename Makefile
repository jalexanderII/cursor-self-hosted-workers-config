SHELL := /bin/bash

-include .env
export

AWS_PROFILE ?= default
AWS_REGION ?= us-east-1
AWS_ACCOUNT_ID_RESOLVED := $(if $(AWS_ACCOUNT_ID),$(AWS_ACCOUNT_ID),$(shell aws sts get-caller-identity --profile "$(AWS_PROFILE)" --query Account --output text 2>/dev/null))
ECR_REPOSITORY_NAME ?= cursor-self-hosted-worker
WORKER_IMAGE_TAG ?= latest
WORKER_PLATFORM ?= linux/amd64
ECR_REGISTRY := $(AWS_ACCOUNT_ID_RESOLVED).dkr.ecr.$(AWS_REGION).amazonaws.com
ECR_WORKER_IMAGE := $(ECR_REGISTRY)/$(ECR_REPOSITORY_NAME):$(WORKER_IMAGE_TAG)

EC2_TF_DIR ?= terraform/examples/ec2-asg
EKS_CLUSTER_TF_DIR ?= terraform/examples/eks-new-cluster
EKS_WORKERS_TF_DIR ?= terraform/examples/eks-existing-cluster
K8S_NAMESPACE ?= cursord
WORKER_DEPLOYMENT_NAME ?= cursor-workers
CURSOR_API_KEY_SECRET_NAME ?= cursor-workers-api-key
GITHUB_PAT_SECRET_NAME ?= cursor-workers-github

.PHONY: help \
	ecr-login ecr-build-push \
	put-secret-cursor-api-key put-secret-github-pat \
	ec2-init ec2-plan ec2-apply ec2-validate \
	eks-cluster-init eks-cluster-plan eks-cluster-apply eks-cluster-validate \
	eks-workers-init eks-workers-plan eks-workers-apply eks-workers-validate \
	kube-create-api-key-secret kube-create-github-secret kube-apply-rendered kube-status \
	terraform-fmt terraform-validate-all

help:
	@echo "Targets:"
	@echo "  ecr-build-push              Build and push kube/worker-image to ECR"
	@echo "  put-secret-cursor-api-key   Store CURSOR_API_KEY in AWS Secrets Manager"
	@echo "  put-secret-github-pat       Store GITHUB_PAT in AWS Secrets Manager"
	@echo "  ec2-init|plan|apply         Manage the EC2 ASG Terraform example"
	@echo "  eks-cluster-init|plan|apply Manage the optional new EKS cluster example"
	@echo "  eks-workers-init|plan|apply Manage workers on an existing EKS cluster"
	@echo "  kube-create-*-secret        Copy local secrets into Kubernetes Secrets"
	@echo "  kube-apply-rendered         Apply Terraform-rendered WorkerDeployment YAML"
	@echo "  terraform-fmt               Format all Terraform files"
	@echo "  terraform-validate-all      Validate all Terraform examples"

ecr-login:
	@if [[ -z "$(AWS_ACCOUNT_ID_RESOLVED)" ]]; then echo "AWS_ACCOUNT_ID or AWS CLI auth is required."; exit 1; fi
	aws ecr get-login-password --profile "$(AWS_PROFILE)" --region "$(AWS_REGION)" \
		| docker login --username AWS --password-stdin "$(ECR_REGISTRY)"

ecr-build-push: ecr-login
	docker buildx build \
		--platform "$(WORKER_PLATFORM)" \
		-f kube/worker-image/Dockerfile \
		-t "$(ECR_WORKER_IMAGE)" \
		--push \
		kube/worker-image
	@echo "Pushed $(ECR_WORKER_IMAGE)"

put-secret-cursor-api-key:
	@if [[ -z "$${CURSOR_API_KEY:-}" ]]; then echo "CURSOR_API_KEY must be set in .env or the shell."; exit 1; fi
	aws secretsmanager put-secret-value \
		--profile "$(AWS_PROFILE)" \
		--region "$(AWS_REGION)" \
		--secret-id "$${CURSOR_API_SECRET_ID:-cursor/self-hosted-workers/cursor-api-key}" \
		--secret-string "$${CURSOR_API_KEY}" >/dev/null
	@echo "Updated Cursor API key secret."

put-secret-github-pat:
	@if [[ -z "$${GITHUB_PAT:-}" ]]; then echo "GITHUB_PAT must be set in .env or the shell."; exit 1; fi
	aws secretsmanager put-secret-value \
		--profile "$(AWS_PROFILE)" \
		--region "$(AWS_REGION)" \
		--secret-id "$${GITHUB_PAT_SECRET_ID:-cursor/self-hosted-workers/github-pat}" \
		--secret-string "$${GITHUB_PAT}" >/dev/null
	@echo "Updated GitHub PAT secret."

ec2-init:
	terraform -chdir="$(EC2_TF_DIR)" init

ec2-plan:
	terraform -chdir="$(EC2_TF_DIR)" plan

ec2-apply:
	terraform -chdir="$(EC2_TF_DIR)" apply

ec2-validate:
	terraform -chdir="$(EC2_TF_DIR)" validate

eks-cluster-init:
	terraform -chdir="$(EKS_CLUSTER_TF_DIR)" init

eks-cluster-plan:
	terraform -chdir="$(EKS_CLUSTER_TF_DIR)" plan

eks-cluster-apply:
	terraform -chdir="$(EKS_CLUSTER_TF_DIR)" apply

eks-cluster-validate:
	terraform -chdir="$(EKS_CLUSTER_TF_DIR)" validate

eks-workers-init:
	terraform -chdir="$(EKS_WORKERS_TF_DIR)" init

eks-workers-plan:
	terraform -chdir="$(EKS_WORKERS_TF_DIR)" plan

eks-workers-apply:
	terraform -chdir="$(EKS_WORKERS_TF_DIR)" apply

eks-workers-validate:
	terraform -chdir="$(EKS_WORKERS_TF_DIR)" validate

kube-create-api-key-secret:
	@if [[ -z "$${CURSOR_API_KEY:-}" ]]; then echo "CURSOR_API_KEY must be set in .env or the shell."; exit 1; fi
	kubectl create namespace "$(K8S_NAMESPACE)" --dry-run=client -o yaml | kubectl apply -f -
	kubectl create secret generic "$(CURSOR_API_KEY_SECRET_NAME)" \
		--from-literal=api-key="$${CURSOR_API_KEY}" \
		-n "$(K8S_NAMESPACE)" \
		--dry-run=client -o yaml | kubectl apply -f -
	kubectl label secret "$(CURSOR_API_KEY_SECRET_NAME)" \
		-n "$(K8S_NAMESPACE)" \
		"workers.cursor.com/worker-deployment=$(WORKER_DEPLOYMENT_NAME)" \
		--overwrite

kube-create-github-secret:
	@if [[ -z "$${GITHUB_PAT:-}" ]]; then echo "GITHUB_PAT must be set in .env or the shell."; exit 1; fi
	kubectl create namespace "$(K8S_NAMESPACE)" --dry-run=client -o yaml | kubectl apply -f -
	kubectl create secret generic "$(GITHUB_PAT_SECRET_NAME)" \
		--from-literal=pat="$${GITHUB_PAT}" \
		-n "$(K8S_NAMESPACE)" \
		--dry-run=client -o yaml | kubectl apply -f -

kube-apply-rendered:
	kubectl apply -f "$(EKS_WORKERS_TF_DIR)/rendered/workers.yaml"

kube-status:
	kubectl get workerdeployments,pods -n "$(K8S_NAMESPACE)"

terraform-fmt:
	terraform fmt -recursive terraform

terraform-validate-all: ec2-validate eks-cluster-validate eks-workers-validate
