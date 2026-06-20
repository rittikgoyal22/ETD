# ✈️ Employee Travel Desk (ETD)

A microservices-based **corporate travel management platform** — a Cognizant FSE Business-Aligned Project that automates the entire business-trip lifecycle: raising travel requests, HR approval and budgeting, reservation booking, and post-trip expense reimbursement.

**Tech stack:** Java 21 · Spring Boot 3.5.7 · Spring Cloud OpenFeign · Spring Security (JWT) · Spring Data JPA · **MySQL 8** · Angular 17 · Bootstrap 5 · Bootstrap Icons · Chart.js · Gradle

---

## 📋 Overview

ETD is split into **five independent Spring Boot microservices** (backend) and **five matching Angular single-page micro-frontends** (frontend), integrated through a shared, stateless **JSON Web Token (JWT)**.

### Roles

| Role | What they do |
|---|---|
| **HR** | Manage employees & grades, approve/reject travel requests, calculate the approved trip budget |
| **Employee** | Raise travel requests, track reservations, submit post-trip reimbursement claims |
| **TravelDeskExe** (Travel Desk Executive) | Upload reservation bookings (flight/train/bus/cab/hotel) for approved trips, review & process reimbursement claims |

### End-to-end flow

```
Employee raises a travel request
   → HR approves it and calculates the budget
      → TravelDeskExe books reservations (flight / hotel / cab …)
         → Employee travels and submits expense invoices
            → TravelDeskExe approves or rejects each reimbursement claim
```

---

## 🏗️ Architecture

Each backend service is autonomous, owns its data, and exposes a REST API documented with OpenAPI/Swagger. Each Angular app maps one-to-one to a backend service and runs on its own port. The browser talks to every service directly (open CORS); there is no central API gateway in the current build.

| Microservice | Port | Front-end app | FE Port | Responsibility |
|---|---|---|---|---|
| **account-management** | 8081 | account-management-app | 4201 | Employees, grades, grade history; **owns the shared `account_management` MySQL DB** |
| **auth-service** | 8080 | auth-app | 4200 | Central login, token refresh, logout, JWT blacklist check |
| **travel-planner** | 8082 | travel-planner-app | 4202 | Travel-request lifecycle + budget calculation; hosts the unified **Home dashboard** |
| **reservation-management** | 8083 | reservation-management-app | 4203 | Reservation booking + PDF storage/download |
| **reimbursement-management** | 8084 | reimbursement-management-app | 4204 | Expense-claim submission + processing |

**Startup order (mandatory):** `account-management` → `auth-service` → `travel-planner` → `reservation-management` → `reimbursement-management`. account-management must start first because it creates and seeds the shared `account_management` schema that auth-service depends on.

---

## 🧰 Technology Stack

### Backend
| Area | Technology |
|---|---|
| Language / runtime | Java 21 |
| Framework | Spring Boot 3.5.7, Spring Cloud 2025.0.0 |
| Core modules | Spring Web (REST), Spring Security, Spring Data JPA |
| Inter-service calls | Spring Cloud OpenFeign |
| Authentication | JJWT 0.12.6 (HMAC-SHA256 signed JWT) |
| Database | **MySQL 8** (`mysql-connector-j`, dialect `MySQLDialect`, `ddl-auto=update`) |
| API docs | springdoc-openapi (Swagger UI) |
| Boilerplate | Lombok 1.18.40 |
| Build | Gradle (system Gradle; wrapper jar not committed) |

### Frontend
| Area | Technology |
|---|---|
| Framework | Angular 17.2 (NgModule-based) |
| Language | TypeScript 5.3 |
| Reactive | RxJS 7.8 |
| UI / styling | Bootstrap 5 + Bootstrap Icons (via CDN), custom vibrant theme |
| Charts | Chart.js 4 (via CDN) |
| Auth | HttpClient with auth + error interceptors; route + role guards; cross-app JWT hand-off |
| Tooling | Angular CLI 17, Karma + Jasmine |

---

## 📁 Project Structure

