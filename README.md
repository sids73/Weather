# Weather dashboard

A lightweight, responsive weather dashboard for Delaware, Ohio; Mumbai, India;
and Mangalore, India. The application is a single HTML file with inline CSS and
JavaScript, served by nginx on Kubernetes. No application build step, custom
container image, or API keys are needed for the current implementation.

## Features and data sources

- **Delaware:** National Weather Service observations, alerts, hourly and daily
  forecasts, sun times, and the Wilmington (KILN) radar loop.
- **Mumbai and Mangalore:** Open-Meteo current conditions, hourly and seven-day
  forecasts, sunrise/sunset, UV index, and optional US AQI data. Links to the
  India Meteorological Department provide additional warning/radar information;
  these tabs do not include an automatic alert feed.
- Responsive layout, automatic light/dark styling, and remembered location
  selection using browser local storage.
- Delaware temperatures use Fahrenheit; Indian locations use Celsius.

Weather API requests and radar downloads happen **in the browser**, not in nginx.
Each device needs internet access to the providers. There is no server-side
generator, backend API, or offline weather cache.

### Refresh behavior

| Data | Refresh interval |
| --- | --- |
| Delaware alerts and radar | 5 minutes |
| Delaware observations | 10 minutes |
| Delaware hourly and daily forecasts | 30 minutes |
| Mumbai/Mangalore weather and AQI | 30 minutes, starting when the tab is first opened |

Delaware point metadata is cached in local storage for up to 24 hours. API
requests retry transient network errors, HTTP 429, and server errors; scheduled
panel failures display an error and retry after one minute. AQI is optional and
is omitted if its request fails.

For Delaware's current conditions, the page checks the **three closest NWS
stations** and chooses the newest timestamp with a temperature reading. It does
not search all stations or enforce a maximum observation age. Check the
displayed observation time and station when comparing readings. If any of those
station requests fails after retries, the current-conditions update fails rather
than silently ignoring the station.

## Project layout

| File | Purpose |
| --- | --- |
| [src/weather.html](src/weather.html) | Dashboard markup, styles, API calls, and rendering |
| [kubernetes/base/weather-k8s.yaml](kubernetes/base/weather-k8s.yaml) | Kubernetes resources and nginx configuration |
| [kubernetes/base/kustomization.yaml](kubernetes/base/kustomization.yaml) | Shared Kustomize base |
| `kubernetes/local/kustomization.yaml` (Git-ignored) | Optional LAN-specific Service IP override |
| [kubernetes/scripts/k8sCreateScript.sh](kubernetes/scripts/k8sCreateScript.sh) | Initial deployment and repeatable manifest application |
| [kubernetes/scripts/k8sUpdateScript.sh](kubernetes/scripts/k8sUpdateScript.sh) | Update the deployed HTML ConfigMap only |

## Local preview

Open [src/weather.html](src/weather.html) in a modern browser with JavaScript
enabled. No build or dependency installation is required. If the browser
restricts API calls from local files, serve the file with a local static HTTP
server. Browser developer tools show provider request errors.

## Kubernetes prerequisites

> **Load balancer assumption:** The external-access and IP-pinning instructions
> below assume MetalLB 0.14 or newer. The shared `type: LoadBalancer` Service can
> also work with other Kubernetes load balancer implementations, but the
> `metallb.io/loadBalancerIPs` annotation is MetalLB-specific and is not a
> portable way to reserve an address.
>
> For a different implementation, follow its documentation for provisioning a
> load balancer and requesting a static address, and adapt the local Kustomize
> overlay accordingly. This may require provider-specific annotations or
> reserving an address outside Kubernetes; some providers return a hostname
> instead of an IP. Adapt the verification commands accordingly. Without a
> load balancer controller, external access can remain pending; port forwarding
> below is available for testing.

- A Kubernetes cluster and `kubectl` configured with permissions to manage the
  resources in this manifest, including the `weather` Namespace.
- Bash to run the deployment scripts.
- Cluster nodes able to pull the public nginx image from Docker Hub.
- MetalLB **0.14 or newer**, with an available address in an address pool.
  Configure the optional local overlay below to pin a specific address.
- A NetworkPolicy-enforcing CNI, such as Calico.
- At least two eligible schedulable nodes for the two replicas. Required pod
  anti-affinity prevents weather pods from sharing a node; if only one eligible
  node is available, the second replica remains Pending.
- Network access from your device to the LoadBalancer IP and from your browser
  to the external weather providers.

Check the target cluster before deploying:

```bash
kubectl config current-context
```

### First-time deployment

The shared manifest does not pin an external IP. Without a local overlay,
MetalLB assigns an address from its pool.

To pin your LAN address, create `kubernetes/local/kustomization.yaml` with the
following content, replacing `<WEATHER_EXTERNAL_IP>` with an available address:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
patches:
  - target:
      kind: Service
      name: weather
    patch: |-
      - op: add
        path: /metadata/annotations/metallb.io~1loadBalancerIPs
        value: <WEATHER_EXTERNAL_IP>
```

The entire `kubernetes/local/` directory is Git-ignored. The create script uses
that overlay when the directory exists; otherwise it uses the shared base.
An invalid or incomplete local overlay fails deployment rather than falling
back to the base. Removing the overlay and applying the base can remove an
existing IP pin, so retain your local configuration.

From the project root:

```bash
bash kubernetes/scripts/k8sCreateScript.sh
```

Both scripts resolve their input files relative to their own location. You can
also invoke them by absolute path from another working directory.

The create script:

1. Applies the Namespace, nginx configuration ConfigMap, Deployment,
   PodDisruptionBudget, NetworkPolicy, and LoadBalancer Service.
2. Generates and applies `weather-site`, mapping the local HTML to `index.html`.
3. Waits up to 120 seconds for Deployment readiness.
4. Displays the Service and its external IP.

Pods may temporarily wait for `weather-site` because the manifest is applied
before that ConfigMap is created. The script is repeatable: existing resources
are updated declaratively instead of failing with "already exists."

Open `http://<WEATHER_EXTERNAL_IP>/` once MetalLB assigns the address. Deployment readiness
does not guarantee that the external IP has been assigned.

