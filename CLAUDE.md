# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository contains kustomize manifests, example machine sets, app definitions and helper tooling for provisioning and testing MAAS (Model-as-a-Service) applications on Kubernetes clusters. It follows a GitOps pattern designed for use with ArgoCD.

## Key Commands

### Cluster Bootstrapping
```bash
# Bootstrap OpenShift GitOps and configure ArgoCD with cluster privileges
chmod +x tools/bootstrap-cluster.sh
./tools/bootstrap-cluster.sh
```

### Kustomize Operations
```bash
# Apply MAAS platform base
kubectl apply -k components/platform/maas/base

# Apply a machine-set (CAUTION: creates real machine resources)
kubectl apply -k components/platform/machine-set/base

# Apply example model applications
kubectl apply -k components/platform/public-models/base
```

### Client Example (Go)
```bash
# From client-example/golang-client/ directory
make build          # Build the binary
make test           # Run tests
make run            # Run the application
make clean          # Clean build artifacts
make lint           # Run linter (requires golangci-lint)
```

### API Testing
```bash
# Interactive curl cheatsheet for OpenShift/MAAS APIs
./client-example/curl-cheatsheet/curl_api_demo.sh
```

## Architecture

### Directory Structure
- `components/` - Reusable kustomize bases for apps and platform components
  - `platform/maas/base/` - Core MAAS platform manifests (RBAC, tier mappings, rate limits)
  - `platform/machine-set/base/` - Machine set manifests for node provisioning
  - `platform/public-models/base/` - Example model inference applications
  - `platform/users/base/` - User authentication manifests
- `clusters/` - Cluster-specific overlays and ArgoCD app-of-apps configurations
  - `ocpai3-aws/` - Example cluster overlay with ArgoCD Application manifests
- `tools/` - Helper scripts for cluster bootstrapping and automation

### Key Components
- **MAAS Platform**: Provides tier-to-group mappings, rate limiting policies, and RBAC for model access control
- **Machine Sets**: Declarative machine provisioning using 4xlarge-machine-set.yaml template
- **LLMInferenceService**: Custom resources for deploying ML models via KServe API (serving.kserve.io/v1alpha1)
- **ArgoCD Integration**: App-of-apps pattern with repository configuration for GitOps workflows

### Model Deployment Pattern
Models are deployed as LLMInferenceService resources with:
- Tier-based access control via annotations (alpha.maas.opendatahub.io/tiers)
- Gateway routing through maas-default-gateway
- SSL/TLS termination
- Health probes and container specifications

## Configuration Points

When adapting this codebase:
- Machine sizes/flavors: `components/platform/machine-set/base/4xlarge-machine-set.yaml`
- Model images/specs: LLM inference YAML files in platform components
- User accounts: `components/platform/users/base/users.htpasswd`
- Cluster-specific settings: overlays in `clusters/ocpai3-aws/`
- Repository URL: Update in `clusters/appofapps-repository-config.yaml`

## Safety Notes

- Machine set manifests will create real infrastructure resources in MAAS
- Bootstrap script grants cluster-admin privileges to ArgoCD
- Always inspect scripts before execution
- Test in non-production environments first

## Prerequisites

- MAAS environment with API access
- Kubernetes cluster with machine provisioning capability  
- `kubectl` and `kustomize` installed
- OpenShift CLI (`oc`) for OpenShift clusters
- `jq` for JSON processing in scripts