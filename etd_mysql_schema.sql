-- =====================================================================================
--  Employee Travel Desk (ETD) -- MySQL Schema
-- =====================================================================================
--  Reference DDL that mirrors the JPA / Hibernate entities currently auto-created on H2
--  (spring.jpa.hibernate.ddl-auto=update). No application code was changed to produce
--  this file -- it simply reproduces the same schema in MySQL syntax.
--
--  The ETD backend has FIVE microservices but only FOUR physical databases:
--    1. account_management        -> owned by account-management; auth-service SHARES it
--                                    (auth-service has ddl-auto=none and creates no DB of
--                                    its own; refresh_tokens + token_blacklist live here).
--    2. travel_planner            -> owned by travel-planner
--    3. reservation_types         -> owned by reservation-management
--                                    (NOTE: the database name really is "reservation_types",
--                                     and it also contains a TABLE called reservation_types).
--    4. reimbursement_management  -> owned by reimbursement-management
--
--  Column type mapping (Java/JPA  ->  MySQL):
--    Long              -> BIGINT
--    String            -> VARCHAR(255)        (VARCHAR(512) only where length is set in code)
--    Boolean           -> TINYINT(1)          (0 = false, 1 = true)
--    java.util.Date    -> DATETIME(6)         (Hibernate maps util.Date as a timestamp)
--    java.sql.Date     -> DATE
--    LocalDateTime     -> DATETIME(6)
--
--  Notes:
--    * Identity PKs use AUTO_INCREMENT. The employees table starts at 100000 to match the
--      JPA @SequenceGenerator (initialValue = 100000) -> employee IDs are always 6 digits.
--    * CHECK constraints reproduce the entity @Check annotations (enforced on MySQL 8.0.16+).
--    * Columns are nullable unless the entity declares nullable=false (tokens / expiry dates).
--    * Cross-service ID columns (e.g. raised_by_employee_id, travel_request_id in the
--      reservation / reimbursement services) point at data in ANOTHER database, so -- exactly
--      like the running app -- they are plain BIGINT columns with NO foreign key.
--    * To run a service on MySQL, point its spring.datasource.url at the matching database
--      below (and switch the driver). That is a configuration change only; not done here.
-- =====================================================================================


-- =====================================================================================
--  DATABASE 1 of 4 : account_management
--  Used by: account-management (schema owner) AND auth-service (shared, read/writes data)
--  Tables: grades, employees, grades_history, refresh_tokens, token_blacklist
-- =====================================================================================
CREATE DATABASE IF NOT EXISTS account_management
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE account_management;