```
C:\ETD
├── BE\                              # Backend — 5 Spring Boot microservices
│   ├── account-management\          (port 8081)
│   ├── auth-service\                (port 8080)
│   ├── travel-planner\              (port 8082)
│   ├── reservation-management\      (port 8083)
│   ├── reimbursement-management\    (port 8084)
│   ├── etd_mysql_schema.sql         # Optional reference MySQL DDL (4 databases)
│   └── CLAUDE.md                    # Full backend reference
├── FE\                              # Frontend — 5 Angular micro-frontends
│   ├── auth-app\                    (port 4200)
│   ├── account-management-app\      (port 4201)
│   ├── travel-planner-app\          (port 4202)
│   ├── reservation-management-app\  (port 4203)
│   └── reimbursement-management-app\(port 4204)
├── ETD_Project_Documentation.pdf    # Formal project documentation
└── README.md                        # This file
```

Each backend service follows the same layered structure: `controller → service (interface + impl) → dao (JpaRepository) → entity`, with `mapper/`, `dto/`, `client/` (Feign), `config/`, `constant/`, `exception/`, and `util/` packages.

---

## 🔌 Backend Microservices & API

> All `/api/**` endpoints require a valid JWT (`Authorization: Bearer <token>`) except where noted. Swagger UI for each service is at `http://localhost:<port>/swagger-ui.html`.

### account-management (8081) — employees, grades
| Method | Path | Role |
|---|---|---|
| GET | `/api/employees` | Any authenticated |
| GET | `/api/employees/me` | Any authenticated (current user from JWT) |
| GET | `/api/employees/{id}` | Any authenticated |
| POST | `/api/employees` | HR |
| PUT | `/api/employees/{id}` | HR |
| DELETE | `/api/employees/{id}` | HR |
| GET | `/api/grades` | Any authenticated |
| GET | `/api/gradeHistory`, `/api/gradeHistory/{employeeId}` | Any authenticated |

### auth-service (8080) — authentication (all routes public)
| Method | Path | Description |
|---|---|---|
| POST | `/login` | Returns access token (1h) + refresh token (7d) |
| POST | `/auth/refresh` | Rotates tokens |
| POST | `/auth/logout` | Deletes refresh token; blacklists access token |
| GET | `/auth/blacklist/check?token=` | Used by every service on each request |

### travel-planner (8082) — travel requests & budget
| Method | Path | Role |
|---|---|---|
| POST | `/api/travelrequests/new` | Employee |
| GET | `/api/travelrequests/{hrId}/pending` | HR |
| PUT | `/api/travelrequests/{trid}/update` | HR (approve/reject) |
| POST | `/api/travelrequests/calculatebudget` | HR |
| GET | `/api/travelrequests/my` | Employee (own requests) |
| GET | `/api/travelrequests/approved` | TravelDeskExe (all approved) |
| GET | `/api/travelrequests/{trid}` | Any authenticated |
| GET | `/api/travelrequests/locations` | Any authenticated |

### reservation-management (8083) — bookings & PDFs
| Method | Path | Role |
|---|---|---|
| POST | `/api/reservations/add` | TravelDeskExe (multipart + PDF) |
| GET | `/api/reservations/track/{travelRequestId}` | Employee + TravelDeskExe |
| GET | `/api/reservations/{reservationId}` | Employee |
| GET | `/api/reservations/{reservationId}/download` | Employee |
| GET | `/api/reservations/types` | Any authenticated |

### reimbursement-management (8084) — expense claims
| Method | Path | Role |
|---|---|---|
| POST | `/api/reimbursements/add` | Employee (multipart + PDF; travel request must be APPROVED) |
| PUT | `/api/reimbursements/{reimbursementId}/process` | TravelDeskExe (approve/reject) |
| GET | `/api/reimbursements/my` | Employee (own claims) |
| GET | `/api/reimbursements/{travelRequestId}/requests` | Any authenticated |
| GET | `/api/reimbursements/{reimbursementId}` | Any authenticated |
| GET | `/api/reimbursements/types` | Any authenticated |

---

## 🖥️ Frontend Applications

