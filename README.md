# Student Grade Tracker

A containerised 3-tier web application for recording students and their grades, built with Nginx, Node.js/Express, and PostgreSQL, orchestrated with Docker Compose.

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
git clone https://github.com/<your-username>/student-grade-tracker.git
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

| Symptom                                          | Likely cause / fix                                                                 |
|-----------------------------------------------------|------------------------------------------------------------------------------------|
| Backend image builds but has no `HEALTHCHECK`, no non-root user, no app code | The Dockerfile only had Stage 1 (`deps`) written when `docker build` ran — Stage 2 (`runtime`) was added to the file *after* the build. Confirm both stages exist with `cat Dockerfile` (look for two `FROM` lines), then rebuild with `docker build -t <image>:<tag> .` — Docker will re-run every instruction now present in the file. |
| Backend fails to authenticate against Postgres / crash-loops even though `.env` "looks right" | `.env` had **duplicate variable definitions** (e.g. a leftover placeholder block below the real one) — in a `.env` file, the *last* definition of a variable wins, so `DB_HOST=database` or `DB_PASSWORD=your_secure_password` silently overrode the correct values set earlier in the same file. Run `cat .env` and check for the same variable name appearing more than once; delete the duplicate block and re-run `docker compose config` to confirm the resolved values are correct before starting the stack. |
| Frontend briefly shows `0` students / `0` grades right after `docker compose restart db` | The page happened to load (or auto-refresh) during the few seconds `db` was restarting, so the `fetch()` calls in `index.html` failed silently and fell back to their default `0`/`—` placeholders. This is a transient UI read, not data loss — confirm the real state directly against Postgres: `docker compose exec db psql -U <user> -d <db> -c "SELECT * FROM students;"`, then refresh the browser once `docker compose ps` shows `db` and `backend` both `(healthy)` again. |

## Clean Rebuild (From Scratch)

```bash
docker compose down -v
docker compose up --build
```

## Author

Abdirahman Maalim — Independent Docker & Docker Compose Project
