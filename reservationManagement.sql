use reservation_management;

CREATE TABLE reservation_types (
    type_id INT PRIMARY KEY AUTO_INCREMENT,
    type_name VARCHAR(25)
);

INSERT INTO reservation_types (type_name) VALUES 
    ('Flight'),
    ('Train'),
    ('Bus'),
    ('Cab'),
    ('Hotel');

CREATE TABLE reservations (
    id INT PRIMARY KEY AUTO_INCREMENT,
    reservation_done_by_employee_id INT,
    travel_request_id INT,
    reservation_type_id INT,
    created_on DATE,
    reservation_done_with_entity VARCHAR(50),
    reservation_date DATE,
    amount INT,
    confirmation_id VARCHAR(10),
    remarks VARCHAR(100) NOT NULL,
    CONSTRAINT amount_positive CHECK (amount > 0),
    FOREIGN KEY (reservation_type_id) REFERENCES reservation_types(type_id)
);

CREATE TABLE reservation_docs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    reservation_id INT,
    document_url VARCHAR(100),
    FOREIGN KEY (reservation_id) REFERENCES reservations(id)
);

desc reservation_types;
desc reservations;
desc reservation_docs;

select * from reservation_types;
select * from reservations;
select * from reservation_docs;
