use account_management;

CREATE TABLE grades (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(25)
);

INSERT INTO grades (Id, Name) VALUES
(1, 'Grade-1'),
(2, 'Grade-2'),
(3, 'Grade-3');

CREATE TABLE employees (
  employee_id INT PRIMARY KEY AUTO_INCREMENT,
  first_name VARCHAR(15),
  last_name VARCHAR(10),
  phone_number VARCHAR(10) UNIQUE,
  -- Check constraint for exactly 10 digit phone numbers
  CONSTRAINT CHK_PhoneNumber CHECK (phone_number REGEXP '^[0-9]{10}$'),
  email_address VARCHAR(50) UNIQUE,
  role VARCHAR(15) CHECK (role IN ('Employee', 'HR', 'TravelDeskExe')),
  current_grade_id INT,
  access_granted BOOLEAN DEFAULT TRUE,
  FOREIGN KEY (current_grade_id) REFERENCES Grades(id)
)AUTO_INCREMENT=100000;

CREATE TABLE grades_history (
  id INT PRIMARY KEY AUTO_INCREMENT,
  assigned_on DATETIME,
  employee_id INT,
  grade_id INT,
  FOREIGN KEY (employee_id) REFERENCES Employees(employee_id),
  FOREIGN KEY (grade_id) REFERENCES Grades(id)
);

DESC grades;
DESC employees;
DESC grades_history;

SELECT * FROM grades;
SELECT * FROM employees;
SELECT * FROM grades_history;