All five apps land on a unified, role-aware **Home dashboard** (travel-planner-app `/home`) after login, share an identical **data-driven navigation bar**, and pass the JWT between apps as URL parameters during cross-app navigation.

| App (port) | Primary role | Key pages |
|---|---|---|
| **auth-app** (4200) | All | Login |
| **account-management-app** (4201) | HR | Employee list (+ role/grade charts), Add employee, Change grade |
| **travel-planner-app** (4202) | Employee / HR | **Home dashboard**, New request, My Requests (+ status/priority charts), Pending requests, Calculate budget, Request details |
| **reservation-management-app** (4203) | TravelDeskExe / Employee | Add reservation, **View Reservations** (TravelDeskExe, + spend chart), My Reservations (track), Reservation details |
| **reimbursement-management-app** (4204) | Employee / TravelDeskExe | Submit claim, My Claims (+ status/type/amount charts), Process/Search claims |

Travel-request-ID fields on the Add Reservation, View Reservations, My Reservations, and Process Claims pages are **dropdowns** (no manual ID typing) populated from the relevant scoped endpoint.

---

## 🔐 Authentication & Authorization

- **Stateless JWT** signed with HMAC-SHA256 using a shared secret identical across all five services.
- Claims: `sub` (email), `role` (`HR` / `Employee` / `TravelDeskExe`), `iat`, `exp`. Access token valid **1 hour**; refresh token **7 days** (rotated on use).
- Each protected service runs a `JwtAuthFilter` that validates signature + expiry locally and calls auth-service to check the **logout blacklist** on every request (fail-open if auth-service is unreachable).
- Spring Security maps the JWT `role` claim directly to an authority (no `ROLE_` prefix). Outgoing Feign calls forward the bearer token via a `FeignAuthInterceptor`.
- The frontend stores the token in `localStorage`, attaches it via an HTTP interceptor, guards routes by role, and hands the token between apps through URL params on cross-app navigation.

---

## 🗄️ Database (MySQL 8)

The backend runs entirely on **MySQL 8** over TCP 3306 (`root` user). Each service uses `spring-boot-starter-data-jpa` + `runtimeOnly 'com.mysql:mysql-connector-j'` with `spring.jpa.hibernate.ddl-auto=update`, so Hibernate auto-creates/updates all tables on startup.

| Service | MySQL database | JDBC URL |
|---|---|---|
| account-management | `account_management` (**schema owner**) | `jdbc:mysql://localhost:3306/account_management` |
| auth-service | `account_management` (**shared**) | `jdbc:mysql://localhost:3306/account_management` |
| travel-planner | `travel_planner` | `jdbc:mysql://localhost:3306/travel_planner` |
| reservation-management | `reservation_management` | `jdbc:mysql://localhost:3306/reservation_management` |
| reimbursement-management | `reimbursement_management` | `jdbc:mysql://localhost:3306/reimbursement_management` |

- **account-management + auth-service share** the `account_management` database directly over TCP 3306. account-management creates/seeds the `employees`/`grades` schema; auth-service creates the `refresh_tokens` and `token_blacklist` tables it owns.
- A hand-written reference schema is available at `BE/etd_mysql_schema.sql` (4 databases, 13 tables) — optional, since `ddl-auto=update` builds the schema automatically.
- **Fresh start:** `DROP DATABASE <name>; CREATE DATABASE <name>;` then restart the service.

---

## 🔁 Inter-Service Communication (Feign)

| Caller | Calls | Purpose |
|---|---|---|
| travel-planner | account-management, auth-service | Validate employee + grade for budget; blacklist check |
| reservation-management | travel-planner, auth-service | Validate approved trip + budget; blacklist check |
| reimbursement-management | travel-planner, account-management, auth-service | Validate trip + dates; validate processor role; blacklist check |

---

## 📐 Key Business Rules

**Grade changes (account-management):** upgrade only (lower grade id = more senior); no change within 2 years of joining; at most once per year; TravelDeskExe is force-assigned to Grade-1.