Verify:

```bash
kubectl -n weather get pods -l app=weather
kubectl -n weather get svc weather
WEATHER_IP="$(kubectl -n weather get svc weather -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
test -n "$WEATHER_IP" && curl --fail --silent --show-error -D - -o /dev/null "http://$WEATHER_IP/"
```

The page should return HTTP 200. The nginx configuration uses
`server_tokens off;`, so the response header should be `Server: nginx` without a
version. This does not remove nginx's identity entirely.

If LoadBalancer access is unavailable, use port forwarding in a separate
terminal:

```bash
kubectl -n weather port-forward svc/weather 8080:80
```

Then open **http://localhost:8080/**.

### Updating the dashboard HTML

Edit [src/weather.html](src/weather.html), then run:

```bash
bash -eo pipefail kubernetes/scripts/k8sUpdateScript.sh
```

The explicit Bash options stop on errors and propagate failures from the
ConfigMap generation pipeline. The updater applies only `weather-site`; it does
not apply manifest changes or wait for the updated file to reach the pods.

The HTML is mounted as a ConfigMap directory, so Kubernetes propagates changes
eventually without restarting nginx. Allow time for both replicas to receive
the update; they can temporarily serve different versions. Reload the browser
afterward, using a hard refresh if necessary. An already-open page continues
running its old JavaScript until reloaded.

To compare the served HTML with your source:

```bash
WEATHER_IP="$(kubectl -n weather get svc weather -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
test -n "$WEATHER_IP" && curl --fail --silent --show-error "http://$WEATHER_IP/" |
  diff - src/weather.html
```

No diff output indicates a match for the replica that served that request.

### Updating Kubernetes or nginx configuration

Edit [kubernetes/base/weather-k8s.yaml](kubernetes/base/weather-k8s.yaml), then optionally
validate against the cluster without saving changes:

```bash
kubectl apply --dry-run=server -k kubernetes/local
```

Use `-k kubernetes/base` instead if you do not have a local overlay. You can preview
the rendered configuration without contacting the cluster using
`kubectl kustomize kubernetes/local` (or `kubectl kustomize kubernetes/base`).

Apply the changes:

```bash
bash kubernetes/scripts/k8sCreateScript.sh
```

Deployment pod-template changes, such as a new image or mount, trigger a rollout
automatically. Rolling updates use `maxSurge: 0` and `maxUnavailable: 1`, replacing
one pod at a time so required anti-affinity does not require a third node during
updates. This temporarily reduces available replicas to one.

**Changes only to `weather-nginx-config` require an explicit
restart:** its file is mounted using `subPath`, which does not receive ConfigMap
updates, and nginx must read the new configuration at startup.

```bash
kubectl -n weather rollout restart deployment/weather
kubectl -n weather rollout status deployment/weather --timeout=120s
```

## Deployment settings

- Two replicas using nginx-unprivileged **1.30.5-alpine**, pinned to a
  multi-platform image digest.
- HTTP Service port 80 routes to named container port `http` (8080).
- Readiness and liveness HTTP probes.
- Non-root execution, read-only root filesystem, dropped Linux capabilities,
  RuntimeDefault seccomp, and no mounted service-account token.
- CPU request of 10m with no CPU limit; memory request/limit of 16Mi/64Mi.
- Ephemeral-storage request/limit of 64Mi/256Mi and a 32Mi writable `/tmp`.
- PodDisruptionBudget requiring one available replica during voluntary
  disruptions. It can delay node drains when only one healthy replica remains;
  it does not guarantee availability during node failures.
- NetworkPolicy permits inbound TCP 8080 from any source and blocks pod egress.
  External weather requests still work because they originate in the browser.
  Policies are additive; another policy can allow additional traffic.
- No TLS termination or authentication is configured. The pinned IP is stable
  addressing, not an access-control mechanism.

## Customization

Location coordinates, radar station, and Indian-city settings live in
[src/weather.html](src/weather.html). Adding another Indian-city tab requires a
`CITIES` entry, a navigation button, and a matching `tab-<key>` container.

After changing Delaware coordinates, clear the browser's cached `pt` local
storage entry so the old NWS point metadata is not reused. Update location
labels and radar settings as appropriate.

## Troubleshooting

```bash
kubectl -n weather describe deployment weather
kubectl -n weather get events --sort-by=.metadata.creationTimestamp
kubectl -n weather logs -l app=weather --all-containers=true --tail=100
```

- **Pods waiting for a ConfigMap:** verify `weather-site` and
  `weather-nginx-config` exist in the `weather` namespace.
- **Rollout timeout:** inspect pod events, image pulls, scheduling, and probe
  failures. The timeout does not roll back already-applied resources.
- **External IP pending:** check MetalLB, its pool, and whether your requested IP is
  available.
- **Old HTML:** wait for ConfigMap propagation, check both replicas, and reload
  the browser.
- **Old nginx configuration:** restart the Deployment after updating its
  configuration ConfigMap.
- **Weather panels fail while the page loads:** inspect browser network errors,
  provider availability, and browser internet connectivity. nginx logs do not
  contain browser-to-provider requests.
- **Missing last-applied annotation warning:** a resource was likely created
  imperatively. `kubectl apply` adds the annotation automatically; both scripts
  use declarative ConfigMap application.

Weather observations and alerts can be delayed or unavailable. Check source
timestamps and consult official weather services for safety-critical decisions.
