# Student Grade Tracker

A containerised 3-tier web application for recording students and their grades, built with Nginx, Node.js/Express, and PostgreSQL, orchestrated with Docker Compose and then a Kubernetes deployment, reusing the
same Docker Hub images built during the Docker Compose phase - no
application code changes were needed.

## Architecture#

The browser only ever talks to the `frontend` container. Nginx reverse-proxies any request under `/api/` to the `backend` service by its Compose service name (`backend:3000`), which in turn connects to `db:5432`. Neither `backend` nor `db` publish ports to the host — they're reachable only inside the `grade-tracker-network` Docker network.

Full design rationale: [docs/architecture.md](docs/architecture.md)

## Services

| Service  | Image                                                                                  | Port (host)      | Description                                                                |
|----------|------------------------------------------------------------------------------------------|--------------------|--------------------------------------------------------------------------------|
| frontend | `grade-tracker-frontend:0.1.0` (built from `nginxinc/nginx-unprivileged:1.27-alpine`)     | `8080:8080`        | Serves the static UI, reverse-proxies `/api` to backend, runs as non-root      |
| backend  | `grade-tracker-backend:0.1.0` (built from `node:20.15-alpine`, multi-stage)               | *(internal only)*  | Express REST API, connects to Postgres via `pg`, runs as non-root              |
| db       | `postgres:16.3-alpine` (official image)                                                   | *(internal only)*  | Stores students and grades, seeded from `database/init.sql`                    |

## Prerequisites

