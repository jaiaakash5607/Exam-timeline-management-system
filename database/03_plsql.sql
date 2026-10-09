
USE exam_timeline_db;

CREATE TABLE IF NOT EXISTS ATTENDANCE_LOG (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    attendance_id INT,
    old_status VARCHAR(20),
    new_status VARCHAR(20),
    changed_on TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3.7.1 PROCEDURE: GET EXAM SUMMARY

DROP PROCEDURE IF EXISTS get_exam_summary;

DELIMITER $$

CREATE PROCEDURE get_exam_summary(
    IN p_exam_id INT,
    OUT p_slots INT,
    OUT p_invigilators INT
)
BEGIN
    SELECT COUNT(*) INTO p_slots
    FROM EXAM_SLOT
    WHERE exam_id = p_exam_id;

    SELECT COUNT(*) INTO p_invigilators
    FROM INVIGILATION i
    JOIN EXAM_SLOT es ON i.slot_id = es.slot_id
    WHERE es.exam_id = p_exam_id;
END$$

DELIMITER ;

-- 3.7.2 FUNCTION: SLOT DURATION IN MINUTES

DROP FUNCTION IF EXISTS slot_duration_mins;

DELIMITER $$

CREATE FUNCTION slot_duration_mins(p_slot_id INT)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_mins INT;

    SELECT TIME_TO_SEC(TIMEDIFF(end_time, start_time)) / 60
    INTO v_mins
    FROM EXAM_SLOT
    WHERE slot_id = p_slot_id;

    RETURN v_mins;
END$$

DELIMITER ;

-- 3.7.3 FUNCTION: ATTENDANCE PERCENTAGE

DROP FUNCTION IF EXISTS attendance_percentage;

DELIMITER $$

CREATE FUNCTION attendance_percentage(p_slot_id INT)
RETURNS DECIMAL(5,2)
READS SQL DATA
BEGIN
    DECLARE v_total INT;
    DECLARE v_present INT;

    SELECT COUNT(*) INTO v_total
    FROM EXAM_ATTENDANCE
    WHERE slot_id = p_slot_id;

    SELECT COUNT(*) INTO v_present
    FROM EXAM_ATTENDANCE
    WHERE slot_id = p_slot_id
      AND status = 'Present';

    IF v_total = 0 THEN
        RETURN 0;
    END IF;

    RETURN v_present * 100 / v_total;
END$$

DELIMITER ;

-- 3.7.4 PROCEDURE: ASSIGN INVIGILATOR

DROP PROCEDURE IF EXISTS assign_invigilator;

DELIMITER $$

CREATE PROCEDURE assign_invigilator(
    IN p_inv_id INT,
    IN p_role VARCHAR(30),
    IN p_slot_id INT,
    IN p_teacher_id INT
)
BEGIN
    DECLARE v_msg VARCHAR(255);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SELECT CONCAT('Failed: ', v_msg) AS Message;
    END;

    START TRANSACTION;

    INSERT INTO INVIGILATION (
        invigilation_id,
        role,
        assigned_on,
        remarks,
        slot_id,
        teacher_id
    )
    VALUES (
        p_inv_id,
        p_role,
        CURDATE(),
        'Assigned via procedure',
        p_slot_id,
        p_teacher_id
    );

    COMMIT;

    SELECT 'Invigilator assigned successfully' AS Message;
END$$

DELIMITER ;

-- CURSOR PROCEDURE: MARK ABSENTEES

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
          AND s.student_id NOT IN (
              SELECT student_id
              FROM EXAM_ATTENDANCE
              WHERE slot_id = p_slot_id
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

        INSERT INTO EXAM_ATTENDANCE (
            attendance_id,
            status,
            check_in_time,
            check_out_time,
            remarks,
            student_id,
            slot_id
        )
        VALUES (
            v_next_id,
            'Absent',
            NULL,
            NULL,
            'Auto-marked absent',
            v_student,
            p_slot_id
        );

        SET v_count = v_count + 1;
    END LOOP;

    CLOSE absent_cur;

    SELECT v_count AS students_marked_absent;
END$$

DELIMITER ;

-- TRIGGER 1: VALIDATE EXAM SLOT AND PREVENT CONFLICTS

DROP TRIGGER IF EXISTS before_insert_slot;

DELIMITER $$

CREATE TRIGGER before_insert_slot
BEFORE INSERT ON EXAM_SLOT
FOR EACH ROW
BEGIN
    DECLARE v_room_clash INT;
    DECLARE v_class_clash INT;

    IF NEW.end_time <= NEW.start_time THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Slot end time must be after start time';
    END IF;

    SELECT COUNT(*) INTO v_room_clash
    FROM EXAM_SLOT
    WHERE room_no = NEW.room_no
      AND exam_date = NEW.exam_date
      AND start_time < NEW.end_time
      AND end_time > NEW.start_time;

    IF v_room_clash > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Room already booked for an overlapping slot';
    END IF;

    SELECT COUNT(*) INTO v_class_clash
    FROM EXAM_SLOT
    WHERE class_id = NEW.class_id
      AND exam_date = NEW.exam_date
      AND start_time < NEW.end_time
      AND end_time > NEW.start_time;

    IF v_class_clash > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Class already has an exam in this time window';
    END IF;
END$$

DELIMITER ;

-- TRIGGER 2: PREVENT INVIGILATOR TIME CONFLICTS

DROP TRIGGER IF EXISTS before_insert_invigilation;

DELIMITER $$

CREATE TRIGGER before_insert_invigilation
BEFORE INSERT ON INVIGILATION
FOR EACH ROW
BEGIN
    DECLARE v_clash INT;

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
            SET MESSAGE_TEXT =
                'Teacher already invigilating an overlapping slot';
    END IF;
END$$

DELIMITER ;

-- TRIGGER 3: VALIDATE STUDENT-CLASS ELIGIBILITY

DROP TRIGGER IF EXISTS before_insert_attendance;

DELIMITER $$

CREATE TRIGGER before_insert_attendance
BEFORE INSERT ON EXAM_ATTENDANCE
FOR EACH ROW
BEGIN
    DECLARE v_ok INT;

    SELECT COUNT(*) INTO v_ok
    FROM STUDENT s
    JOIN EXAM_SLOT es ON s.class_id = es.class_id
    WHERE s.student_id = NEW.student_id
      AND es.slot_id = NEW.slot_id;

    IF v_ok = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT =
                'Student does not belong to the class of this slot';
    END IF;
END$$

DELIMITER ;

-- TRIGGER 4: LOG ATTENDANCE STATUS CHANGES

DROP TRIGGER IF EXISTS after_update_attendance;

DELIMITER $$

CREATE TRIGGER after_update_attendance
AFTER UPDATE ON EXAM_ATTENDANCE
FOR EACH ROW
BEGIN
    IF OLD.status <> NEW.status THEN
        INSERT INTO ATTENDANCE_LOG (
            attendance_id,
            old_status,
            new_status
        )
        VALUES (
            OLD.attendance_id,
            OLD.status,
            NEW.status
        );
    END IF;
END$$

DELIMITER ;

-- TEST 1: GET EXAM SUMMARY

CALL get_exam_summary(501, @slots, @invs);

SELECT
    @slots AS total_slots,
    @invs AS total_invigilators;

-- TEST 2: SLOT DURATION

SELECT slot_duration_mins(701) AS duration_mins;

-- TEST 3: ATTENDANCE PERCENTAGE

SELECT attendance_percentage(701) AS attendance_pct;

-- TEST 4: INSERT A STUDENT

INSERT INTO STUDENT VALUES (
    404,
    'Meena R',
    'RA2211003010004',
    'B.Tech CSE',
    '9000000004',
    'meena@srmist.edu.in',
    201
);

-- TEST 5: MARK ABSENTEES

CALL mark_absentees(701);

SELECT *
FROM EXAM_ATTENDANCE
WHERE slot_id = 701;

-- TEST 6: UPDATE ATTENDANCE AND CHECK THE LOG

UPDATE EXAM_ATTENDANCE
SET status = 'Present'
WHERE attendance_id = 902;

SELECT *
FROM ATTENDANCE_LOG;

-- TEST 7: INSERT AN EXAM SLOT

INSERT INTO EXAM_SLOT
VALUES (
    703,
    '2026-11-20',
    '11:00:00',
    '12:00:00',
    'Room 305',
    40,
    501,
    202
);

-- TEST 8: ASSIGN AN INVIGILATOR

CALL assign_invigilator(
    802,
    'Co-Invigilator',
    703,
    301
);


CALL assign_invigilator(
    803,
    'Co-Invigilator',
    703,
    302
);
