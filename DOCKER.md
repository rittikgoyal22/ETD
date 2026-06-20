# Running ETD with Docker

Brings up the entire stack — **MySQL + 5 Spring Boot services + 5 Angular apps** — with one command.

## Prerequisites
- Docker Desktop (Docker Engine + Compose v2) running on your machine.

## Quick start
From the project root (`C:\ETD`):
```bash
docker compose up --build -d
```
The first run builds all 11 images (Gradle + Node builds — a few minutes) and starts everything. Then open **http://localhost:4200** and log in:

| Role | Email | Password |
|---|---|---|
| HR | `admin.hr@cognizant.com` | `Admin@123` |
| TravelDeskExe | `desk.exec@cognizant.com` | `Exec@123` |
| Employee | `john.employee@cognizant.com` | `Employee@123` |

## Ports
| Service | URL |
|---|---|
| auth-app | http://localhost:4200 |
| account-management-app | http://localhost:4201 |
| travel-planner-app | http://localhost:4202 |
| reservation-management-app | http://localhost:4203 |
| reimbursement-management-app | http://localhost:4204 |
| auth-service | http://localhost:8080 |
| account-management | http://localhost:8081 |
| travel-planner | http://localhost:8082 |
| reservation-management | http://localhost:8083 |
| reimbursement-management | http://localhost:8084 |
| MySQL | localhost:3306 |

## Useful commands
```bash
docker compose ps                       # status of all containers
docker compose logs -f account-management   # tail a service's logs
docker compose up --build -d account-management   # rebuild one service
docker compose down                     # stop (keeps MySQL data + uploads)
docker compose down -v                  # stop AND wipe all volumes (fresh DB)
```

## How it's wired
- **Backend → backend** calls use Docker **service names** via environment variables defined in each service's own `.env` file (loaded by Compose with `env_file:`), e.g. `AUTH_SERVICE_BASE_URL=http://auth-service:8080/`. The `application.properties` defaults stay `localhost`, so the apps still run un-dockerized.
- **Browser → backend**: the Angular apps' API URLs are baked at build time as `localhost:8080–8084`; this works because each backend container is published to the matching host port.
- **MySQL** data persists in the `mysql-data` volume; the four databases are created by `mysql-init/01-init-databases.sql` (and `createDatabaseIfNotExist=true`).
- **Uploaded PDFs** persist in the `reservation-uploads` / `reimbursement-uploads` volumes.
- **Startup order** is enforced: services wait for MySQL to be healthy; account-management starts before the others (it seeds the shared schema + default users).
- **Per-service config** lives in `BE/<service>/.env` (datasource, JWT secret, Feign URLs); the MySQL root password lives in `db.env`.

## Configuration (per-service .env)

Each backend service is configured by its own env file, loaded into the container by Compose (`env_file:`). The Angular apps have **no** runtime env file — they are configured at build time (the API URLs are baked into the JS bundle).

| File | Drives |
|---|---|
| `db.env` | `MYSQL_ROOT_PASSWORD` for the MySQL container |
| `BE/account-management/.env` | datasource, `JWT_SECRET`, `AUTH_SERVICE_BASE_URL` |
| `BE/auth-service/.env` | datasource (shared `account_management` DB), `JWT_SECRET` |
| `BE/travel-planner/.env` | datasource, `JWT_SECRET`, auth + account-management URLs |
| `BE/reservation-management/.env` | datasource, `JWT_SECRET`, auth + travel-planner URLs, `APP_UPLOAD_DIR` |
| `BE/reimbursement-management/.env` | datasource, `JWT_SECRET`, auth + travel-planner + account-management URLs, `APP_UPLOAD_DIR` |

These env vars override the matching `application.properties` values at runtime via Spring's relaxed binding (`AUTH_SERVICE_BASE_URL` → `auth.service.base_url`, `SPRING_DATASOURCE_PASSWORD` → `spring.datasource.password`, `JWT_SECRET` → `jwt.secret`, `APP_UPLOAD_DIR` → `app.upload.dir`).

> **Two values must stay in sync across files:** `SPRING_DATASOURCE_PASSWORD` (in every backend `.env`) must equal `MYSQL_ROOT_PASSWORD` (in `db.env`); and `JWT_SECRET` must be **identical** in all five backend `.env` files (a mismatched secret breaks token validation between services).

> The `.env` files hold a dev password and are excluded from the built images (via `.dockerignore`). Git-ignore them and use a secrets manager for production.

## Before deploying to AWS
- **Frontend URLs are baked at build time.** For AWS you must rebuild the Angular images with the public/ALB URLs (or add runtime config) — the `localhost` API URLs only work when the browser is on the same host as the published ports.
- Move secrets (`MYSQL_ROOT_PASSWORD`, `jwt.secret`) into AWS Secrets Manager / SSM rather than `.env`.
- Use **Amazon RDS for MySQL** instead of the MySQL container, and **S3** for uploaded PDFs (the volumes are per-host and won't be shared across scaled instances).
- Push images to **Amazon ECR** and run on **ECS Fargate** (or EKS); front the apps with **CloudFront/S3** and the APIs with an **ALB**.

## Notes
- Build images use `gradle:8.11.1-jdk21` (backend) and `node:20-alpine` (frontend). If the exact Gradle tag is unavailable, change it to `gradle:8.11-jdk21` or `gradle:jdk21` in each backend `Dockerfile`.
- Tests are skipped during the image build (`gradle bootJar -x test`) because the context-load test needs a live MySQL.