**Travel request & budget (travel-planner):** priority caps the trip duration (ONE 30, TWO 20, THREE 10 days); only the logged-in employee can raise their own request; the approver must be HR; budget = grade daily cap (Grade-1 ₹15,000 / Grade-2 ₹12,500 / Grade-3 ₹10,000) × days; hotel rating by role (HR: 5/7-STAR, others: 3/5-STAR).

**Reservations (reservation-management):** PDF ≤ 1 MB; one reservation per category (transport/cab/hotel); train/bus exactly 1 day before the trip, hotel on the trip start date; budget caps (of 70% of the approved budget) — transport 35%, cab 15%, hotel 50%.

**Reimbursements (reimbursement-management):** travel request must be **APPROVED** before a claim can be raised; PDF ≤ 256 KB; per-invoice ranges (Food/Water ₹1,000–1,500, Laundry ₹250–500, LocalTravel ≤₹1,000) and daily cumulative limits; only a TravelDeskExe can process; remarks required on rejection.

---

## 🎨 UI / UX & Analytics

- **Vibrant, modern theme** shared across all apps: animated gradient navbar, gradient buttons with hover effects, glassmorphism cards, slide-in alerts, and a full-page animated **travel-cityscape background image** (SVG) behind every page.
- **Emojis** on titles, section labels, empty states, and primary buttons for a friendly feel.
- **Chart.js analytics** (pie/doughnut, bar, line) on data-rich pages — e.g. employees by role/grade, travel requests by status/priority, reimbursement claims by status/type and amount over time, reservation spend by type.
- Fully responsive; respects `prefers-reduced-motion`.

---

## 👤 Default Seed Credentials

Seeded by account-management's `DataInitializer` on first startup (passwords are BCrypt-hashed):

| Role | Email | Password | Employee ID |
|---|---|---|---|
| HR | `admin.hr@cognizant.com` | `Admin@123` | 100000 |
| TravelDeskExe | `desk.exec@cognizant.com` | `Exec@123` | 100001 |
| Employee | `john.employee@cognizant.com` | `Employee@123` | 100002 |

---

## 🚀 Getting Started

### Prerequisites
- **Java 21**, **Gradle** (system install — the wrapper jar is not committed)
- **MySQL 8** running on `localhost:3306`
- **Node.js 18+** and **Angular CLI 17** for the frontend

### 1. Database
Ensure MySQL is running. The services auto-create their databases (the JDBC URLs use `createDatabaseIfNotExist=true`). Set the `root` password in each service's `src/main/resources/application.properties` to match your MySQL instance (default in the repo is `Rittik@95174`).

### 2. Backend (start in this order)
```bash
# from each service folder, e.g. C:\ETD\BE\account-management
gradle bootRun
```
Order: **account-management (8081)** → **auth-service (8080)** → **travel-planner (8082)** → **reservation-management (8083)** → **reimbursement-management (8084)**.

### 3. Frontend (any order)
```bash
# from each app folder, e.g. C:\ETD\FE\auth-app
npm install     # first time only
npm start       # ng serve
```
Ports: 4200 (auth) · 4201 (account) · 4202 (travel) · 4203 (reservation) · 4204 (reimbursement).

### 4. Use it
Open **http://localhost:4200**, log in with a seeded account above. All roles land on the Home dashboard at `http://localhost:4202/home`.

---

## ⚠️ Limitations & Future Enhancements

- **Development-stage config:** the JWT secret and MySQL credentials are hard-coded in each `application.properties`; externalise them (env vars / Spring Config / secrets manager) for production.
- **No API gateway / service discovery:** the browser calls each service directly over open CORS. Consider Spring Cloud Gateway + Eureka.
- **Test coverage** is limited to the default Spring context-load test per service; add unit/integration/contract tests.
- **Front-end shared code** (navbar, config) is duplicated across the five apps; a shared Angular library or Module Federation would remove the duplication.
- **Analytics dashboard:** charts currently use per-page data; dedicated aggregate endpoints could power a richer cross-role analytics home page.

---

*Employee Travel Desk (ETD) — Cognizant FSE Business-Aligned Project.*
