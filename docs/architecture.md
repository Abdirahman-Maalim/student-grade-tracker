# Student Grade Tracker — Architecture Plan

## 1. Service Mapping & File Breakdown
*   **Frontend Service**: Serves the user interface to the client browser. 
    *   *Starter Files*: `frontend/src/index.html`.
*   **Backend Service**: A Node.js REST API that processes requests, contains application logic, and handles data management.
    *   *Starter Files*: `backend/package.json`, `backend/src/server.js`.
*   **Database Service**: A persistent relational database engine used to store application records.
    *   *Starter Files*: `database/init.sql`.

---

## 2. Component Communication Workflow
```text
   User (Browser)
        │
        │ HTTP (Port 80)
        ▼
  ┌───────────┐
  │  Frontend │ (Nginx web server hosting static assets)
  └─────┬─────┘
        │
        │ API Requests via Browser Context (/api/*)
        ▼
  ┌───────────┐
  │  Backend  │ (Node.js Express Application Server)
  └─────┬─────┘
        │
        │ PostgreSQL Client Protocol (Port 5432)
        ▼
  ┌───────────┐
  │ Database  │ (PostgreSQL Relational Engine)
  └───────────┘

---

# Kubernetes Deployment

This section extends the architecture above with the Kubernetes deployment
built on top of the same Docker images (`abdirahmankhalif/grade-tracker-backend:0.1.0`,
`abdirahmankhalif/grade-tracker-frontend:0.1.0`) already pushed to Docker Hub.
No application code or Dockerfiles changed for this phase — only how the
containers are orchestrated.

## Kubernetes Resources and Why Each Was Chosen

| Resource | Kind | Why this kind, specifically |
|---|---|---|
| `grade-tracker` | Namespace | Isolates this app's resources from anything else on the cluster; every other manifest deploys into it. |
| `grade-tracker-config` | ConfigMap | Externalizes non-sensitive config (`DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `PORT`, `APP_ENV`) the same way `.env` did for Docker Compose - but consumable by multiple Pods without baking values into images. |
| `postgres-initdb` | ConfigMap | Holds `database/init.sql`'s content so it can be mounted as a file inside the Postgres Pod. Kubernetes cannot bind-mount a file straight from the Git repo into a container the way Docker Compose could - a ConfigMap is the mechanism that carries the file content *into* the cluster. |
| `grade-tracker-postgres-pv` | PersistentVolume | Represents real, available storage on the Minikube node (`hostPath`) - the Kubernetes-level equivalent of Docker's named volume, but explicitly split into "available storage" vs "storage request" (see PVC below). |
| `grade-tracker-postgres-pvc` | PersistentVolumeClaim | The Postgres Pod's request for storage - binds to the PV above based on matching `storageClassName`, size, and access mode. |
| `backend-replicaset-exercise` | ReplicaSet | Temporary, graded exercise only (see below) - not part of the final running architecture. |
| `postgres` | StatefulSet | Chosen over a Deployment because a database needs a **stable identity tied to its storage**. StatefulSet Pods get predictable names (`postgres-0`) that persist across restarts, and pair naturally with a PVC that reattaches to the same identity every time. A Deployment gives no such guarantee - its Pods are anonymous and interchangeable. |
| `postgres-headless` | Headless Service (`clusterIP: None`) | Required by the StatefulSet's `serviceName` field - gives each replica its own stable DNS entry rather than one load-balanced IP. |
| `postgres-service` | ClusterIP Service | The stable internal address the backend actually connects to (`DB_HOST=postgres-service`) - load-balances if replicas ever increase, though we run 1. |
| `backend-deployment` | Deployment | Two replicas, `RollingUpdate` strategy - unlike the ReplicaSet exercise, a Deployment can migrate existing Pods to a new image spec without manual intervention. |
| `backend` | ClusterIP Service | **Named `backend` deliberately**, not `backend-service` - see "Two Gotchas" below. |
| `frontend-deployment` | Deployment | Two replicas, no special update requirements beyond the Deployment default. |
| `frontend-service` | NodePort Service | The only externally-reachable entry point (`nodePort: 30090`), replacing Docker Compose's `ports: "8080:8080"` host-port mapping. |

## How the ConfigMap Is Used

Two consumption patterns are used across the manifests:

1. **`envFrom.configMapRef`** (in `backend-deployment.yaml`) - injects every
   key in `grade-tracker-config` as an environment variable in one shot.
   This matches how `server.js` already reads `process.env.DB_HOST`,
   `process.env.PORT`, etc. - no code changes were needed.
2. **`env[].valueFrom.configMapKeyRef`** (in `postgres-statefulset.yaml`) -
   picks individual keys and renames them, because the official Postgres
   image expects `POSTGRES_DB`/`POSTGRES_USER` while our ConfigMap uses
   `DB_NAME`/`DB_USER` to match the backend's own variable names. This
   mapping is why `envFrom` alone couldn't be used for Postgres.

One deliberate deviation from the project brief: the brief's checklist
names `API_PORT`, but `server.js` actually reads `process.env.PORT`. The
ConfigMap key is named `PORT` to match the real application code rather
than the brief's checklist wording.

## Storage Setup - PV, PVC, and StatefulSet

The PV (`grade-tracker-postgres-pv`) provisions 2Gi via `hostPath` at
`/data/grade-tracker/postgres` on the Minikube node, with a `Retain`
reclaim policy - meaning the underlying data is not deleted even if the
PVC is removed, only if the PV itself is explicitly deleted.