- Docker Engine 24+
- Docker Compose v2 (`docker compose`, not the legacy `docker-compose`)
- (Optional) [Trivy](https://aquasecurity.github.io/trivy/) for image scanning

## Quick Start

```bash
git clone https://github.com/Abdirahman-Maalim/student-grade-tracker.git
cd student-grade-tracker

# Create your local environment file
cp .env.example .env
# then edit .env and set POSTGRES_PASSWORD / DB_PASSWORD to a real value
# (POSTGRES_USER must match DB_USER, POSTGRES_PASSWORD must match DB_PASSWORD)

# Build and start the full stack
docker compose up --build
```

Once all three containers report `(healthy)` (`docker compose ps`), open the app in your browser.

- **Running Docker natively** (Docker Desktop on Mac/Windows/Linux): open `http://localhost:8080`
- **Running Docker inside a VM** (e.g. this project's Multipass Ubuntu VM): `localhost` refers to the VM itself, not your host machine's browser. Find the VM's IP first:
```bash
  ip addr show enp0s1 | grep "inet "
```
  Then open `http://<vm-ip>:8080` — for example `http://192.168.252.2:8080`.

## Usage

- **Add a student**: fill in name + email under "Add Student" and click **Add Student**.
- **Record a grade**: select a student, enter a subject and score (0–100), and click **Record Grade**.
- **Class Statistics** and the **All Grades** table update automatically, and auto-refresh every 30 seconds.
- Sample students/grades are seeded automatically from `database/init.sql` the first time the `db` volume is created.

## Automation Scripts

```bash
# Build and tag all custom images
./scripts/build.sh 0.1.0

# Verify the running stack is healthy
./scripts/healthcheck.sh
```

## Verifying Data Persistence

```bash
docker compose restart db
```

Refresh the app — previously added students/grades are still there, because Postgres data lives in the named volume `grade-tracker-db-data`, independent of the container's lifecycle.

## Vulnerability Scanning

Both custom-built images were scanned with [Trivy](https://aquasecurity.github.io/trivy/) (`--severity HIGH,CRITICAL`).

| Image                          | Alpine OS packages | App dependencies (`app/node_modules`) | HIGH | CRITICAL |
|----------------------------------|-----------------------|------------------------------------------|--------|------------|
| `grade-tracker-backend:0.1.0`  | 0 vulnerabilities     | 0 vulnerabilities                        | 12   | 0        |
| `grade-tracker-frontend:0.1.0` | 0 vulnerabilities     | n/a (no application dependencies)        | 0    | 0        |

**No CRITICAL vulnerabilities remain in either image.**

The 12 HIGH findings on the backend (e.g. `cross-spawn`, `glob`, `minimatch`, `tar`, `sigstore`) all live in `usr/local/lib/node_modules/npm/...` — the **npm CLI bundled inside the `node:20.15-alpine` base image itself**, not in code the application imports or executes. The application's own three dependencies (`express`, `pg`, `cors`) scanned completely clean. Since the final image is built via a multi-stage Dockerfile and only needs the Node.js *runtime* (not the `npm` CLI) to execute `node src/server.js`, these findings can be eliminated entirely by removing the bundled npm binary from the final stage — noted as a follow-up hardening step.

Full scan reports are saved under [`docs/scans/`](docs/scans/):
- `backend-vuln-scan.txt` — initial backend scan
- `backend-vuln-scan-rescan.txt` — backend re-scan
- `frontend-vuln-scan.txt` — initial frontend scan
- `frontend-vuln-scan-rescan.txt` — frontend re-scan

To re-run the scans yourself:

```bash
trivy image --severity HIGH,CRITICAL grade-tracker-backend:0.1.0
trivy image --severity HIGH,CRITICAL grade-tracker-frontend:0.1.0
```

## Pushing Images to Docker Hub

```bash
docker login

docker tag grade-tracker-backend:0.1.0  hub.docker.com/repository/docker/abdirahmankhalif/grade-tracker-backend:0.1.0
docker tag grade-tracker-frontend:0.1.0 hub.docker.com/repository/docker/abdirahmankhalif/grade-tracker-frontend:0.1.0

docker push hub.docker.com/repository/docker/abdirahmankhalif/grade-tracker-backend:0.1.0
docker push hub.docker.com/repository/docker/abdirahmankhalif/grade-tracker-frontend:0.1.0
```

## Troubleshooting

| Symptom                                                                              | Likely cause / fix                                                                                                                                                                                                                                                                                                                          |
|-----------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Backend image builds but has no `HEALTHCHECK`, no non-root user, no app code             | The Dockerfile only had Stage 1 (`deps`) written when `docker build` ran — Stage 2 (`runtime`) was added to the file *after* the build. Confirm both stages exist with `cat Dockerfile` (look for two `FROM` lines), then rebuild with `docker build -t grade-tracker-backend:0.1.0 .` (run from inside the `backend/` directory) — Docker will re-run every instruction now present in the file. |
| Backend fails to authenticate against Postgres / crash-loops even though `.env` "looks right" | `.env` had **duplicate variable definitions** (e.g. a leftover placeholder block below the real one) — in a `.env` file, the *last* definition of a variable wins, so `DB_HOST=database` or `DB_PASSWORD=your_secure_password` silently overrode the correct values set earlier in the same file. Run `cat .env` and checked for the same variable name appearing more than once; deleted the duplicate block and re-run `docker compose config` to confirm the resolved values are correct before starting the stack. |
| Frontend briefly shows `0` students / `0` grades right after `docker compose restart db` | The page happened to load (or auto-refresh) during the few seconds `db` was restarting, so the `fetch()` calls in `index.html` failed silently and fell back to their default `0`/`—` placeholders. This is a transient UI read, not data loss — confirm the real state directly against Postgres: `docker compose exec db psql -U admin -d grades_db -c "SELECT * FROM students;"`, then refresh the browser once `docker compose ps` shows `db` and `backend` both `(healthy)` again. |

## Clean Rebuild (From Scratch)

```bash
docker compose down -v
docker compose up --build
```
---

## Kubernetes Deployment

This project also ships as a Kubernetes deployment (`k8s/`), reusing the
same Docker Hub images built during the Docker Compose phase - no
application code changes were needed.

### Kubernetes Resources

| Kind | Name | Purpose |
|---|---|---|
| Namespace | `grade-tracker` | Isolates all resources for this app |
| ConfigMap | `grade-tracker-config` | Non-sensitive app config (DB host/port/name/user, API port) |
| ConfigMap | `postgres-initdb` | Holds `init.sql` content, mounted into Postgres on first start |
| PersistentVolume | `grade-tracker-postgres-pv` | 2Gi hostPath storage for the database |
| PersistentVolumeClaim | `grade-tracker-postgres-pvc` | 1Gi claim bound to the PV above |
| StatefulSet | `postgres` | Single-replica PostgreSQL 15 instance |
| Service (Headless) | `postgres-headless` | Stable per-Pod DNS for the StatefulSet |
| Service (ClusterIP) | `postgres-service` | Internal DB endpoint used by the backend |
| Deployment | `backend-deployment` | 2 replicas of the Express API |
| Service (ClusterIP) | `backend` | Internal API endpoint (name required by the frontend's built-in nginx proxy) |
| Deployment | `frontend-deployment` | 2 replicas of the Nginx-served UI |
| Service (NodePort) | `frontend-service` | External access on port 30010 |

### Prerequisites

- Minikube
- kubectl
- Docker (for Minikube's driver)

### Deployment Order

```bash
cd k8s
kubectl apply -f namespace.yaml
kubectl apply -f configmap.yaml
kubectl apply -f persistentvolume.yaml
kubectl apply -f persistentvolumeclaim.yaml
kubectl apply -f postgres-headless-service.yaml
kubectl apply -f postgres-service.yaml
kubectl apply -f postgres-statefulset.yaml
kubectl apply -f backend-service.yaml
kubectl apply -f backend-deployment.yaml
kubectl apply -f frontend-service.yaml
kubectl apply -f frontend-deployment.yaml
```

Full step-by-step reasoning for this order, plus the ReplicaSet exercise
(applied and deleted separately, before the backend Deployment), is in
[docs/architecture.md](docs/architecture.md).

### Accessing the Application

```bash
minikube service frontend-service -n grade-tracker --url
```

Open the printed URL in your browser.

### Verifying Everything Is Healthy

```bash
kubectl get all -n grade-tracker
kubectl get pv,pvc -n grade-tracker
kubectl get endpoints -n grade-tracker
```

All Pods should show `Running`, the PVC should show `Bound`, and every
Service should have real Pod IPs listed under its endpoints (not `<none>`).

### Verifying Data Persistence

```bash
kubectl delete pod postgres-0 -n grade-tracker
kubectl get pods -n grade-tracker -w
```

Reload the app once `postgres-0` is `Running` again - previously added
students and grades should still be present, since they live in the PVC,
not the Pod.

### Cleaning Up

```bash
kubectl delete namespace grade-tracker
```

Deletes every resource created in this section in one command. The
PersistentVolume itself (`grade-tracker-postgres-pv`) is cluster-scoped,
not namespaced, so it survives this and would need
`kubectl delete pv grade-tracker-postgres-pv` separately if you want to
remove it too - its `Retain` reclaim policy means the underlying data on
disk is preserved either way.

### Kubernetes-Specific Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| StatefulSet rejected with `spec.updateStrategy: Invalid value` | StatefulSets only accept `RollingUpdate` or `OnDelete` for `updateStrategy.type` - `Recreate` (valid on Deployments) is not valid here. |
| Pod stuck in `ImagePullBackOff` with "no space left on device" in `kubectl describe pod` | Minikube's internal disk is full. Run `minikube ssh -- docker system prune -a -f`, and if that's insufficient, resize the underlying VM's disk and restart Minikube. |
| `kubectl` suddenly returns "no route to host" on port 8443 | Minikube's internal cluster stopped (often after the host VM was stopped/restarted) and needs to be brought back up explicitly with `minikube start` - it does not restart automatically with the host. |
| Frontend loads but API calls fail | Confirm the backend Service is named exactly `backend` - the frontend's built-in `nginx.conf` has this hostname hardcoded and cannot be changed without rebuilding the image. |

## Author

Abdirahman Maalim (https://github.com/Abdirahman-Maalim/student-grade-tracker)  — Independent Docker,  Docker Compose and Kubernetes deployment Project
