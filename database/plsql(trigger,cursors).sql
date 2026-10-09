
USE exam_timeline_db;

-- 3.8.1 Prevent invalid exam-slot times
DROP TRIGGER IF EXISTS before_insert_slot;

DELIMITER $$

CREATE TRIGGER before_insert_slot
BEFORE INSERT ON EXAM_SLOT
FOR EACH ROW
BEGIN
    IF NEW.end_time <= NEW.start_time THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Slot end time must be after start time';
    END IF;
END$$

DELIMITER ;


-- 3.8.2 Prevent overlapping room bookings
DROP TRIGGER IF EXISTS before_insert_slot_room_clash;

DELIMITER $$

CREATE TRIGGER before_insert_slot_room_clash
BEFORE INSERT ON EXAM_SLOT
FOR EACH ROW
BEGIN
    DECLARE v_room_clash INT DEFAULT 0;

    SELECT COUNT(*) INTO v_room_clash
    FROM EXAM_SLOT
    WHERE room_no = NEW.room_no
      AND exam_date = NEW.exam_date
      AND start_time < NEW.end_time
      AND end_time > NEW.start_time;

    IF v_room_clash > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Room already booked for an overlapping slot';
    END IF;
END$$

DELIMITER ;


-- 3.8.3 Prevent teacher invigilation clashes
DROP TRIGGER IF EXISTS before_insert_invigilation;

DELIMITER $$

CREATE TRIGGER before_insert_invigilation
BEFORE INSERT ON INVIGILATION
FOR EACH ROW
BEGIN
    DECLARE v_clash INT DEFAULT 0;

    SELECT COUNT(*) INTO v_clash
    FROM INVIGILATION i
    JOIN EXAM_SLOT old_s ON i.slot_id = old_s.slot_id
    JOIN EXAM_SLOT new_s ON new_s.slot_id = NEW.slot_id
    WHERE i.teacher_id = NEW.teacher_id
      AND old_s.exam_date = new_s.exam_date
      AND old_s.start_time < new_s.end_time
      AND old_s.end_time > new_s.start_time;

    IF v_clash > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Teacher already invigilating an overlapping slot';
    END IF;
END$$

DELIMITER ;


-- 3.8.4 Validate student-class eligibility for attendance
DROP TRIGGER IF EXISTS before_insert_attendance;

DELIMITER $$

CREATE TRIGGER before_insert_attendance
BEFORE INSERT ON EXAM_ATTENDANCE
FOR EACH ROW
BEGIN
    DECLARE v_ok INT DEFAULT 0;

    SELECT COUNT(*) INTO v_ok
    FROM STUDENT s
    JOIN EXAM_SLOT es ON s.class_id = es.class_id
    WHERE s.student_id = NEW.student_id
      AND es.slot_id = NEW.slot_id;

    IF v_ok = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Student does not belong to the class of this slot';
    END IF;
END$$

DELIMITER ;


