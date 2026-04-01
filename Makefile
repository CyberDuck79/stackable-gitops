SHELL := /bin/bash
.DEFAULT_GOAL := help

SEALED_SECRETS_NS     := sealed-secrets
SEALED_SECRETS_NAME   := sealed-secrets-controller
CERT                  := tls.crt

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} \
	  /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# ─── Cluster bootstrap ────────────────────────────────────────────────────────

.PHONY: cluster
cluster: ## Create the local kind cluster
	kind create cluster --name stackable --config bootstrap/kind-config.yaml

.PHONY: argocd
argocd: ## Install ArgoCD and configure it
	bash bootstrap/argocd-install.sh

.PHONY: bootstrap
bootstrap: cluster argocd ## Create cluster and install ArgoCD (combines cluster + argocd)

# ─── Secret management ────────────────────────────────────────────────────────

.PHONY: fetch-cert
fetch-cert: ## Fetch the sealed-secrets public cert from the cluster → tls.crt
	kubeseal --fetch-cert \
	  --controller-name $(SEALED_SECRETS_NAME) \
	  --controller-namespace $(SEALED_SECRETS_NS) \
	  > $(CERT)
	@echo "Cert saved to $(CERT)"

.PHONY: seal-secrets
seal-secrets: $(CERT) ## Generate all SealedSecrets from secrets-templates/
	CERT=$(CERT) bash scripts/generate-sealed-secrets.sh

$(CERT):
	@echo "$(CERT) not found. Run 'make fetch-cert' first."
	@exit 1

# ─── ArgoCD deployment ────────────────────────────────────────────────────────

.PHONY: deploy
deploy: ## Apply the ArgoCD Project and bootstrap the App of Apps
	kubectl apply -f argocd/projects/data-platform.yaml
	kubectl apply -f argocd/apps/app-of-apps.yaml
	@echo ""
	@echo "ArgoCD is now syncing the data platform."
	@echo "Monitor progress: argocd app list"
	@echo "UI: http://localhost:30080"

.PHONY: sync
sync: ## Force-sync all ArgoCD applications
	argocd app sync data-platform --async
	argocd app wait data-platform --sync

# ─── Teardown ─────────────────────────────────────────────────────────────────

.PHONY: destroy
destroy: ## Delete the kind cluster (irreversible!)
	kind delete cluster --name stackable
