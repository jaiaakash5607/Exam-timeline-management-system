CREATE DATABASE IF NOT EXISTS exam_timeline_db;
USE exam_timeline_db;
CREATE TABLE DEPARTMENT (
    dept_id INT,
    dept_name VARCHAR(50),
    location VARCHAR(50),
    PRIMARY KEY (dept_id)
);
CREATE TABLE SUBJECT (
    subject_id INT,
    subject_name VARCHAR(50),
    subject_code VARCHAR(20),
    credits INT,
    department_id INT,
    PRIMARY KEY (subject_id),
    FOREIGN KEY (department_id) REFERENCES DEPARTMENT(dept_id)
);
CREATE TABLE class (
    class_id INT,
    class_name VARCHAR(50),
    semester VARCHAR(50),
    dept_id INT,
    section VARCHAR(50),
    PRIMARY KEY (class_id),
    FOREIGN KEY (dept_id) REFERENCES DEPARTMENT(dept_id)
);

-- 4. TEACHER
CREATE TABLE TEACHER (
    teacher_id INT,
    teacher_name VARCHAR(50),
    email VARCHAR(50),
    phone VARCHAR(15),
    qualification VARCHAR(50),
    dept_id INT,
    PRIMARY KEY (teacher_id),
    FOREIGN KEY (dept_id) REFERENCES DEPARTMENT(dept_id)
);
CREATE TABLE STUDENT (
    student_id INT,
    student_name VARCHAR(50),
    roll_no VARCHAR(20),
    program VARCHAR(50),
    phone VARCHAR(15),
    email VARCHAR(50) CHECK (email LIKE '%@srmist.edu.in'),
    class_id INT,
    PRIMARY KEY (student_id),
    FOREIGN KEY (class_id) REFERENCES class(class_id)
);
CREATE TABLE EXAM (
    exam_id INT,
    exam_name VARCHAR(50),
    exam_type VARCHAR(30),
    start_date DATE,
    end_date DATE,
    description VARCHAR(100),
    subject_id INT,
    PRIMARY KEY (exam_id),
    FOREIGN KEY (subject_id) REFERENCES SUBJECT(subject_id)
);
CREATE TABLE EXAM_TIMELINE (
    timeline_id INT,
    event_name VARCHAR(50),
    event_type VARCHAR(30),
    event_date DATE,
    start_time TIME,
    end_time TIME,
    status VARCHAR(20),
    remarks VARCHAR(100),
    exam_id INT,
    PRIMARY KEY (timeline_id),
    FOREIGN KEY (exam_id) REFERENCES EXAM(exam_id)
);
CREATE TABLE EXAM_SLOT (
    slot_id INT,
    exam_date DATE,
    start_time TIME,
    end_time TIME,
    room_no VARCHAR(20),
    capacity INT,
    exam_id INT,
    class_id INT,
    PRIMARY KEY (slot_id),
    FOREIGN KEY (exam_id) REFERENCES EXAM(exam_id),
    FOREIGN KEY (class_id) REFERENCES class(class_id)
);
CREATE TABLE INVIGILATION (
    invigilation_id INT,
    role VARCHAR(30),
    assigned_on DATE,
    remarks VARCHAR(100),
    slot_id INT,
    teacher_id INT,
    PRIMARY KEY (invigilation_id),
    FOREIGN KEY (slot_id) REFERENCES EXAM_SLOT(slot_id),
    FOREIGN KEY (teacher_id) REFERENCES TEACHER(teacher_id)
);
CREATE TABLE EXAM_ATTENDANCE (
    attendance_id INT,
    status VARCHAR(20),
    check_in_time TIME,
    check_out_time TIME,
    remarks VARCHAR(100),
    student_id INT,
    slot_id INT,
    PRIMARY KEY (attendance_id),
    FOREIGN KEY (student_id) REFERENCES STUDENT(student_id),
    FOREIGN KEY (slot_id) REFERENCES EXAM_SLOT(slot_id)
);
