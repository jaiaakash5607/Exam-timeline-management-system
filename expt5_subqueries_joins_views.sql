USE exam_timeline_db;
INSERT IGNORE INTO DEPARTMENT VALUES (3, 'Mechanical', 'Block C');
INSERT IGNORE INTO SUBJECT    VALUES (103, 'Thermodynamics', '21MEC201', 4, 3);
INSERT IGNORE INTO class      VALUES (203, 'MECH-A', '3', 3, 'A');
INSERT IGNORE INTO TEACHER    VALUES (303, 'Dr. Priya Das', 'priya@srmist.edu.in', '9876543212', 'PhD MECH', 3);
INSERT IGNORE INTO STUDENT    VALUES (405, 'Sanjay M', 'RA2211005010001', 'B.Tech MECH', '9000000005', 'sanjay@srmist.edu.in', 203);
INSERT IGNORE INTO STUDENT    VALUES (406, 'Lakshmi P', 'RA2211005010002', 'B.Tech MECH', '9000000006', 'lakshmi@srmist.edu.in', 203);
INSERT IGNORE INTO EXAM       VALUES (502, 'Thermo Internal', 'Internal', '2026-11-22', '2026-11-22', 'Internal test', 103);
INSERT IGNORE INTO EXAM       VALUES (503, 'Digital Circuits End Sem', 'Semester', '2026-11-25', '2026-11-25', 'No slot scheduled yet', 102);
INSERT IGNORE INTO EXAM_SLOT  VALUES (704, '2026-11-22', '10:00:00', '12:00:00', 'Room 110', 60, 502, 203);
INSERT IGNORE INTO EXAM_ATTENDANCE VALUES (910, 'Present', '09:50:00', '12:00:00', 'On time', 405, 704);

SELECT student_name, roll_no
FROM STUDENT
WHERE class_id = (SELECT class_id FROM STUDENT WHERE student_name = 'Aakash Kumar');

SELECT subject_name, credits
FROM SUBJECT
WHERE credits > (SELECT AVG(credits) FROM SUBJECT);

SELECT slot_id, room_no, capacity
FROM EXAM_SLOT
WHERE capacity = (SELECT MAX(capacity) FROM EXAM_SLOT);

SELECT teacher_id, teacher_name
FROM TEACHER
WHERE teacher_id IN (SELECT teacher_id FROM INVIGILATION);

SELECT teacher_id, teacher_name
FROM TEACHER
WHERE teacher_id NOT IN (SELECT teacher_id FROM INVIGILATION);
SELECT slot_id, room_no, capacity
FROM EXAM_SLOT
WHERE capacity > ANY (SELECT capacity FROM EXAM_SLOT WHERE class_id = 201);

SELECT slot_id, room_no, capacity
FROM EXAM_SLOT
WHERE capacity > ALL (SELECT capacity FROM EXAM_SLOT WHERE class_id = 201);

SELECT s.student_name, s.roll_no
FROM STUDENT s
WHERE EXISTS (SELECT 1
              FROM EXAM_ATTENDANCE ea
              WHERE ea.student_id = s.student_id
                AND ea.status = 'Absent');

SELECT e.exam_id, e.exam_name
FROM EXAM e
WHERE NOT EXISTS (SELECT 1 FROM EXAM_SLOT es WHERE es.exam_id = e.exam_id);

SELECT exam_name
FROM EXAM
WHERE exam_id IN (
    SELECT exam_id
    FROM EXAM_SLOT
    WHERE class_id IN (
        SELECT class_id
        FROM class
        WHERE dept_id = (SELECT dept_id FROM DEPARTMENT
                         WHERE dept_name = 'Computer Science')
    )
);

SELECT T.exam_id, T.avg_capacity
FROM (SELECT exam_id, AVG(capacity) AS avg_capacity
      FROM EXAM_SLOT
      GROUP BY exam_id) T
WHERE T.avg_capacity > 40;

SELECT e.exam_name, es.exam_date, es.start_time, es.end_time,
       es.room_no, c.class_name
FROM EXAM e
INNER JOIN EXAM_SLOT es ON e.exam_id = es.exam_id
INNER JOIN class c      ON es.class_id = c.class_id
ORDER BY es.exam_date, es.start_time;

SELECT s.student_name, s.roll_no, ea.status, ea.slot_id
FROM STUDENT s
LEFT JOIN EXAM_ATTENDANCE ea ON s.student_id = ea.student_id;

SELECT es.slot_id, es.room_no, t.teacher_name, i.role
FROM INVIGILATION i
JOIN TEACHER t ON i.teacher_id = t.teacher_id
RIGHT JOIN EXAM_SLOT es ON i.slot_id = es.slot_id;

SELECT e.exam_name
FROM EXAM e
LEFT JOIN EXAM_SLOT es ON e.exam_id = es.exam_id
WHERE es.slot_id IS NULL;

SELECT e.exam_name, d.dept_name
FROM EXAM e
CROSS JOIN DEPARTMENT d;

SELECT a.student_name AS student_1, b.student_name AS student_2, a.class_id
FROM STUDENT a
JOIN STUDENT b ON a.class_id = b.class_id
              AND a.student_id < b.student_id;

SELECT t.teacher_name, COUNT(i.invigilation_id) AS duties
FROM TEACHER t
LEFT JOIN INVIGILATION i ON t.teacher_id = i.teacher_id
GROUP BY t.teacher_id, t.teacher_name;

CREATE OR REPLACE VIEW v_invigilation_schedule AS
SELECT es.slot_id, e.exam_name, es.exam_date, es.start_time,
       es.end_time, es.room_no, c.class_name, t.teacher_name, i.role
FROM INVIGILATION i
JOIN EXAM_SLOT es ON i.slot_id = es.slot_id
JOIN EXAM e       ON es.exam_id = e.exam_id
JOIN class c      ON es.class_id = c.class_id
JOIN TEACHER t    ON i.teacher_id = t.teacher_id;

SELECT * FROM v_invigilation_schedule ORDER BY exam_date, start_time;

CREATE OR REPLACE VIEW v_absent_students AS
SELECT s.student_id, s.student_name, s.roll_no, ea.slot_id
FROM STUDENT s
JOIN EXAM_ATTENDANCE ea ON s.student_id = ea.student_id
WHERE ea.status = 'Absent';

SELECT * FROM v_absent_students;

CREATE OR REPLACE VIEW v_cse_a_students AS
SELECT student_id, student_name, phone
FROM STUDENT
WHERE class_id = 201;

SELECT * FROM v_cse_a_students;

UPDATE v_cse_a_students SET phone = '9111111111' WHERE student_id = 401;
SELECT student_id, student_name, phone FROM STUDENT WHERE student_id = 401;

CREATE OR REPLACE VIEW v_exam_load AS
SELECT e.exam_name, COUNT(es.slot_id) AS slots, COALESCE(SUM(es.capacity), 0) AS total_seats
FROM EXAM e
LEFT JOIN EXAM_SLOT es ON e.exam_id = es.exam_id
GROUP BY e.exam_id, e.exam_name;

SELECT * FROM v_exam_load;

SHOW FULL TABLES WHERE Table_type = 'VIEW';