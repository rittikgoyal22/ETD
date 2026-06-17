# Employee Travel Desk (ETD) — Backend

A Cognizant FSE Business Aligned Project. ETD is a microservices-based corporate travel management platform. Employees raise travel requests, HR approves them and calculates budgets, Travel Desk Executives handle reservations and process reimbursement claims.

---

## Table of Contents

1. [Tech Stack](#tech-stack)
2. [Microservice Overview](#microservice-overview)
3. [Getting Started](#getting-started)
4. [Default Credentials](#default-credentials)
5. [Authentication & Token Lifecycle](#authentication--token-lifecycle)
6. [Role Permissions Matrix](#role-permissions-matrix)
7. [API Reference — account-management](#api-reference--account-management-port-8081)
8. [API Reference — auth-service](#api-reference--auth-service-port-8080)
9. [API Reference — travel-planner](#api-reference--travel-planner-port-8082)
10. [API Reference — reservation-management](#api-reference--reservation-management-port-8083)
11. [API Reference — reimbursement-management](#api-reference--reimbursement-management-port-8084)
12. [Business Rules](#business-rules)
13. [Database Details](#database-details)
14. [Error Handling](#error-handling)
15. [End-to-End Test Flow](#end-to-end-test-flow)

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Java 21 |
| Framework | Spring Boot 3.5.7 |
| Security | Spring Security 6 + JWT (JJWT 0.12.6, HMAC-SHA256) |
| ORM | Spring Data JPA / Hibernate |
| Database (dev) | H2 (TCP mode for shared DB; file mode for independent DBs) |
| Database (prod) | MySQL (commented out in all `application.properties`) |
| HTTP Clients | Spring Cloud OpenFeign |
| Build | Gradle (system install — wrapper JAR not committed) |
| API Docs | Springdoc OpenAPI (Swagger UI) |
| Utilities | Lombok |

---

## Microservice Overview

| Service | Port | Responsibility |
|---|---|---|
| **account-management** | 8081 | Employee & grade CRUD. Hosts the H2 TCP server on port 9092. Seeds default employees and grades on first startup. |
| **auth-service** | 8080 | Centralised login, token refresh, logout, and blacklist check. All other services call its blacklist endpoint on every request. |
| **travel-planner** | 8082 | Travel request lifecycle (create → approve/reject) and budget calculation. |
| **reservation-management** | 8083 | TravelDeskExe uploads flight/train/bus/cab/hotel booking confirmations (PDF). Employees can track and download bookings. |
| **reimbursement-management** | 8084 | Employees submit expense invoices (PDF). TravelDeskExe approves or rejects each claim. |

---

## Getting Started

### Prerequisites

- Java 21
- Gradle (system install — `gradle/wrapper/gradle-wrapper.jar` is **not** committed)

### Mandatory Startup Order

Services must be started in this exact order. Each step depends on the previous one being up:

```
1. account-management  (port 8081) ← starts H2 TCP server on port 9092 — all others depend on it
2. auth-service        (port 8080) ← connects to account-management's H2 via TCP
3. travel-planner      (port 8082) ← has its own H2 DB; calls account-management + auth-service
4. reservation-management (port 8083) ← has its own H2 DB; calls travel-planner + auth-service
5. reimbursement-management (port 8084) ← has its own H2 DB; calls travel-planner + account-management + auth-service
```

### Running a Service

```bash
# From within the service directory (e.g., cd account-management)
gradle bootRun    # start the service
gradle build      # compile and run tests
gradle test       # run tests only
gradle clean      # clean build output
```

### First Startup

- **account-management** seeds the database with default employees (HR, TravelDeskExe, Employee) and grades (Grade-1, Grade-2, Grade-3) on first run.
- **travel-planner** seeds 8 location records (Mumbai, Delhi, Bangalore, Chennai, Hyderabad, Pune, Kolkata, Ahmedabad).
- **reservation-management** seeds 5 reservation type records (Flight, Train, Bus, Cab, Hotel).
- **reimbursement-management** seeds 4 reimbursement type records (Food, Water, Laundry, LocalTravel).

---

## Default Credentials

Seeded by **account-management** on first startup. Use these to log in via auth-service `POST /login`.

| Role | Email | Password | Employee ID |
|---|---|---|---|
| HR | `admin.hr@cognizant.com` | `Admin@123` | 100000 |
| TravelDeskExe | `desk.exec@cognizant.com` | `Exec@123` | 100001 |
| Employee | `john.employee@cognizant.com` | `Employee@123` | 100002 |

---

## Authentication & Token Lifecycle

All tokens are issued by **auth-service** (`POST http://localhost:8080/login`). Every other service validates tokens locally and also calls auth-service's blacklist endpoint on each request.

### Shared JWT Secret

All five services must have the same secret in their `application.properties`:

```properties
jwt.secret=etdTravelDeskJwtSecretKey1234567890ABCDEF
```

Changing this in any one service immediately invalidates all active tokens across the entire system.

### Token Structure (JWT)

```json
{
  "sub": "admin.hr@cognizant.com",
  "role": "HR",
  "iat": 1749135600,
  "exp": 1749139200
}
```

| Claim | Value |
|---|---|
| `sub` | Employee email address |
| `role` | `"HR"` / `"Employee"` / `"TravelDeskExe"` |
| `iat` | Issued-at timestamp (Unix seconds) |
| `exp` | Expiry timestamp (1 hour after `iat`) |

### Token Lifecycle

```
POST /login
  → accessToken  (JWT, 1 hour)   — use in Authorization: Bearer header on all API calls
  → refreshToken (UUID, 7 days)  — store securely; only send to POST /auth/refresh

When accessToken expires (service returns 403):
  → POST /auth/refresh with { "refreshToken": "..." }
  → returns new accessToken + new refreshToken (old refresh token is deleted)
  → save both new tokens immediately

When refreshToken expires (POST /auth/refresh returns 400):
  → must POST /login again

POST /auth/logout
  → deletes refreshToken
  → blacklists accessToken (all services reject it immediately on next call)
```

### How Other Services Validate Tokens

Every request to travel-planner, reservation-management, and reimbursement-management goes through:

```
1. Extract Bearer token from Authorization header
2. Call GET http://localhost:8080/auth/blacklist/check?token=... → if true → 403
3. Validate JWT signature + expiry with shared secret
4. Extract role claim → set in SecurityContext
```

If auth-service is unreachable at step 2, the blacklist check is skipped (fail-open) and only local validation applies.

---

## Role Permissions Matrix

| Endpoint | HR | Employee | TravelDeskExe |
|---|:---:|:---:|:---:|
| **account-management** | | | |
| `GET /api/grades` | ✅ | ✅ | ✅ |
| `GET /api/employees` | ✅ | ✅ | ✅ |
| `GET /api/employees/{id}` | ✅ | ✅ | ✅ |
| `POST /api/employees` | ✅ | ❌ | ❌ |
| `PUT /api/employees/{id}` | ✅ | ❌ | ❌ |
| `DELETE /api/employees/{id}` | ✅ | ❌ | ❌ |
| **auth-service** (all open) | | | |
| `POST /login` | ✅ | ✅ | ✅ |
| `POST /auth/refresh` | ✅ | ✅ | ✅ |
| `POST /auth/logout` | ✅ | ✅ | ✅ |
| `GET /auth/blacklist/check` | ✅ | ✅ | ✅ |
| **travel-planner** | | | |
| `GET /api/travelrequests/locations` | ✅ | ✅ | ✅ |
| `GET /api/travelrequests/{trid}` | ✅ | ✅ | ✅ |
| `POST /api/travelrequests/new` | ❌ | ✅ | ❌ |
| `GET /api/travelrequests/{hrId}/pending` | ✅ | ❌ | ❌ |
| `PUT /api/travelrequests/{trid}/update` | ✅ | ❌ | ❌ |
| `POST /api/travelrequests/calculatebudget` | ✅ | ❌ | ❌ |
| **reservation-management** | | | |
| `GET /api/reservations/types` | ✅ | ✅ | ✅ |
| `POST /api/reservations/add` | ❌ | ❌ | ✅ |
| `GET /api/reservations/track/{travelRequestId}` | ❌ | ✅ | ❌ |
| `GET /api/reservations/{reservationId}` | ❌ | ✅ | ❌ |
| `GET /api/reservations/{reservationId}/download` | ❌ | ✅ | ❌ |
| **reimbursement-management** | | | |
| `GET /api/reimbursements/types` | ✅ | ✅ | ✅ |
| `POST /api/reimbursements/add` | ❌ | ✅ | ❌ |
| `GET /api/reimbursements/{travelRequestId}/requests` | ✅ | ✅ | ✅ |
| `GET /api/reimbursements/{reimbursementId}` | ✅ | ✅ | ✅ |
| `PUT /api/reimbursements/{reimbursementId}/process` | ❌ | ❌ | ✅ |

---

## API Reference — account-management (Port 8081)

Base URL: `http://localhost:8081`

All endpoints require `Authorization: Bearer <token>` except `/login`, `/auth/refresh`, `/auth/logout`.

---

### GET /api/grades

Returns all available employee grades.

**Auth:** Any authenticated role

**Response `200`:**
```json
[
  { "id": 1, "name": "Grade-1" },
  { "id": 2, "name": "Grade-2" },
  { "id": 3, "name": "Grade-3" }
]
```

> Lower `id` = higher seniority. Grade-1 is the most senior.

---

### GET /api/employees

Returns all employees.

**Auth:** Any authenticated role

**Response `200`:** Array of employee objects.

---

### GET /api/employees/{id}

Returns a single employee by ID.

**Auth:** Any authenticated role

**Path variable:** `id` (Long) — employee ID (6-digit, e.g., `100002`)

**Response `200`:**
```json
{
  "employeeId": 100002,
  "firstName": "John",
  "emailAddress": "john.employee@cognizant.com",
  "role": "Employee",
  "accessGranted": true,
  "gradeName": "Grade-3"
}
```

**Response `404`:** Employee not found

---

### POST /api/employees

Creates a new employee.

**Auth:** HR only

**Request body:**
```json
{
  "firstName": "Jane",
  "emailAddress": "jane.smith@cognizant.com",
  "role": "Employee",
  "gradeId": 3
}
```

> `emailAddress` must end with `@cognizant.com`.
> TravelDeskExe is always force-assigned to Grade-1 regardless of `gradeId`.
> Password is auto-generated (BCrypt-12) by the service.

**Response `200`:** Created employee object.

**Possible errors:**
| Status | Reason |
|---|---|
| 400 | Email does not end with `@cognizant.com` |
| 400 | Grade not found |
| 403 | Not HR |

---

### PUT /api/employees/{id}

Updates an existing employee. Grade change is validated against grade-change rules.

**Auth:** HR only

**Request body:** Same structure as POST.

> Grade changes are subject to strict rules — see [Grade Change Business Rules](#br-grade-change-rules).

**Possible errors:**
| Status | Reason |
|---|---|
| 400 | Grade downgrade attempted |
| 400 | Grade change within 2 years of joining |
| 400 | Grade change within 1 year of last change |
| 404 | Employee not found |
| 403 | Not HR |

---

### DELETE /api/employees/{id}

Deletes an employee.

**Auth:** HR only

**Response `200`:** Success message.

---

## API Reference — auth-service (Port 8080)

Base URL: `http://localhost:8080`

**All endpoints are open** — no `Authorization` header required.

---

### POST /login

Authenticates credentials and returns a JWT access token + refresh token.

**Request:**
```json
{
  "emailAddress": "admin.hr@cognizant.com",
  "password": "Admin@123"
}
```

**Response `200`:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9...",
  "refreshToken": "a3f9b2c1-d4e5-6f78-90ab-cdef12345678",
  "emailAddress": "admin.hr@cognizant.com",
  "role": "HR"
}
```

> Store `token` in memory and attach it as `Authorization: Bearer <token>` on every subsequent API call.
> Store `refreshToken` securely and only send it to `POST /auth/refresh`.

**Possible errors:**
| Status | Reason |
|---|---|
| 400 | Invalid email or password |
| 404 | Employee not found |

---

### POST /auth/refresh

Rotates both tokens. The old refresh token is permanently deleted and a new pair is issued.

**Request:**
```json
{
  "refreshToken": "a3f9b2c1-d4e5-6f78-90ab-cdef12345678"
}
```

**Response `200`:** Same structure as `POST /login` — save **both** new tokens immediately.

> Call this whenever any ETD service returns `403` due to an expired access token.

**Possible errors:**
| Status | Reason |
|---|---|
| 400 | Invalid or expired refresh token |

---

### POST /auth/logout

Deletes the refresh token and blacklists the access token.

**Headers:**
```
Authorization: Bearer <accessToken>   ← required to blacklist the access token
Content-Type: application/json
```

**Request:**
```json
{
  "refreshToken": "a3f9b2c1-d4e5-6f78-90ab-cdef12345678"
}
```

**Response `204 No Content`**

> The `Authorization` header is optional but strongly recommended. Without it, the refresh token is deleted but the access token remains valid for the remainder of its 1-hour window.
> With the header, the access token is immediately blacklisted — all ETD services reject it on the next call.

---

### GET /auth/blacklist/check

Checks whether an access token has been invalidated via logout.

```
GET /auth/blacklist/check?token=eyJhbGciOiJIUzI1NiJ9...
```

**Response `200`:**
```json
true    // token is blacklisted — reject the request
false   // token is valid (not blacklisted)
```

> This endpoint is called internally by travel-planner, reservation-management, and reimbursement-management on every incoming request. Frontend clients do not call it directly.

---

## API Reference — travel-planner (Port 8082)

Base URL: `http://localhost:8082`

All endpoints require `Authorization: Bearer <token>`.

---

### GET /api/travelrequests/locations

Returns all available travel destinations.

**Auth:** Any authenticated role

**Response `200`:**
```json
[
  { "id": 1, "name": "Mumbai" },
  { "id": 2, "name": "Delhi" },
  { "id": 3, "name": "Bangalore" },
  { "id": 4, "name": "Chennai" },
  { "id": 5, "name": "Hyderabad" },
  { "id": 6, "name": "Pune" },
  { "id": 7, "name": "Kolkata" },
  { "id": 8, "name": "Ahmedabad" }
]
```

---

### POST /api/travelrequests/new

Raises a new travel request.

**Auth:** Employee only

**Request:**
```json
{
  "raisedByEmployeeId": 100002,
  "toBeApprovedByHrId": 100000,
  "fromDate": 1782864000000,
  "toDate": 1783641600000,
  "purposeOfTravel": "Client meeting and project review",
  "locationId": 3,
  "priority": "TWO"
}
```

| Field | Notes |
|---|---|
| `raisedByEmployeeId` | Must exist, must have `Employee` role, must match the logged-in user |
| `toBeApprovedByHrId` | Must exist, must have `HR` role |
| `fromDate` / `toDate` | Unix milliseconds |
| `locationId` | Must be a valid location ID from `GET /locations` |
| `priority` | `"ONE"` (max 30 days), `"TWO"` (max 20 days), `"THREE"` (max 10 days) |

**Response `200`:**
```json
{
  "requestId": 1,
  "raisedByEmployeeId": 100002,
  "toBeApprovedByHrId": 100000,
  "requestRaisedOn": 1749135600000,
  "fromDate": 1782864000000,
  "toDate": 1783641600000,
  "purposeOfTravel": "Client meeting and project review",
  "locationName": "Bangalore",
  "requestStatus": "NEW",
  "requestApprovedOn": null,
  "priority": "TWO"
}
```

**Possible errors:**
| Status | Reason |
|---|---|
| 400 | `raisedByEmployeeId` does not match logged-in user |
| 400 | `raisedByEmployeeId` does not have Employee role |
| 400 | `toBeApprovedByHrId` does not have HR role |
| 400 | `fromDate` is after `toDate` |
| 400 | Trip duration exceeds priority cap |
| 400 | Invalid `locationId` |
| 404 | Employee ID not found |
| 403 | Not Employee role |

---

### GET /api/travelrequests/{hrId}/pending

Returns all `NEW` (pending) travel requests assigned to the specified HR.

**Auth:** HR only

```
GET /api/travelrequests/100000/pending
```

**Response `200`:** Array of travel request objects (same structure as POST response).

---

### GET /api/travelrequests/{trid}

Returns full detail of a travel request. Budget fields are included if the budget has been calculated.

**Auth:** Any authenticated role

```
GET /api/travelrequests/1
```

**Response `200` (with budget calculated):**
```json
{
  "requestId": 1,
  "raisedByEmployeeId": 100002,
  "toBeApprovedByHrId": 100000,
  "requestRaisedOn": 1749135600000,
  "fromDate": 1782864000000,
  "toDate": 1783641600000,
  "purposeOfTravel": "Client meeting and project review",
  "locationName": "Bangalore",
  "requestStatus": "APPROVED",
  "requestApprovedOn": 1749222000000,
  "priority": "TWO",
  "travelBudgetAllocationId": 1,
  "approvedBudget": 135000,
  "approvedModeOfTravel": "AIR",
  "approvedHotelStarRating": "3-STAR"
}
```

> Budget fields (`travelBudgetAllocationId`, `approvedBudget`, `approvedModeOfTravel`, `approvedHotelStarRating`) are omitted (`null`) if budget has not been calculated yet.

**Response `404`:** Travel request not found

---

### PUT /api/travelrequests/{trid}/update

Approves or rejects a travel request. Can only be called **once** per request.

**Auth:** HR only

**Request:**
```json
{ "requestStatus": "APPROVED" }
```

> `requestStatus` values: `"APPROVED"` or `"REJECTED"` (case-insensitive input, stored uppercase).

**Response `200`:** Updated travel request object.

**Possible errors:**
| Status | Reason |
|---|---|
| 400 | Request has already been approved or rejected |
| 400 | Invalid status value |
| 404 | Travel request not found |
| 403 | Not HR role |

---

### POST /api/travelrequests/calculatebudget

Calculates and saves the total approved travel budget. Can only be called **once** per request; the request must already be `APPROVED`.

**Auth:** HR only

**Request:**
```json
{
  "travelRequestId": 1,
  "approvedModeOfTravel": "AIR",
  "approvedHotelStarRating": "3-STAR"
}
```

| Field | Allowed values |
|---|---|
| `approvedModeOfTravel` | `"AIR"`, `"TRAIN"`, `"BUS"` |
| `approvedHotelStarRating` | HR: `"5-STAR"` or `"7-STAR"` · Others: `"3-STAR"` or `"5-STAR"` |

**Response `200`:** Total approved budget as a number (Long).
```json
135000
```

> Budget = `dailyRate × numberOfDays`, where daily rate depends on the employee's grade:
> - Grade-1 (most senior): ₹15,000/day
> - Grade-2: ₹12,500/day
> - Grade-3: ₹10,000/day

**Possible errors:**
| Status | Reason |
|---|---|
| 400 | Budget already calculated for this request |
| 400 | HR role not allowed to book the specified hotel star rating |
| 400 | Invalid mode of travel |
| 400 | Invalid employee grade |
| 404 | Travel request not found |
| 400 | Travel request not approved yet |
| 403 | Not HR role |

---

### Date Reference

| Date | Milliseconds |
|---|---|
| 2026-07-01 | `1782864000000` |
| 2026-07-06 | `1783296000000` |
| 2026-07-10 | `1783641600000` |
| 2026-07-20 | `1784505600000` |
| 2026-07-30 | `1785369600000` |

---

## API Reference — reservation-management (Port 8083)

Base URL: `http://localhost:8083`

All endpoints require `Authorization: Bearer <token>`.

---

### GET /api/reservations/types

Returns all reservation types.

**Auth:** Any authenticated role

**Response `200`:**
```json
[
  { "typeId": 1, "typeName": "Flight" },
  { "typeId": 2, "typeName": "Train" },
  { "typeId": 3, "typeName": "Bus" },
  { "typeId": 4, "typeName": "Cab" },
  { "typeId": 5, "typeName": "Hotel" }
]
```

---

### POST /api/reservations/add

Creates a new reservation for an approved travel request. Requires a PDF booking confirmation document.

**Auth:** TravelDeskExe only

**Content-Type:** `multipart/form-data`

| Part | Type | Description |
|---|---|---|
| `reservationRequestDTO` | JSON (`application/json`) | Reservation details |
| `pdfFile` | File | PDF booking confirmation (max **1 MB**, must be PDF) |

**`reservationRequestDTO` fields:**
```json
{
  "reservationDoneByEmployeeId": 100001,
  "travelRequestId": 1,
  "reservationTypeId": 1,
  "reservationDoneWithEntity": "IndiGo Airlines",
  "reservationDate": "2026-07-01",
  "amount": 5000,
  "confirmationId": "PNR123456",
  "remarks": "Window seat requested"
}
```

| Field | Required | Notes |
|---|---|---|
| `reservationDoneByEmployeeId` | Yes | TravelDeskExe employee ID |
| `travelRequestId` | Yes | Travel request must be APPROVED with budget calculated |
| `reservationTypeId` | Yes | ID from `GET /api/reservations/types` |
| `reservationDoneWithEntity` | Yes | Airline/hotel/company name |
| `reservationDate` | Yes | See date rules below |
| `amount` | Yes | INR; must be > 0; must not exceed budget cap |
| `confirmationId` | Yes | PNR / booking reference |
| `remarks` | No | Optional notes |

**Reservation date rules:**
| Type | Rule |
|---|---|
| Train or Bus | `reservationDate` must be exactly **1 day before** the travel request `fromDate` |
| Hotel | `reservationDate` must be the **same day** as the travel request `fromDate` |
| Flight or Cab | No restriction |

**Response `200`:**
```json
{
  "id": 1,
  "reservationDoneByEmployeeId": 100001,
  "travelRequestId": 1,
  "createdOn": "2025-11-20",
  "reservationDoneWithEntity": "IndiGo Airlines",
  "reservationDate": "2026-07-01",
  "amount": 5000,
  "confirmationId": "PNR123456",
  "remarks": "Window seat requested",
  "reservationTypeName": "Flight"
}
```

**Possible errors:**
| Status | Reason |
|---|---|
| 400 | Amount is null or ≤ 0 |
| 400 | Invalid reservation type ID |
| 400 | Travel request not found or unreachable |
| 400 | Travel request not APPROVED |
| 400 | Budget not yet calculated |
| 400 | Amount exceeds budget cap for this type |
| 400 | Reservation date violates date rules |
| 400 | Duplicate reservation for same type and travel request |
| 400 | PDF content-type is not `application/pdf` |
| 403 | Not TravelDeskExe role |
| 413 | PDF file exceeds 1 MB |

---

### GET /api/reservations/track/{travelRequestId}

Returns all reservations for a specific travel request.

**Auth:** Employee only

**Response `200`:** Array of reservation response objects.

**Response `404`:** No reservations found for the given travel request ID.

---

### GET /api/reservations/{reservationId}

Returns a single reservation by its ID.

**Auth:** Employee only

**Response `200`:** Single reservation response object.

**Response `404`:** Reservation not found.

---

### GET /api/reservations/{reservationId}/download

Downloads the PDF booking confirmation for a reservation.

**Auth:** Employee only

**Response `200`:**
- Content-Type: `application/pdf`
- Body: Raw PDF bytes

**Response `404`:** No document found for the given reservation ID.

---

## API Reference — reimbursement-management (Port 8084)

Base URL: `http://localhost:8084`

All endpoints require `Authorization: Bearer <token>`.

---

### GET /api/reimbursements/types

Returns all reimbursement expense types.

**Auth:** Any authenticated role

**Response `200`:**
```json
[
  { "id": 1, "type": "Food" },
  { "id": 2, "type": "Water" },
  { "id": 3, "type": "Laundry" },
  { "id": 4, "type": "LocalTravel" }
]
```

---

### POST /api/reimbursements/add

Submits a new reimbursement claim with an invoice PDF.

**Auth:** Employee only

**Content-Type:** `multipart/form-data`

| Part | Type | Description |
|---|---|---|
| `reimbursementRequestDTO` | JSON (`application/json`) | Claim details |
| `pdfFile` | File | Invoice PDF (max **256 KB**, must be PDF) |

**`reimbursementRequestDTO` fields:**
```json
{
  "travelRequestId": 1,
  "requestRaisedByEmployeeId": 100002,
  "reimbursementTypeId": 1,
  "invoiceNo": "REST-001",
  "invoiceDate": "2026-07-05",
  "invoiceAmount": 1200
}
```

| Field | Required | Notes |
|---|---|---|
| `travelRequestId` | Yes | Travel request this expense belongs to |
| `requestRaisedByEmployeeId` | Yes | Must match `raisedByEmployeeId` in the travel request |
| `reimbursementTypeId` | Yes | ID from `GET /api/reimbursements/types` |
| `invoiceNo` | Yes | Invoice/receipt number |
| `invoiceDate` | Yes | Must be within the travel request's `fromDate`–`toDate` |
| `invoiceAmount` | Yes | INR; must be within the allowed range for the type |

**Amount limits by type:**
| Type | Minimum | Maximum | Daily Combined Cap |
|---|---|---|---|
| Food | ₹1,000 | ₹1,500 | Food + Water combined ≤ ₹1,500/day |
| Water | ₹1,000 | ₹1,500 | Food + Water combined ≤ ₹1,500/day |
| Laundry | ₹250 | ₹500 | ≤ ₹500/day |
| LocalTravel | ₹0 | ₹1,000 | ≤ ₹1,000/day |

**Response `200`:**
```json
{
  "id": 1,
  "travelRequestId": 1,
  "requestRaisedByEmployeeId": 100002,
  "requestDate": "2026-07-15",
  "reimbursementType": "Food",
  "invoiceNo": "REST-001",
  "invoiceDate": "2026-07-05",
  "invoiceAmount": 1200,
  "documentUrl": "1749300000000_invoice.pdf",
  "requestProcessedOn": null,
  "requestProcessedByEmployeeId": null,
  "status": "New",
  "remarks": null
}
```

**Possible errors:**
| Status | Reason |
|---|---|
| 400 | PDF content-type is not `application/pdf` |
| 400 | Invalid reimbursement type ID |
| 400 | Travel request not found |
| 400 | `requestRaisedByEmployeeId` does not match who raised the travel request |
| 400 | Invoice date is outside travel request `fromDate`–`toDate` |
| 400 | Invoice amount is outside the allowed range |
| 400 | Daily cumulative limit exceeded for the type on that date |
| 403 | Not Employee role |
| 413 | PDF exceeds 256 KB |

---

### GET /api/reimbursements/{travelRequestId}/requests

Returns all reimbursement claims for a travel request.

**Auth:** Any authenticated role

**Response `200`:** Array of reimbursement response objects.

**Response `404`:** No reimbursements found for that travel request ID.

---

### GET /api/reimbursements/{reimbursementId}

Returns a single reimbursement claim by ID.

**Auth:** Any authenticated role

**Response `200`:** Single reimbursement response object.

**Response `404`:** Reimbursement not found.

---

### PUT /api/reimbursements/{reimbursementId}/process

Approves or rejects a reimbursement claim.

**Auth:** TravelDeskExe only

**Request:**
```json
{
  "requestProcessedByEmployeeId": 100001,
  "status": "Approved",
  "remarks": ""
}
```

| Field | Required | Notes |
|---|---|---|
| `requestProcessedByEmployeeId` | Yes | Must be a TravelDeskExe in account-management |
| `status` | Yes | Exactly `"Approved"` or `"Rejected"` (case-sensitive) |
| `remarks` | Conditional | Required when `status = "Rejected"` |

**Response `200`:** Updated reimbursement object with `status`, `requestProcessedOn`, and `requestProcessedByEmployeeId` filled in.

**Possible errors:**
| Status | Reason |
|---|---|
| 400 | `status` is not `"Approved"` or `"Rejected"` |
| 400 | `status = "Rejected"` but `remarks` is empty |
| 400 | Request has already been processed |
| 400 | `requestProcessedByEmployeeId` is not a TravelDeskExe |
| 403 | Not TravelDeskExe role |
| 404 | Reimbursement not found |

---

## Business Rules

### BR-1 — Employee Email

All employee email addresses must end with `@cognizant.com`. Validated on create and update.

---

### BR-2 — TravelDeskExe Grade

A TravelDeskExe employee is always assigned Grade-1 on creation, regardless of the `gradeId` submitted in the request.

---

### BR-3 — Grade Change Rules

Applies when HR updates an employee's grade:

1. **Upgrade only** — Grade can only move to a higher seniority (lower `id`). Downgrading is not allowed.
2. **2-year freeze** — No grade change within the first 2 years of the employee's joining date (= earliest grade history record).
3. **Once per year** — No grade change within 1 year of the most recent grade change.

---

### BR-4 — Travel Request: Priority vs. Maximum Duration

| Priority | Maximum Trip Length |
|---|---|
| `ONE` (highest) | 30 days |
| `TWO` | 20 days |
| `THREE` (lowest) | 10 days |

---

### BR-5 — Travel Request: Identity Check

The `raisedByEmployeeId` in the travel request must exactly match the email of the currently logged-in user. An employee cannot raise a travel request on behalf of another employee.

---

### BR-6 — Budget Calculation: Grade → Daily Cap

| Grade | Seniority | Daily Budget Cap |
|---|---|---|
| Grade-1 | Most senior | ₹15,000/day |
| Grade-2 | Mid | ₹12,500/day |
| Grade-3 | Most junior | ₹10,000/day |

Total approved budget = `dailyRate × numberOfDays`.

---

### BR-7 — Budget Calculation: Hotel Rating by Role

| Role | Allowed Hotel Ratings |
|---|---|
| HR | `5-STAR`, `7-STAR` |
| Employee / TravelDeskExe | `3-STAR`, `5-STAR` |

---

### BR-8 — Reservations: Budget Allocation

The total approved budget from travel-planner is split as:

```
reservationsBudget = approvedBudget × 70%
```

Maximum allowed amount per reservation type within `reservationsBudget`:

| Type | Max % |
|---|---|
| Flight, Train, or Bus | 35% of reservationsBudget |
| Cab | 15% of reservationsBudget |
| Hotel | 50% of reservationsBudget |

**Example:** If `approvedBudget = ₹100,000`:
- `reservationsBudget = ₹70,000`
- Max flight = ₹70,000 × 35% = ₹24,500
- Max cab = ₹70,000 × 15% = ₹10,500
- Max hotel = ₹70,000 × 50% = ₹35,000

---

### BR-9 — Reservations: One Per Category Per Travel Request

For each travel request:
- Only **one** transport reservation (Flight, Train, or Bus) is allowed
- Only **one** Cab reservation is allowed
- Only **one** Hotel reservation is allowed

---

### BR-10 — Reservations: Advance Booking Dates

| Reservation Type | Required Date |
|---|---|
| Train or Bus | Exactly **1 day before** the travel `fromDate` |
| Hotel | **Same day** as the travel `fromDate` |
| Flight or Cab | No restriction |

---

### BR-11 — Reservations: Budget Must Be Calculated First

The travel request must have an `approvedBudget` (i.e., `POST /calculatebudget` was called) before any reservation can be added.

---

### BR-12 — Reimbursement: Employee Must Match

The `requestRaisedByEmployeeId` in a reimbursement submission must match the `raisedByEmployeeId` in the corresponding travel request. Cross-employee claims are rejected.

---

### BR-13 — Reimbursement: Invoice Date Bounds

The `invoiceDate` must fall on or between the travel request's `fromDate` and `toDate` (both inclusive). Expenses outside the trip dates are not claimable.

---

### BR-14 — Reimbursement: Per-Invoice Amount Range

| Type | Minimum | Maximum |
|---|---|---|
| Food | ₹1,000 | ₹1,500 |
| Water | ₹1,000 | ₹1,500 |
| Laundry | ₹250 | ₹500 |
| LocalTravel | ₹0 | ₹1,000 |

---

### BR-15 — Reimbursement: Daily Cumulative Limits

In addition to per-invoice range limits, the **combined total** for the same category on the same `invoiceDate` cannot exceed:

| Category | Daily Combined Limit |
|---|---|
| Food + Water (combined) | ₹1,500/day |
| Laundry | ₹500/day |
| LocalTravel | ₹1,000/day |

**Example:** Food = ₹1,200 already claimed on July 5th → Water on July 5th is blocked (₹1,200 + any Water ≥ ₹1,000 would exceed ₹1,500).

---

### BR-16 — Reimbursement: Status Must Be "New" to Process

A reimbursement can only be approved or rejected once. Any attempt to process an already-processed claim returns an error stating the date it was processed.

---

### BR-17 — Reimbursement: Status Values Are Case-Sensitive

Process status must be exactly `"Approved"` or `"Rejected"`. Values like `"APPROVED"`, `"approved"`, or `"approved"` are rejected.

---

### BR-18 — Reimbursement: Rejection Requires Remarks

When setting status to `"Rejected"`, the `remarks` field is mandatory and must be non-empty.

---

### BR-19 — PDF Requirements

| Service | Type | Max Size |
|---|---|---|
| reservation-management | Booking confirmation | 1 MB (1,048,576 bytes) |
| reimbursement-management | Invoice proof | 256 KB (262,144 bytes) |

Both services require Content-Type `application/pdf`. Non-PDF files are rejected.

---

## Database Details

| Service | Type | URL | ddl-auto | Notes |
|---|---|---|---|---|
| account-management | H2 TCP server | `jdbc:h2:tcp://localhost:9092/~/data/account_management` | `update` | Schema owner for shared DB |
| auth-service | Shared H2 TCP | Same as above | `none` | Reads/writes data; never creates tables |
| travel-planner | H2 file | `jdbc:h2:file:~/data/travel_planner;AUTO_SERVER=TRUE` | `update` | Own DB |
| reservation-management | H2 file | `jdbc:h2:file:~/data/reservation_types;AUTO_SERVER=TRUE` | `update` | Own DB |
| reimbursement-management | H2 file | `jdbc:h2:file:~/data/reimbursement_management;AUTO_SERVER=TRUE` | `update` | Own DB |

H2 Console credentials: username `sa`, password *(blank)*.

### Shared Database Tables (hosted by account-management)

| Table | Owned By | Who Accesses |
|---|---|---|
| `employees` | account-management | account-management (full CRUD), auth-service (read-only) |
| `grades` | account-management | account-management only |
| `grade_history` | account-management | account-management only |
| `refresh_tokens` | auth-service | auth-service (full CRUD) |
| `token_blacklist` | auth-service | auth-service (full CRUD) |

### Cross-Service References (no DB foreign keys)

These fields reference entities in other microservices. Validated at the application layer via Feign — no DB-level constraints:

| Service | Column | References |
|---|---|---|
| reservation-management | `reservations.travel_request_id` | travel-planner `travel_requests.request_id` |
| reservation-management | `reservations.reservation_done_by_employee_id` | account-management `employees.employee_id` |
| reimbursement-management | `reimbursement_requests.travel_request_id` | travel-planner `travel_requests.request_id` |
| reimbursement-management | `reimbursement_requests.request_raised_by_employee_id` | account-management `employees.employee_id` |
| travel-planner | `travel_requests.raised_by_employee_id` | account-management `employees.employee_id` |
| travel-planner | `travel_requests.to_be_approved_by_hr_id` | account-management `employees.employee_id` |

---

## Error Handling

All services return errors in a consistent `ErrorDTO` format:

```json
{
  "message": "Human-readable description of the error",
  "fieldName": "The field that caused the error (may be null)",
  "status": "BAD_REQUEST"
}
```

### HTTP Status Codes

| Code | Meaning | When |
|---|---|---|
| 200 | OK | Success |
| 204 | No Content | Successful logout |
| 400 | Bad Request | Validation failure, business rule violation, invalid input |
| 403 | Forbidden | Missing/expired/blacklisted token, or insufficient role |
| 404 | Not Found | Entity does not exist |
| 413 | Payload Too Large | PDF file exceeds the size limit |

---

## End-to-End Test Flow

Complete walkthrough of the ETD system from login to reimbursement:

```
Step 1: Login as Employee
  POST http://localhost:8080/login
  { "emailAddress": "john.employee@cognizant.com", "password": "Employee@123" }
  → copy employeeToken and refreshToken

Step 2: Login as HR
  POST http://localhost:8080/login
  { "emailAddress": "admin.hr@cognizant.com", "password": "Admin@123" }
  → copy hrToken

Step 3: Login as TravelDeskExe
  POST http://localhost:8080/login
  { "emailAddress": "desk.exec@cognizant.com", "password": "Exec@123" }
  → copy deskToken

Step 4: Get available locations  (use employeeToken)
  GET http://localhost:8082/api/travelrequests/locations
  → pick a locationId

Step 5: Raise a travel request  (use employeeToken)
  POST http://localhost:8082/api/travelrequests/new
  {
    "raisedByEmployeeId": 100002,
    "toBeApprovedByHrId": 100000,
    "fromDate": 1782864000000,
    "toDate": 1783641600000,
    "purposeOfTravel": "Client meeting",
    "locationId": 3,
    "priority": "TWO"
  }
  → copy requestId

Step 6: HR checks pending requests  (use hrToken)
  GET http://localhost:8082/api/travelrequests/100000/pending

Step 7: HR approves the request  (use hrToken)
  PUT http://localhost:8082/api/travelrequests/{requestId}/update
  { "requestStatus": "APPROVED" }

Step 8: HR calculates budget  (use hrToken)
  POST http://localhost:8082/api/travelrequests/calculatebudget
  {
    "travelRequestId": {requestId},
    "approvedModeOfTravel": "AIR",
    "approvedHotelStarRating": "3-STAR"
  }
  → get total approved budget (e.g., 135000)

Step 9: TravelDeskExe adds a flight reservation  (use deskToken, multipart)
  POST http://localhost:8083/api/reservations/add
  reservationRequestDTO: {
    "reservationDoneByEmployeeId": 100001,
    "travelRequestId": {requestId},
    "reservationTypeId": 1,
    "reservationDoneWithEntity": "IndiGo Airlines",
    "reservationDate": "2026-07-01",
    "amount": 5000,
    "confirmationId": "PNR123456"
  }
  pdfFile: <upload PDF ≤ 1MB>
  → copy reservationId

Step 10: Employee tracks reservations  (use employeeToken)
  GET http://localhost:8083/api/reservations/track/{requestId}

Step 11: Employee downloads booking PDF  (use employeeToken)
  GET http://localhost:8083/api/reservations/{reservationId}/download

Step 12: Employee submits food reimbursement  (use employeeToken, multipart)
  POST http://localhost:8084/api/reimbursements/add
  reimbursementRequestDTO: {
    "travelRequestId": {requestId},
    "requestRaisedByEmployeeId": 100002,
    "reimbursementTypeId": 1,
    "invoiceNo": "REST-001",
    "invoiceDate": "2026-07-05",
    "invoiceAmount": 1200
  }
  pdfFile: <upload PDF ≤ 256KB>
  → copy reimbursementId

Step 13: TravelDeskExe approves reimbursement  (use deskToken)
  PUT http://localhost:8084/api/reimbursements/{reimbursementId}/process
  {
    "requestProcessedByEmployeeId": 100001,
    "status": "Approved",
    "remarks": ""
  }

Step 14: View full travel request detail  (any token)
  GET http://localhost:8082/api/travelrequests/{requestId}

Step 15: Logout  (use employeeToken)
  POST http://localhost:8080/auth/logout
  Authorization: Bearer <employeeToken>
  { "refreshToken": "<refreshToken>" }
```

---

## Swagger UI Quick Reference

| Service | URL |
|---|---|
| account-management | `http://localhost:8081/swagger-ui.html` |
| auth-service | `http://localhost:8080/swagger-ui.html` |
| travel-planner | `http://localhost:8082/swagger-ui.html` |
| reservation-management | `http://localhost:8083/swagger-ui.html` |
| reimbursement-management | `http://localhost:8084/swagger-ui.html` |

---

## Related Services

| Service | Port | Responsibility |
|---|---|---|
| **account-management** | 8081 | Employee & grade CRUD + H2 TCP server host |
| **auth-service** | 8080 | Login, token refresh, logout, blacklist check |
| **travel-planner** | 8082 | Travel request lifecycle + budget calculation |
| **reservation-management** | 8083 | Reservation booking + PDF document management |
| **reimbursement-management** | 8084 | Expense claim submission + TravelDeskExe processing |
