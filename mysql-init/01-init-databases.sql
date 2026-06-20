-- ETD: create all four databases on first MySQL initialization.
-- (Belt-and-suspenders: every service's JDBC URL also uses createDatabaseIfNotExist=true.)
CREATE DATABASE IF NOT EXISTS account_management;
CREATE DATABASE IF NOT EXISTS travel_planner;
CREATE DATABASE IF NOT EXISTS reservation_management;
CREATE DATABASE IF NOT EXISTS reimbursement_management;