-- --- grades -------------------------------------------------------------------------
-- Seeded by DataInitializer: id 1 = Grade-1, 2 = Grade-2, 3 = Grade-3 (lower id = senior)
CREATE TABLE grades (
    id    BIGINT       NOT NULL AUTO_INCREMENT,
    name  VARCHAR(255),
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --- employees ----------------------------------------------------------------------
-- email_address is treated as unique in the application logic but is NOT constrained
-- at the DB level in the current entity (no unique=true), so it is left unconstrained
-- here to faithfully match the generated schema.
CREATE TABLE employees (
    employee_id       BIGINT       NOT NULL AUTO_INCREMENT,
    first_name        VARCHAR(255),
    last_name         VARCHAR(255),
    phone_number      VARCHAR(255),
    email_address     VARCHAR(255),
    role              VARCHAR(255),               -- "HR" / "Employee" / "TravelDeskExe"
    password          VARCHAR(255),               -- BCrypt (strength 12) hash
    access_granted    TINYINT(1),                 -- Boolean (0/1)
    current_grade_id  BIGINT,
    PRIMARY KEY (employee_id),
    CONSTRAINT fk_employees_grade
        FOREIGN KEY (current_grade_id) REFERENCES grades (id)
) ENGINE=InnoDB AUTO_INCREMENT=100000 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --- grades_history -----------------------------------------------------------------
-- Append-only audit log; one row per grade assignment (on create + each change).
CREATE TABLE grades_history (
    id           BIGINT       NOT NULL AUTO_INCREMENT,
    assigned_on  DATETIME(6),
    employee_id  BIGINT,
    grade_id     BIGINT,
    PRIMARY KEY (id),
    CONSTRAINT fk_gh_employee
        FOREIGN KEY (employee_id) REFERENCES employees (employee_id),
    CONSTRAINT fk_gh_grade
        FOREIGN KEY (grade_id) REFERENCES grades (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --- refresh_tokens (owned by auth-service) -----------------------------------------
-- One active refresh token per employee (@OneToOne -> employee_id is unique).
CREATE TABLE refresh_tokens (
    id           BIGINT        NOT NULL AUTO_INCREMENT,
    token        VARCHAR(255)  NOT NULL,
    expiry_date  DATETIME(6)   NOT NULL,
    employee_id  BIGINT,
    PRIMARY KEY (id),
    CONSTRAINT uq_refresh_tokens_token    UNIQUE (token),
    CONSTRAINT uq_refresh_tokens_employee UNIQUE (employee_id),
    CONSTRAINT fk_refresh_tokens_employee
        FOREIGN KEY (employee_id) REFERENCES employees (employee_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --- token_blacklist (owned by auth-service) ----------------------------------------
-- Access tokens invalidated via logout; token stores the full JWT (length 512).
CREATE TABLE token_blacklist (
    id           BIGINT        NOT NULL AUTO_INCREMENT,
    token        VARCHAR(512)  NOT NULL,
    expiry_date  DATETIME(6)   NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT uq_token_blacklist_token UNIQUE (token)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================================
--  DATABASE 2 of 4 : travel_planner
--  Owned by: travel-planner
--  Tables: locations, travel_requests, travel_budget_allocations
-- =====================================================================================
CREATE DATABASE IF NOT EXISTS travel_planner
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE travel_planner;

-- --- locations ----------------------------------------------------------------------
-- Seeded with 8 cities: Mumbai, Delhi, Bangalore, Chennai, Hyderabad, Pune, Kolkata, Ahmedabad
CREATE TABLE locations (
    id    BIGINT       NOT NULL AUTO_INCREMENT,
    name  VARCHAR(255),
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --- travel_requests ----------------------------------------------------------------
-- raised_by_employee_id and to_be_approved_by_hr_id reference employees in the
-- account_management database (cross-service) -> no FK here, by design.
CREATE TABLE travel_requests (
    request_id               BIGINT       NOT NULL AUTO_INCREMENT,
    raised_by_employee_id    BIGINT,                       -- cross-service (account_management.employees)
    to_be_approved_by_hr_id  BIGINT,                       -- cross-service (account_management.employees)
    request_raised_on        DATETIME(6),
    from_date                DATETIME(6),
    to_date                  DATETIME(6),
    purpose_of_travel        VARCHAR(255),
    request_status           VARCHAR(255),                 -- "NEW" / "APPROVED" / "REJECTED"
    request_approved_on      DATETIME(6),
    priority                 VARCHAR(255),                 -- "ONE" / "TWO" / "THREE"
    location_id              BIGINT,
    PRIMARY KEY (request_id),
    CONSTRAINT fk_tr_location
        FOREIGN KEY (location_id) REFERENCES locations (id),
    CONSTRAINT chk_tr_date_range CHECK (to_date >= from_date),
    CONSTRAINT chk_tr_status     CHECK (request_status IN ('NEW', 'APPROVED', 'REJECTED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --- travel_budget_allocations ------------------------------------------------------
-- @OneToOne to travel_requests -> travel_request_id is unique.
CREATE TABLE travel_budget_allocations (
    id                          BIGINT       NOT NULL AUTO_INCREMENT,
    approved_budget             BIGINT,                    -- INR
    approved_mode_of_travel     VARCHAR(255),              -- "AIR" / "TRAIN" / "BUS"
    approved_hotel_star_rating  VARCHAR(255),              -- "3-STAR" / "5-STAR" / "7-STAR"
    travel_request_id           BIGINT,
    PRIMARY KEY (id),
    CONSTRAINT uq_tba_travel_request UNIQUE (travel_request_id),
    CONSTRAINT fk_tba_travel_request
        FOREIGN KEY (travel_request_id) REFERENCES travel_requests (request_id),
    CONSTRAINT chk_tba_mode   CHECK (approved_mode_of_travel    IN ('AIR', 'TRAIN', 'BUS')),
    CONSTRAINT chk_tba_rating CHECK (approved_hotel_star_rating IN ('3-STAR', '5-STAR', '7-STAR'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================================
--  DATABASE 3 of 4 : reservation_types
--  Owned by: reservation-management
--  Tables: reservation_types, reservations, reservation_docs
--  (Yes -- the database and one of its tables share the name "reservation_types".)
-- =====================================================================================
CREATE DATABASE IF NOT EXISTS reservation_types
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE reservation_types;

-- --- reservation_types (lookup table) -----------------------------------------------
-- Seeded (in order): 1 Flight, 2 Train, 3 Bus, 4 Cab, 5 Hotel. Do not re-order.
CREATE TABLE reservation_types (
    type_id    BIGINT       NOT NULL AUTO_INCREMENT,
    type_name  VARCHAR(255),
    PRIMARY KEY (type_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --- reservations -------------------------------------------------------------------
-- reservation_done_by_employee_id and travel_request_id are cross-service references.
CREATE TABLE reservations (
    id                             BIGINT       NOT NULL AUTO_INCREMENT,
    reservation_done_by_employee_id BIGINT,                  -- cross-service (account_management.employees)
    travel_request_id              BIGINT,                   -- cross-service (travel_planner.travel_requests)
    created_on                     DATETIME(6),
    reservation_done_with_entity   VARCHAR(255),
    reservation_date               DATETIME(6),
    amount                         BIGINT,                   -- INR
    confirmation_id                VARCHAR(255),
    remarks                        VARCHAR(255),
    reservation_type_id            BIGINT,
    PRIMARY KEY (id),
    CONSTRAINT fk_reservations_type
        FOREIGN KEY (reservation_type_id) REFERENCES reservation_types (type_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --- reservation_docs ---------------------------------------------------------------
-- @OneToOne to reservations -> reservation_id is unique. Stores the PDF filename only.
CREATE TABLE reservation_docs (
    id              BIGINT       NOT NULL AUTO_INCREMENT,
    document_url    VARCHAR(255),
    reservation_id  BIGINT,
    PRIMARY KEY (id),
    CONSTRAINT uq_reservation_docs_reservation UNIQUE (reservation_id),
    CONSTRAINT fk_reservation_docs_reservation
        FOREIGN KEY (reservation_id) REFERENCES reservations (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================================
--  DATABASE 4 of 4 : reimbursement_management
--  Owned by: reimbursement-management
--  Tables: reimbursement_types, reimbursement_requests
--  (These date columns use java.sql.Date in code -> MySQL DATE, not DATETIME.)
-- =====================================================================================
CREATE DATABASE IF NOT EXISTS reimbursement_management
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE reimbursement_management;

-- --- reimbursement_types (lookup table) ---------------------------------------------
-- Seeded (in order): 1 Food, 2 Water, 3 Laundry, 4 LocalTravel.
CREATE TABLE reimbursement_types (
    id    BIGINT       NOT NULL AUTO_INCREMENT,
    type  VARCHAR(255),
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --- reimbursement_requests ---------------------------------------------------------
-- travel_request_id, request_raised_by_employee_id and request_processed_by_employee_id
-- are cross-service references (no FK).
CREATE TABLE reimbursement_requests (
    id                                BIGINT       NOT NULL AUTO_INCREMENT,
    travel_request_id                 BIGINT,                 -- cross-service (travel_planner.travel_requests)
    request_raised_by_employee_id     BIGINT,                 -- cross-service (account_management.employees)
    request_date                      DATE,
    invoice_no                        VARCHAR(255),
    invoice_date                      DATE,
    invoice_amount                    BIGINT,                 -- INR
    document_url                      VARCHAR(255),
    request_processed_on              DATE,
    request_processed_by_employee_id  BIGINT,                 -- cross-service (account_management.employees)
    status                            VARCHAR(255),           -- "New" / "Approved" / "Rejected"
    remarks                           VARCHAR(255),
    reimbursement_type_id             BIGINT,
    PRIMARY KEY (id),
    CONSTRAINT fk_reimbursement_requests_type
        FOREIGN KEY (reimbursement_type_id) REFERENCES reimbursement_types (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================================
--  OPTIONAL : reference / lookup seed data
-- -------------------------------------------------------------------------------------
--  Each service's DataInitializer already inserts this data automatically on startup,
--  so these INSERTs are only needed if you create the schema manually and want the
--  lookup rows present immediately. The three default users (HR / TravelDeskExe /
--  Employee) are NOT seeded here because their passwords are BCrypt-hashed at runtime
--  by account-management's DataInitializer -- start that service to create them.
-- =====================================================================================

-- Grades
USE account_management;
INSERT INTO grades (id, name) VALUES (1, 'Grade-1'), (2, 'Grade-2'), (3, 'Grade-3');

-- Locations
USE travel_planner;
INSERT INTO locations (id, name) VALUES
    (1, 'Mumbai'), (2, 'Delhi'), (3, 'Bangalore'), (4, 'Chennai'),
    (5, 'Hyderabad'), (6, 'Pune'), (7, 'Kolkata'), (8, 'Ahmedabad');

-- Reservation types
USE reservation_types;
INSERT INTO reservation_types (type_id, type_name) VALUES
    (1, 'Flight'), (2, 'Train'), (3, 'Bus'), (4, 'Cab'), (5, 'Hotel');

-- Reimbursement types
USE reimbursement_management;
INSERT INTO reimbursement_types (id, type) VALUES
    (1, 'Food'), (2, 'Water'), (3, 'Laundry'), (4, 'LocalTravel');

-- =====================================================================================
--  End of ETD MySQL schema
-- =====================================================================================
