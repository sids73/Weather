kubectl -n weather create configmap weather-site --from-file=index.html="$(CDPATH= cd -- "$(dirname -- "$0")/../src" && pwd)/weather.html" \
  --dry-run=client -o yaml | kubectl apply -f -