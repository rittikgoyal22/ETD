use reimbursement_management;

CREATE TABLE reimbursement_types (
    id INT PRIMARY KEY AUTO_INCREMENT,
    type VARCHAR(25)
);

INSERT INTO reimbursement_types (type) VALUES
('Food'),
('Water'),
('Laundry'),
('LocalTravel');

CREATE TABLE reimbursement_requests (
    id INT PRIMARY KEY AUTO_INCREMENT,
    travel_request_id INT,
    request_raised_by_employee_id INT,
    request_date DATE DEFAULT (CURRENT_DATE),
    reimbursement_type_id INT,
    invoice_no VARCHAR(20),
    invoice_date DATE,
    invoice_amount INT,
    document_url VARCHAR(100),
    request_processed_on DATE,
    request_processed_by_employee_id INT,
    status VARCHAR(10),
    remarks VARCHAR(100),
    FOREIGN KEY (reimbursement_type_id) REFERENCES reimbursement_types(id),
    CHECK (status IN ('New', 'Approved', 'Rejected'))
);

select * from reimbursement_requests;
select * from reimbursement_types;
