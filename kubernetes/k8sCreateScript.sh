#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

kubectl apply -f "$SCRIPT_DIR/weather-k8s.yaml"
kubectl -n weather create configmap weather-site \
  --from-file=index.html="$SCRIPT_DIR/../src/weather.html" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n weather rollout status deployment/weather --timeout=120s
kubectl -n weather get svc weather