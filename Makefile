SHELL := /bin/bash

-include .env
export AWS_PROFILE AWS_REGION AWS_ACCOUNT_ID DEPLOYMENT_NAME ENVIRONMENT
export ECR_REPOSITORY_NAME WORKER_IMAGE_TAG WORKER_PLATFORM
export EC2_TF_DIR EKS_CLUSTER_TF_DIR EKS_WORKERS_TF_DIR
export K8S_NAMESPACE WORKER_DEPLOYMENT_NAME CURSOR_API_KEY_SECRET_NAME SCM_TOKEN_SECRET_NAME
export $(filter TF_VAR_%,$(.VARIABLES))

AWS_PROFILE ?= default
AWS_REGION ?= us-east-1
AWS_ACCOUNT_ID_RESOLVED := $(if $(AWS_ACCOUNT_ID),$(AWS_ACCOUNT_ID),$(shell aws sts get-caller-identity --profile "$(AWS_PROFILE)" --query Account --output text 2>/dev/null))
ECR_REPOSITORY_NAME ?= cursor-self-hosted-worker
WORKER_IMAGE_TAG ?= dev-$(shell git rev-parse --short HEAD 2>/dev/null || echo local)
WORKER_PLATFORM ?= linux/amd64
ECR_REGISTRY := $(AWS_ACCOUNT_ID_RESOLVED).dkr.ecr.$(AWS_REGION).amazonaws.com
ECR_WORKER_IMAGE := $(ECR_REGISTRY)/$(ECR_REPOSITORY_NAME):$(WORKER_IMAGE_TAG)

EC2_TF_DIR ?= terraform/examples/ec2-asg
EKS_CLUSTER_TF_DIR ?= terraform/examples/eks-new-cluster
EKS_WORKERS_TF_DIR ?= terraform/examples/eks-existing-cluster
K8S_NAMESPACE ?= cursord
WORKER_DEPLOYMENT_NAME ?= cursor-workers
CURSOR_API_KEY_SECRET_NAME ?= cursor-workers-api-key
SCM_TOKEN_SECRET_NAME ?= cursor-workers-scm

.PHONY: help \
	ecr-login ecr-build-push \
	put-secret-cursor-api-key put-secret-scm-token \
	ec2-init ec2-plan ec2-apply ec2-validate \
	eks-cluster-init eks-cluster-plan eks-cluster-apply eks-cluster-validate \
	eks-workers-init eks-workers-plan eks-workers-apply eks-workers-validate \
	kube-create-api-key-secret kube-create-scm-secret kube-apply-rendered kube-status \
	terraform-fmt terraform-validate-all test lint check

help:
	@echo "Targets:"
	@echo "  ecr-build-push              Build and push kube/worker-image to ECR"
	@echo "  put-secret-cursor-api-key   Store CURSOR_API_KEY in AWS Secrets Manager"
	@echo "  put-secret-scm-token        Store SCM_TOKEN in AWS Secrets Manager"
	@echo "  ec2-init|plan|apply         Manage the EC2 ASG Terraform example"
	@echo "  eks-cluster-init|plan|apply Manage the optional new EKS cluster example"
	@echo "  eks-workers-init|plan|apply Manage workers on an existing EKS cluster"
	@echo "  kube-create-*-secret        Copy local secrets into Kubernetes Secrets"
	@echo "  kube-apply-rendered         Apply Terraform-rendered WorkerDeployment YAML"
	@echo "  terraform-fmt               Format all Terraform files"
	@echo "  terraform-validate-all      Validate all Terraform examples"
	@echo "  test|lint|check             Run repository validation"

ecr-login:
	@if [[ -z "$(AWS_ACCOUNT_ID_RESOLVED)" ]]; then echo "AWS_ACCOUNT_ID or AWS CLI auth is required."; exit 1; fi
	aws ecr get-login-password --profile "$(AWS_PROFILE)" --region "$(AWS_REGION)" \
		| docker login --username AWS --password-stdin "$(ECR_REGISTRY)"

ecr-build-push: ecr-login
	docker buildx build \
		--platform "$(WORKER_PLATFORM)" \
		-f kube/worker-image/Dockerfile \
		--build-arg BUILD_DATE="$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		--build-arg VCS_REF="$$(git rev-parse HEAD)" \
		--build-arg VERSION="$(WORKER_IMAGE_TAG)" \
		--provenance=mode=max \
		--sbom=true \
		-t "$(ECR_WORKER_IMAGE)" \
		--push \
		kube/worker-image
	@echo "Pushed $(ECR_WORKER_IMAGE)"

put-secret-cursor-api-key:
	@if [[ -z "$${CURSOR_API_KEY:-}" ]]; then echo "CURSOR_API_KEY must be supplied in the invoking shell."; exit 1; fi
	@printf '%s' "$${CURSOR_API_KEY}" | scripts/put-secret-value.sh "$${CURSOR_API_SECRET_ID:-cursor/self-hosted-workers/cursor-api-key}"

put-secret-scm-token:
	@if [[ -z "$${SCM_TOKEN:-}" ]]; then echo "SCM_TOKEN must be supplied in the invoking shell."; exit 1; fi
	@printf '%s' "$${SCM_TOKEN}" | scripts/put-secret-value.sh "$${SCM_TOKEN_SECRET_ID:-cursor/self-hosted-workers/scm-token}"

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
	@if [[ -z "$${CURSOR_API_KEY:-}" ]]; then echo "CURSOR_API_KEY must be supplied in the invoking shell."; exit 1; fi
	@printf '%s' "$${CURSOR_API_KEY}" | scripts/create-k8s-secret.sh \
		"$(K8S_NAMESPACE)" "$(CURSOR_API_KEY_SECRET_NAME)" api-key "$(WORKER_DEPLOYMENT_NAME)"

kube-create-scm-secret:
	@if [[ -z "$${SCM_TOKEN:-}" ]]; then echo "SCM_TOKEN must be supplied in the invoking shell."; exit 1; fi
	@printf '%s' "$${SCM_TOKEN}" | scripts/create-k8s-secret.sh \
		"$(K8S_NAMESPACE)" "$(SCM_TOKEN_SECRET_NAME)" token

kube-apply-rendered:
	kubectl apply -f "$(EKS_WORKERS_TF_DIR)/rendered/workers.yaml"

kube-status:
	kubectl get workerdeployments,pods -n "$(K8S_NAMESPACE)"

terraform-fmt:
	terraform fmt -recursive terraform

terraform-validate-all:
	scripts/validate.sh

test:
	python3 -m unittest discover -s tests -p 'test_*.py'

lint:
	scripts/validate.sh

check: lint
