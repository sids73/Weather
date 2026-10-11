#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KUBERNETES_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
KUSTOMIZE_DIR="$KUBERNETES_DIR/base"
if [[ -d "$KUBERNETES_DIR/local" ]]; then
  KUSTOMIZE_DIR="$KUBERNETES_DIR/local"
fi

printf 'Applying Kustomize configuration from %s\n' "$KUSTOMIZE_DIR"
kubectl apply -k "$KUSTOMIZE_DIR"
kubectl -n weather create configmap weather-site \
  --from-file=index.html="$KUBERNETES_DIR/../src/weather.html" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n weather rollout status deployment/weather --timeout=120s
kubectl -n weather get svc weather