-- 3.8.5 Log attendance status changes
CREATE TABLE IF NOT EXISTS ATTENDANCE_LOG (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    attendance_id INT,
    old_status VARCHAR(20),
    new_status VARCHAR(20),
    changed_on TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DROP TRIGGER IF EXISTS after_update_attendance;

DELIMITER $$

CREATE TRIGGER after_update_attendance
AFTER UPDATE ON EXAM_ATTENDANCE
FOR EACH ROW
BEGIN
    IF NOT (OLD.status <=> NEW.status) THEN
        INSERT INTO ATTENDANCE_LOG
            (attendance_id, old_status, new_status)
        VALUES
            (OLD.attendance_id, OLD.status, NEW.status);
    END IF;
END$$

DELIMITER ;


-- Test attendance status logging
UPDATE EXAM_ATTENDANCE
SET status = 'Present'
WHERE attendance_id = 902;

SELECT * FROM ATTENDANCE_LOG;


-- 3.9.1 Cursor to mark students absent
DROP PROCEDURE IF EXISTS mark_absentees;

DELIMITER $$

CREATE PROCEDURE mark_absentees(IN p_slot_id INT)
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE v_student INT;
    DECLARE v_next_id INT;
    DECLARE v_count INT DEFAULT 0;

    DECLARE absent_cur CURSOR FOR
        SELECT s.student_id
        FROM STUDENT s
        JOIN EXAM_SLOT es ON s.class_id = es.class_id
        WHERE es.slot_id = p_slot_id
          AND NOT EXISTS (
              SELECT 1
              FROM EXAM_ATTENDANCE ea
              WHERE ea.student_id = s.student_id
                AND ea.slot_id = p_slot_id
          );

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    OPEN absent_cur;

    read_loop: LOOP
        FETCH absent_cur INTO v_student;

        IF done = 1 THEN
            LEAVE read_loop;
        END IF;

        SELECT COALESCE(MAX(attendance_id), 0) + 1
        INTO v_next_id
        FROM EXAM_ATTENDANCE;

        INSERT INTO EXAM_ATTENDANCE
            (attendance_id, status, check_in_time, check_out_time,
             remarks, student_id, slot_id)
        VALUES
            (v_next_id, 'Absent', NULL, NULL,
             'Auto-marked absent', v_student, p_slot_id);

        SET v_count = v_count + 1;
    END LOOP;

    CLOSE absent_cur;

    SELECT v_count AS students_marked_absent;
END$$

DELIMITER ;

-- Test
CALL mark_absentees(701);


-- 3.9.2 Cursor to count invigilators for an exam
DROP PROCEDURE IF EXISTS cursor_count_exam_invigilators;

DELIMITER $$

CREATE PROCEDURE cursor_count_exam_invigilators(IN p_exam_id INT)
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE v_teacher_id INT;
    DECLARE v_count INT DEFAULT 0;

    DECLARE inv_cur CURSOR FOR
        SELECT i.teacher_id
        FROM INVIGILATION i
        JOIN EXAM_SLOT es ON i.slot_id = es.slot_id
        WHERE es.exam_id = p_exam_id;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    OPEN inv_cur;

    read_loop: LOOP
        FETCH inv_cur INTO v_teacher_id;

        IF done = 1 THEN
            LEAVE read_loop;
        END IF;

        SET v_count = v_count + 1;
    END LOOP;

    CLOSE inv_cur;

    SELECT v_count AS invigilation_assignments;
END$$

DELIMITER ;

-- Test
CALL cursor_count_exam_invigilators(501);


-- 3.9.3 Cursor to report absent students
DROP PROCEDURE IF EXISTS cursor_absent_student_report;

DELIMITER $$

CREATE PROCEDURE cursor_absent_student_report(IN p_slot_id INT)
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE v_student_id INT;
    DECLARE v_name VARCHAR(100);
    DECLARE v_roll VARCHAR(30);

    DECLARE absent_cur CURSOR FOR
        SELECT s.student_id, s.student_name, s.roll_no
        FROM STUDENT s
        JOIN EXAM_ATTENDANCE ea ON ea.student_id = s.student_id
        WHERE ea.slot_id = p_slot_id
          AND ea.status = 'Absent';

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_absent_report;

    CREATE TEMPORARY TABLE tmp_absent_report (
        student_id INT,
        student_name VARCHAR(100),
        roll_no VARCHAR(30)
    );

    OPEN absent_cur;

    read_loop: LOOP
        FETCH absent_cur INTO v_student_id, v_name, v_roll;

        IF done = 1 THEN
            LEAVE read_loop;
        END IF;

        INSERT INTO tmp_absent_report
        VALUES (v_student_id, v_name, v_roll);
    END LOOP;

    CLOSE absent_cur;

    SELECT *
    FROM tmp_absent_report
    ORDER BY student_name;
END$$

DELIMITER ;

-- Test
CALL cursor_absent_student_report(701);

-- 3.8.1

INSERT INTO EXAM_SLOT
VALUES (
    704, '2026-11-20',
    '14:00:00', '12:00:00',
    'Room 306', 40, 501, 202
);

-- 3.8.2

SELECT *
FROM EXAM_SLOT
WHERE room_no = 'Room 305'
  AND exam_date = '2026-11-20';
  
INSERT INTO EXAM_SLOT
VALUES (
    705, '2026-11-20',
    '11:30:00', '12:30:00',
    'Room 305', 40, 501, 202
);


-- 3.8.3

INSERT INTO INVIGILATION
VALUES (
    804, 'Invigilator', CURDATE(),
    'Trigger test', 703, 301
);

-- 3.8.4

INSERT INTO EXAM_ATTENDANCE
VALUES (
    999, 'Present', NOW(), NULL,
    'Trigger test', 404, 703
);

-- 3.8.5

SELECT attendance_id, status
FROM EXAM_ATTENDANCE
WHERE attendance_id = 902;

UPDATE EXAM_ATTENDANCE
SET status = 'Present'
WHERE attendance_id = 902;

SELECT *
FROM ATTENDANCE_LOG;

-- 3.7.4

SELECT * FROM EXAM_SLOT WHERE slot_id = 703;
SELECT * FROM INVIGILATION WHERE invigilation_id = 802;
CALL assign_invigilator(
    802,
    'Co-Invigilator',
    703,
    301
);
SELECT *
FROM INVIGILATION
WHERE invigilation_id = 802;
