use travel_planner;

CREATE TABLE locations (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(20)
);

INSERT INTO locations (name) VALUES 
    ('Delhi'),
    ('Mumbai'),
    ('Bangalore'),
    ('Chennai'),
    ('Hyderabad');
    
CREATE TABLE travel_requests (
    request_id INT PRIMARY KEY AUTO_INCREMENT,
    raised_by_employee_id INT,
    to_be_approved_by_hr_id INT,
    request_raised_on DATE DEFAULT (CURRENT_DATE),
    from_date DATE,
    to_date DATE,
    purpose_of_travel VARCHAR(100),
    location_id INT,
    request_status VARCHAR(15) CHECK (request_status IN ('New', 'Approved', 'Rejected')),
    request_approved_on DATE,
    priority VARCHAR(6),
    CONSTRAINT checkDateRange CHECK (to_date > from_date),
    FOREIGN KEY (location_id) REFERENCES locations(id)
);
CREATE TABLE travel_budget_allocations (
    id INT PRIMARY KEY AUTO_INCREMENT,
    travel_request_id INT,
    approved_budget INT,
    approved_mode_of_travel VARCHAR(10) CHECK (approved_mode_of_travel IN ('Air', 'Train', 'Bus')),
    approved_hotel_star_rating VARCHAR(6) CHECK (approved_hotel_star_rating IN ('3-Star', '5-Star', '7-Star')),
    FOREIGN KEY (travel_request_id) REFERENCES travel_requests(request_id)
);
    
desc locations;
desc travel_requests;
desc travel_budget_allocations;

Select * from locations;
Select * from travel_requests;
Select * from travel_budget_allocations;