The PVC (`grade-tracker-postgres-pvc`) requests 1Gi with the same
`storageClassName: manual` as the PV - this exact match is what allows
Kubernetes to bind them together automatically.

The StatefulSet mounts this PVC (not a `volumeClaimTemplate`, since the
PVC was created explicitly beforehand per the project's Step 5) at
`/var/lib/postgresql/data`, with `PGDATA` set to a subdirectory
(`/var/lib/postgresql/data/pgdata`) rather than the mount root - this
avoids a "directory not empty" initialization failure Postgres raises
when its data directory root already contains the volume's lost+found
metadata.

## Networking - Service Type Per Tier and Why

- **Headless Service** for Postgres: required for StatefulSet DNS identity, not for traffic routing.
- **ClusterIP** for Postgres and backend: both are internal-only, never reached directly from outside the cluster.
- **NodePort** for frontend: the one tier that needs external reachability, since it's the only thing a browser talks to.

## Two Real Gotchas Found and Resolved During This Build

**1. Backend Service naming constraint.** The frontend Docker image
already contains a built-in `nginx.conf` with
`proxy_pass http://backend:3000/api/;` hardcoded from the Docker Compose
project. Since we reused the already-built, already-pushed image rather
than rebuilding it, the backend's ClusterIP Service had to be named
exactly `backend` (not `backend-service`, which would otherwise have been
the more conventional name) - Kubernetes DNS resolves Services by their
`metadata.name`, and any mismatch here would silently break the frontend's
reverse proxy with no error in the frontend's own logs.

**2. Frontend port mismatch.** The project brief's own architecture
diagram assumes the frontend listens on port 80. Our actual image uses
`nginxinc/nginx-unprivileged`, which listens on 8080 internally (a
deliberate non-root design choice made during the Docker phase). The
NodePort Service's `targetPort` was set to 8080 to match the real image,
not the brief's generic assumption.

## ReplicaSet Exercise Observations (Step 4)

Applied `backend-replicaset-exercise.yaml` (2 replicas) before creating
the real backend Deployment.

**Observation A - self-healing:** deleting one of the two Pods
(`kubectl delete pod <name>`) resulted in the ReplicaSet controller
immediately creating a replacement, observed live via
`kubectl get pods -w`. Pod count returned to 2/2 within seconds.

**Observation B - no rollout on spec change:** running
`kubectl set image replicaset/backend-replicaset-exercise backend=...:9.9.9`
updated the ReplicaSet's own spec (confirmed via
`replicaset.apps/backend-replicaset-exercise image updated`), but querying
the *existing* Pods' actual running image
(`kubectl get pods -l exercise=replicaset -o jsonpath='{.items[*].spec.containers[*].image}'`)
still showed the original `0.1.0` tag - proving a ReplicaSet only
reconciles Pod **count**, never Pod **spec drift**. Existing Pods keep
running whatever image they were created with indefinitely, even after
the ReplicaSet's own template changes.

This is the direct, hands-on reason a Deployment is used for the real
backend and frontend workloads instead: a Deployment detects template
changes and creates a new ReplicaSet to gradually migrate Pods to the
updated spec, which a bare ReplicaSet fundamentally cannot do.

The exercise ReplicaSet was deleted (`kubectl delete -f
replicaset-exercise.yaml`) before applying the real `backend-deployment.yaml`,
to avoid both resources' `app: backend` label selectors competing for
the same Pods.

## Persistence Verification (Step 9)

Added additional students and grades through the running application UI,
then ran `kubectl delete pod postgres-0 -n grade-tracker`. The StatefulSet
controller recreated the Pod (confirmed via `kubectl get pods -w`,
transitioning `ContainerCreating` -> `Running` within seconds) using the
same PVC. Reloading the application afterward confirmed all previously
added data was still present - proving the PVC, not the Pod, is the
actual source of truth for the database's state.

## Challenges Encountered and How They Were Resolved

- **`updateStrategy: Recreate` is invalid on a StatefulSet.** Unlike
  Deployments, StatefulSets only accept `RollingUpdate` or `OnDelete` as
  valid `updateStrategy.type` values. Fixed by changing the StatefulSet
  manifest to `OnDelete`, which is also the more deliberate choice for a
  single-replica database - it never auto-restarts Postgres on a spec
  change without an explicit Pod deletion.
- **Minikube ran out of disk space mid-project**, causing
  `postgres:15-alpine` to fail pulling with "no space left on device."
  Diagnosed via `kubectl describe pod` reading the Events section, which
  showed the exact I/O error rather than a generic pull failure. Resolved
  by resizing the underlying Multipass VM's disk (`multipass set
  local.<vm>.disk=60G`, stop/start, then `growpart`/`resize2fs` to expand
  the filesystem) and running `minikube ssh -- docker system prune -a -f`
  to clear stale layers inside Minikube's own internal Docker daemon
  (which is separate from the host VM's Docker installation).
- **Minikube's API server became unreachable after the VM restart**
  required by the disk resize (`no route to host` on port 8443). This was
  because stopping/starting the outer Multipass VM also stopped Minikube's
  internal cluster, which does not restart automatically. Resolved with a
  plain `minikube start` - the existing cluster state (namespace,
  ConfigMaps, PV/PVC, StatefulSet) was preserved throughout, since nothing
  had triggered `minikube delete`.
