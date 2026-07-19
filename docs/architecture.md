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
