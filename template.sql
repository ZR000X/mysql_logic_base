-- --------------------------------------------------------
-- Host:                         127.0.0.1
-- Server version:               8.0.39 - MySQL Community Server - GPL
-- Server OS:                    Win64
-- HeidiSQL Version:             12.8.0.6908
-- --------------------------------------------------------

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET NAMES utf8 */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;


-- Dumping database structure for onedbi_template
CREATE DATABASE IF NOT EXISTS `onedbi_template` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci */ /*!80016 DEFAULT ENCRYPTION='N' */;
USE `onedbi_template`;

-- Dumping structure for procedure onedbi_template.dbi_authorise
DELIMITER //
CREATE PROCEDURE `dbi_authorise`(
	IN in_function_name VARCHAR(255),
    IN in_call_by INT,
    IN in_args TEXT
)
BEGIN

DECLARE in_user_id INT;
DECLARE in_entry_id INT;

IF in_function_name = 'update_entry' THEN

	SET in_entry_id = JSON_EXTRACT(in_args, '$.entryId');

	SELECT user_id 
    INTO in_user_id
    FROM trans_entries 
    WHERE entry_id = in_entry_id;

	IF NOT in_user_id = in_call_by THEN
		CALL dbi_response_set_status(400);
        SET @err_msg = CONCAT('User ',in_call_by,' not authorised to update entry ',in_entry_id,'.');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=@err_msg;
    END IF;

END IF;

END//
DELIMITER ;

-- Dumping structure for procedure onedbi_template.dbi_call
DELIMITER //
CREATE PROCEDURE `dbi_call`(
    IN in_function_name VARCHAR(255),
    IN in_call_by INT,
    IN in_args JSON,
    OUT out_call_id INT
)
BEGIN
    DECLARE in_error_message TEXT;
    DECLARE in_dbf_function_id INT;
    DECLARE in_dbf_function_name TEXT;
    DECLARE in_dbf_function_call TEXT;
    DECLARE out_functionality_sql TEXT;
    DECLARE in_call_at DATETIME(6) DEFAULT NOW(6);
    DECLARE out_response JSON;

	BEGIN
		-- General SQLEXCEPTION handler
		DECLARE EXIT HANDLER FOR SQLEXCEPTION
		BEGIN
			ROLLBACK;
			RESIGNAL;
		END;

		-- Start initial transaction
		START TRANSACTION;
			INSERT INTO dbi_calls (
				call_function_name, 
				call_by, 
				call_args, 
				call_at, 
				call_ms, 
				call_res, 
				call_usr,
                call_req_size
			) VALUES (
				in_function_name, 
				in_call_by,
				in_args,
				in_call_at,
				NULL, 
				'{}', 
				USER(),
                OCTET_LENGTH(JSON_OBJECT(
					'functionName', in_function_name,
                    'userId', in_call_by,                
                    'args', in_args
				))                    
			);
			SELECT LAST_INSERT_ID() INTO out_call_id;
		COMMIT;
    END;

	BEGIN
		-- General SQLEXCEPTION handler for the main work
		DECLARE EXIT HANDLER FOR SQLEXCEPTION
		BEGIN
			GET DIAGNOSTICS CONDITION 1 in_error_message = MESSAGE_TEXT;
			ROLLBACK;
			CALL dbi_response_set_status(500);
			CALL dbi_response_set_err_msg(in_error_message);
            
            SET out_response = fn_dbi_get_response();
            
			UPDATE dbi_calls a, (SELECT out_call_id AS call_id) b
				SET call_ms = fn_ms_since_then(call_at), 
					call_res = out_response,
                    call_res_size = OCTET_LENGTH(out_response)
			WHERE a.call_id = b.call_id;
            
			IF COALESCE(@quiet_mode, 0) = 0 THEN
				SELECT call_res FROM dbi_calls a, (SELECT out_call_id AS call_id) b
				WHERE a.call_id = b.call_id;
			END IF;
			RESIGNAL;
		END;

		-- Specific SQLSTATE '45000' handler
		DECLARE EXIT HANDLER FOR SQLSTATE '45000'
		BEGIN
			GET DIAGNOSTICS CONDITION 1 in_error_message = MESSAGE_TEXT;
			ROLLBACK;
			CALL dbi_response_set_err_msg(in_error_message);
            
            SET out_response = fn_dbi_get_response();
            
			UPDATE dbi_calls a, (SELECT out_call_id AS call_id) b
			SET call_ms = fn_ms_since_then(call_at), 
				call_res = out_response,
                call_res_size = OCTET_LENGTH(out_response)
			WHERE a.call_id = b.call_id;
            
			IF COALESCE(@quiet_mode, 0) = 0 THEN
				SELECT call_res FROM dbi_calls a, (SELECT out_call_id AS call_id) b
				WHERE a.call_id = b.call_id;
			END IF;
		END;

		-- Perform the main work within another transaction
		START TRANSACTION;
			CALL dbi_response_initiate(out_call_id);
            CALL dbi_authorise(in_function_name, in_call_by, in_args);
			IF NOT EXISTS (SELECT * FROM dbi_functionality WHERE function_name = in_function_name) THEN
				CALL dbi_response_set_status(405);
				SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = in_function_name;
			END IF;
			CALL dbi_response_set_status(200);
            SET out_functionality_sql = fn_dbi_get_functionality_sql(in_function_name, in_args);
            CALL dbi_response_append_to_callstack(JSON_OBJECT(
				'sql', out_functionality_sql
			));
			CALL mod_execute_query(out_functionality_sql);
            
			SET out_response = fn_dbi_get_response();
            
			UPDATE dbi_calls a, (SELECT out_call_id AS call_id) b
				SET call_ms = fn_ms_since_then(call_at), 
					call_res = out_response,
                    call_res_size = OCTET_LENGTH(out_response)
			WHERE a.call_id = b.call_id;
            
		COMMIT;

		IF COALESCE(@quiet_mode, 0) = 0 THEN
			SELECT call_res FROM dbi_calls a, (SELECT out_call_id AS call_id) b
			WHERE a.call_id = b.call_id;
		END IF;
	END;
END//
DELIMITER ;

-- Dumping structure for table onedbi_template.dbi_calls
CREATE TABLE IF NOT EXISTS `dbi_calls` (
  `call_id` int NOT NULL AUTO_INCREMENT,
  `call_function_name` varchar(255) NOT NULL,
  `call_by` int NOT NULL,
  `call_args` json NOT NULL,
  `call_at` datetime NOT NULL,
  `call_res` json DEFAULT NULL,
  `call_ms` int DEFAULT NULL,
  `call_usr` varchar(45) NOT NULL,
  `call_req_size` int DEFAULT NULL,
  `call_res_size` int DEFAULT NULL,
  PRIMARY KEY (`call_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Dumping data for table onedbi_template.dbi_calls: ~0 rows (approximately)

-- Dumping structure for procedure onedbi_template.dbi_fn_get_entry
DELIMITER //
CREATE PROCEDURE `dbi_fn_get_entry`(
	in_args JSON
)
BEGIN

DECLARE in_user_id INT;
DECLARE in_entry_id INT;

CALL dbi_response_append_to_callstack(JSON_OBJECT(
	'started', 'dbi_fn_get_entry',
    'at', NOW()
));

IF NOT JSON_CONTAINS_PATH(in_args, 'all', '$.userId', '$.entryId') THEN
    CALL dbi_response_set_status(405);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='dbf_trans_get_entry must contain userId, entryId';
END IF;

SELECT JSON_EXTRACT(in_args, '$.userId') INTO in_user_id;
SELECT JSON_EXTRACT(in_args, '$.entryId') INTO in_entry_id;

CALL dbi_response_set_body_field('entry', (
	SELECT JSON_OBJECT(
		'entryId', a.entry_id,
		'entryDate', a.entry_date,
		'entryDesc', a.entry_desc,
		'amount', a.amount,
		'debitAccountId', a.debit_account_id,
		'debitAccountName', b.account_name,
		'creditAccountId', a.credit_account_id,
        'creditAccountName', c.account_name
	)
    FROM trans_entries a
	JOIN trans_accounts b ON a.debit_account_id = b.account_id
	JOIN trans_accounts c ON a.credit_account_id = c.account_id
	WHERE a.user_id = in_user_id
		AND a.entry_id = in_entry_id
));

IF @test_mode = 1 THEN
	CALL dbi_response_set_testmode_field('entry', (
		SELECT JSON_OBJECT(
			'entryId', a.entry_id,
			'entryDate', a.entry_date,
			'entryDesc', a.entry_desc,
			'amount', a.amount,
			'debitAccountId', a.debit_account_id,
			'debitAccountName', b.account_name,
			'creditAccountId', a.credit_account_id,
			'creditAccountName', c.account_name
		)
		FROM trans_entries a
		JOIN trans_accounts b ON a.debit_account_id = b.account_id
		JOIN trans_accounts c ON a.credit_account_id = c.account_id
		WHERE a.user_id = in_user_id
			AND a.entry_id = in_entry_id
	));
END IF;

CALL dbi_response_set_status(201);

CALL dbi_response_append_to_callstack(JSON_OBJECT(
	'ended', 'dbi_fn_get_entry',
    'at', NOW()
));

END//
DELIMITER ;

-- Dumping structure for procedure onedbi_template.dbi_fn_update_entry
DELIMITER //
CREATE PROCEDURE `dbi_fn_update_entry`(
	IN in_args JSON
)
BEGIN

DECLARE in_entry_id INT;

IF NOT JSON_CONTAINS_PATH(in_args, 'all', '$.entryId', '$.entry') THEN
    CALL dbi_response_set_status(400);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='dbf_trans_get_entry must contain entryId, entry';
END IF;

SET in_entry_id = JSON_EXTRACT(in_args, '$.entryId');

DROP TEMPORARY TABLE IF EXISTS tmp_trans_update_entry;
CREATE TEMPORARY TABLE tmp_trans_update_entry
(
SELECT amount,
	entry_date,
    entry_desc,
    debit_account_id,
    credit_account_id,
    entry_id
FROM JSON_TABLE(
in_args,
'$.entry'
COLUMNS (
	amount DECIMAL(10,2) PATH '$.amount' ERROR ON EMPTY ERROR ON ERROR,
	entry_id INT PATH '$.entryId' ERROR ON EMPTY ERROR ON ERROR,
	entry_date DATE PATH '$.entryDate' ERROR ON EMPTY ERROR ON ERROR,
	entry_desc VARCHAR(255) PATH '$.entryDesc' ERROR ON EMPTY ERROR ON ERROR,
	debit_account_id DECIMAL(20,6) PATH '$.debitAccountId' ERROR ON ERROR,
	credit_account_id DECIMAL(20,6) PATH '$.creditAccountId' ERROR ON ERROR
)) x
);

UPDATE trans_entries a, tmp_trans_update_entry b
	SET a.amount = b.amount,
		a.entry_date = b.entry_date,
        a.entry_desc = b.entry_desc,
        a.debit_account_id = b.debit_account_id,
        a.credit_account_id = b.credit_account_id
WHERE a.entry_id = b.entry_id;

CALL dbi_response_set_status(202);

CALL dbi_response_set_body_field('result', JSON_OBJECT('message', CONCAT('Entry ',in_entry_id,' successfully updated.')));

IF @test_mode = 1 THEN
	CALL dbi_response_set_testmode_field('result', JSON_OBJECT('message', CONCAT('Entry ',in_entry_id,' successfully updated.')));
END IF;

END//
DELIMITER ;

-- Dumping structure for table onedbi_template.dbi_functionality
CREATE TABLE IF NOT EXISTS `dbi_functionality` (
  `function_id` int NOT NULL AUTO_INCREMENT,
  `function_name` varchar(255) NOT NULL,
  `eg_params` json NOT NULL,
  `function_description` text NOT NULL,
  `function_code` varchar(45) NOT NULL,
  `is_testable` tinyint NOT NULL,
  PRIMARY KEY (`function_id`),
  UNIQUE KEY `unq_name` (`function_name`),
  UNIQUE KEY `unq_code` (`function_code`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Dumping data for table onedbi_template.dbi_functionality: ~2 rows (approximately)
INSERT INTO `dbi_functionality` (`function_id`, `function_name`, `eg_params`, `function_description`, `function_code`, `is_testable`) VALUES
	(1, 'get_entry', '{"user_id": 1, "entry_id": 1}', 'Gets a specific entry', 'TRANS-ENT-R', 1),
	(2, 'update_entry', '{}', 'Updates a specific entry', 'TRANS-ENT-U', 1);

-- Dumping structure for procedure onedbi_template.dbi_response_append_to_callstack
DELIMITER //
CREATE PROCEDURE `dbi_response_append_to_callstack`(
    IN in_appendage JSON
)
BEGIN
    -- Correctly set @response_json by appending in_appendage to the callstack array
    SET @response_json = JSON_SET(
        @response_json, 
        '$.callstack', 
        JSON_ARRAY_APPEND(
            COALESCE(
                JSON_EXTRACT(@response_json, '$.callstack'), 
                JSON_ARRAY()
            ), 
            '$', 
            in_appendage
        )
    );
END//
DELIMITER ;

-- Dumping structure for procedure onedbi_template.dbi_response_initiate
DELIMITER //
CREATE PROCEDURE `dbi_response_initiate`(
	IN in_call_id INT
)
BEGIN
SET @response_json = JSON_OBJECT(
	'callId', in_call_id,
	'callstack', JSON_OBJECT('call', 'dbi_call'),
	'status', NULL,
	'body', JSON_OBJECT(),
    'testmode', JSON_OBJECT()
);	
END//
DELIMITER ;

-- Dumping structure for procedure onedbi_template.dbi_response_set_body_field
DELIMITER //
CREATE PROCEDURE `dbi_response_set_body_field`(
	IN in_key VARCHAR(255),
    IN in_data JSON
)
BEGIN

IF NOT JSON_VALID(in_data) THEN
	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='dbi_response_set_body_field';
ELSE
	SET @response_json = JSON_SET(@response_json, CONCAT('$.body.', in_key), in_data); 
END IF;

END//
DELIMITER ;

-- Dumping structure for procedure onedbi_template.dbi_response_set_err_msg
DELIMITER //
CREATE PROCEDURE `dbi_response_set_err_msg`(
	IN in_err_msg TEXT
)
BEGIN

DECLARE in_status_id INT;
DECLARE in_status_name VARCHAR(255);

SELECT fn_dbi_response_get_status()
INTO in_status_id;

SELECT status_name
INTO in_status_name
FROM dbi_statuses
WHERE status_id = in_status_id;

CALL dbi_response_set_body_field(
	'error', JSON_OBJECT('message', CONCAT(COALESCE(in_status_name,'BAD STATUS'),': ',in_err_msg))
);

IF @test_mode = 1 THEN
	CALL dbi_response_set_testmode_field(
		'error',JSON_OBJECT('message', CONCAT(COALESCE(in_status_name,'BAD STATUS'),': ',in_err_msg))
	);
END IF;

END//
DELIMITER ;

-- Dumping structure for procedure onedbi_template.dbi_response_set_status
DELIMITER //
CREATE PROCEDURE `dbi_response_set_status`(
	IN in_status_id INT
)
BEGIN
SET @response_json = JSON_SET(@response_json, '$.status', in_status_id);
END//
DELIMITER ;

-- Dumping structure for procedure onedbi_template.dbi_response_set_testmode_field
DELIMITER //
CREATE PROCEDURE `dbi_response_set_testmode_field`(
	IN in_key VARCHAR(255),
    IN in_value JSON
)
BEGIN

IF @test_mode = 1 THEN
	SET @response_json = JSON_SET(@response_json, CONCAT('$.testmode.', in_key), in_value);
END IF;

END//
DELIMITER ;

-- Dumping structure for table onedbi_template.dbi_statuses
CREATE TABLE IF NOT EXISTS `dbi_statuses` (
  `status_id` int NOT NULL,
  `status_name` varchar(255) NOT NULL,
  PRIMARY KEY (`status_id`),
  UNIQUE KEY `unq_name` (`status_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Dumping data for table onedbi_template.dbi_statuses: ~63 rows (approximately)
INSERT INTO `dbi_statuses` (`status_id`, `status_name`) VALUES
	(202, 'Accepted'),
	(208, 'Already Reported (WebDAV)'),
	(502, 'Bad Gateway'),
	(400, 'Bad Request'),
	(409, 'Conflict'),
	(100, 'Continue'),
	(201, 'Created'),
	(103, 'Early Hints'),
	(417, 'Exception Failed'),
	(424, 'Failed Dependency (WebDAV)'),
	(403, 'Forbidden'),
	(302, 'Found'),
	(504, 'Gateway Timeout'),
	(410, 'Gone'),
	(505, 'HTTP Version Not Supported'),
	(418, 'I\'m a teapot (RFC 2324, April Fools\' Joke)'),
	(226, 'IM Used'),
	(500, 'Internal Server Error'),
	(411, 'Length Required'),
	(423, 'Locked (WebDAV)'),
	(508, 'Loop Detected (WebDAV)'),
	(405, 'Method Not Allowed'),
	(421, 'Misfirected Request'),
	(301, 'Moved Permanently'),
	(207, 'Multi-Status (WebDAV)'),
	(300, 'Multiple Choices'),
	(511, 'Network Authentication Required'),
	(204, 'No Content'),
	(203, 'Non-Authoritative Information'),
	(406, 'Not Acceptable'),
	(510, 'Not Extended'),
	(404, 'Not Found'),
	(501, 'Not Implemented'),
	(304, 'Not Modified'),
	(200, 'OK'),
	(206, 'Partial Content'),
	(413, 'Payload Too Large'),
	(402, 'Payment Required (Reserved)'),
	(308, 'Permanent Redirect'),
	(412, 'Precondition Failed'),
	(428, 'Precondition Required'),
	(102, 'Processing (WebDAV)'),
	(407, 'Proxy Authentication Required'),
	(416, 'Range Not Satisfiable'),
	(431, 'Request Header Fields Too Large'),
	(408, 'Request Timeout'),
	(205, 'Reset Content'),
	(303, 'See Other'),
	(503, 'Service Unavailable'),
	(306, 'Switch Proxy (Unused)'),
	(101, 'Switching Protocols'),
	(307, 'Temporary Redirect'),
	(425, 'Too Early'),
	(429, 'Too Many Requests'),
	(401, 'Unauthorized'),
	(451, 'Unavailable For Legal Reasons'),
	(422, 'Unprocessable Entity (WebDAV)'),
	(507, 'Unsufficient Storage (WebDAV)'),
	(415, 'Unsupported Media Type'),
	(426, 'Upgrade Required'),
	(414, 'URI Too Long'),
	(305, 'Use Proxy (Deprecated)'),
	(506, 'Variant Also Negotiates');

-- Dumping structure for procedure onedbi_template.dbut_mock_dbi_call
DELIMITER //
CREATE PROCEDURE `dbut_mock_dbi_call`(
	IN in_function_name_1 VARCHAR(255),
    IN in_call_by_1 INT,
    IN in_args_1 JSON,
    OUT out_call_id INT
)
BEGIN

DECLARE var_response JSON DEFAULT JSON_OBJECT();

-- Pick up the configured test case
SELECT response
INTO var_response
FROM dbut_unit_test_cases a
WHERE a.in_call_by = in_call_by_1
	AND a.in_function_name = in_function_name_1
	AND a.in_args = in_args_1;

-- Validate that a test case was found for the input params
IF var_response = JSON_OBJECT() THEN
	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Bad Request: No test case available for specified inputs';
END IF;

-- If there was, select it out
SELECT var_response AS call_res;

END//
DELIMITER ;

-- Dumping structure for procedure onedbi_template.dbut_run
DELIMITER //
CREATE PROCEDURE `dbut_run`(
	OUT out_test_id INT
)
BEGIN

SET @test_mode = 1;

-- refresh seed tables
CALL dbut_seed_database();

-- create a new test record
INSERT INTO dbut_tests (test_at)
SELECT NOW();

-- pick up the new test id
SELECT LAST_INSERT_ID() INTO out_test_id;

-- test all functionalities against this test id
CALL dbut_test_functionality(out_test_id);

END//
DELIMITER ;

-- Dumping structure for procedure onedbi_template.dbut_run_tests
DELIMITER //
CREATE PROCEDURE `dbut_run_tests`()
BEGIN

CALL dbut_run(@test_id);

SELECT a.unit_test_id, 
	a.test_id,
	b.unit_test_case_id,
    d.function_id,
    d.function_name,    
	a.test_delta,
	a.test_passed,	
    c.call_id,
    c.call_res AS actual_response,
    b.response AS expected_response
FROM dbut_unit_tests a
JOIN dbut_unit_test_cases b ON a.unit_test_case_id = b.unit_test_case_id
JOIN dbi_calls c ON a.call_id = c.call_id
JOIN dbi_functionality d ON b.in_function_name = d.function_name
WHERE test_id = @test_id;
    
END//
DELIMITER ;

-- Dumping structure for procedure onedbi_template.dbut_seed_database
DELIMITER //
CREATE PROCEDURE `dbut_seed_database`()
BEGIN

--  create destination tables if they do not exist.
DROP TEMPORARY TABLE IF EXISTS tmp_in_execute_mult_queries;
CREATE TEMPORARY TABLE tmp_in_execute_mult_queries
(
SELECT CONCAT(
	'CREATE TABLE IF NOT EXISTS ',to_table,' LIKE ', from_table, ';'
) AS qry
FROM dbut_seed_tables
ORDER BY insert_order ASC
);
CALL mod_execute_queries();

--  truncate destination tables
DROP TEMPORARY TABLE IF EXISTS tmp_in_execute_mult_queries;
CREATE TEMPORARY TABLE tmp_in_execute_mult_queries
(
SELECT CONCAT(
	'DELETE FROM ',to_table,';'
) AS qry
FROM dbut_seed_tables 
ORDER BY insert_order DESC
);
CALL mod_execute_queries();

--  populate destination tables with seed data
DROP TEMPORARY TABLE IF EXISTS tmp_in_execute_mult_queries;
CREATE TEMPORARY TABLE tmp_in_execute_mult_queries
(
SELECT CONCAT(
	'INSERT INTO ',to_table,
    ' SELECT * FROM ', from_table,';'
) AS qry
FROM dbut_seed_tables a
ORDER BY insert_order ASC
);
CALL mod_execute_queries();

END//
DELIMITER ;

-- Dumping structure for table onedbi_template.dbut_seed_tables
CREATE TABLE IF NOT EXISTS `dbut_seed_tables` (
  `from_table` varchar(255) NOT NULL,
  `to_table` varchar(255) NOT NULL,
  `insert_order` int NOT NULL,
  PRIMARY KEY (`from_table`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Dumping data for table onedbi_template.dbut_seed_tables: ~2 rows (approximately)
INSERT INTO `dbut_seed_tables` (`from_table`, `to_table`, `insert_order`) VALUES
	('_seed_trans_accounts', 'trans_accounts', 1),
	('_seed_trans_entries', 'trans_entries', 2);

-- Dumping structure for table onedbi_template.dbut_tests
CREATE TABLE IF NOT EXISTS `dbut_tests` (
  `test_id` int NOT NULL AUTO_INCREMENT,
  `test_at` datetime NOT NULL,
  PRIMARY KEY (`test_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Dumping data for table onedbi_template.dbut_tests: ~0 rows (approximately)

-- Dumping structure for procedure onedbi_template.dbut_test_functionality
DELIMITER //
CREATE PROCEDURE `dbut_test_functionality`(
	IN in_test_id INT
)
BEGIN

DECLARE var_function_id INT;
DECLARE var_unit_test_case_id INT;
DECLARE var_call_by INT;
DECLARE var_function_name VARCHAR(255);
DECLARE var_args JSON;
DECLARE var_expected_response JSON;
DECLARE var_actual_response JSON;
DECLARE var_call_id INT;
DECLARE var_comparison_result TINYINT;
DECLARE var_comparison_delta JSON;
DECLARE done TINYINT DEFAULT 0;

DECLARE test_cases_cursor CURSOR FOR 
SELECT b.function_id,
	a.unit_test_case_id,
	a.in_call_by,
	a.in_function_name,
	a.in_args,
	a.response
FROM dbut_unit_test_cases a
JOIN dbi_functionality b ON a.in_function_name = b.function_name
WHERE b.is_testable = 1;

DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;    

OPEN test_cases_cursor;

-- set session to quiet_mode, so that each DBI call does not shout the response
SET @quiet_mode = 1;

read_loop: LOOP

	FETCH test_cases_cursor INTO var_function_id,
		var_unit_test_case_id, 
		var_call_by, 
        var_function_name, 
        var_args, 
        var_expected_response;

	IF done THEN 
		LEAVE read_loop; 
    END IF;	
        
	/* Call the DBI for this case */
    CALL dbi_call(
		var_function_name, -- <{IN in_function_name VARCHAR(255)}>, 
        var_call_by, -- <{IN in_call_by INT}>, 
        var_args, -- <{IN in_args TEXT}>, 
        var_call_id -- <{OUT out_call_id INT}>
	);
    
    /* Fetch the DBI response */
    SELECT call_res INTO var_actual_response
    FROM dbi_calls
    WHERE call_id = var_call_id;
    
    SELECT fn_compare_json_paths(
		var_expected_response,
        var_actual_response,
        JSON_ARRAY('$.testmode', '$.status')
	) INTO var_comparison_delta;		
    
	SELECT fn_dbut_compare_responses(
		var_function_id,
        var_expected_response,
        var_actual_response
	) INTO var_comparison_result;
    
    /* Record the result*/
	INSERT INTO dbut_unit_tests (
		unit_test_case_id, 
        test_id,
        test_delta, 
        test_passed,
        call_id
	) SELECT 
		var_unit_test_case_id,
		in_test_id,
		var_comparison_delta, 
		var_comparison_result,
        var_call_id;
        
END LOOP;
    
CLOSE test_cases_cursor;

END//
DELIMITER ;

-- Dumping structure for procedure onedbi_template.dbut_truncate_before_template
DELIMITER //
CREATE PROCEDURE `dbut_truncate_before_template`()
BEGIN

/* meta test data */
TRUNCATE dbi_calls;
TRUNCATE dbut_tests;
TRUNCATE dbut_unit_tests;

END//
DELIMITER ;

-- Dumping structure for table onedbi_template.dbut_unit_tests
CREATE TABLE IF NOT EXISTS `dbut_unit_tests` (
  `unit_test_id` int NOT NULL AUTO_INCREMENT,
  `test_id` int NOT NULL,
  `unit_test_case_id` int NOT NULL,
  `test_delta` json NOT NULL,
  `test_passed` tinyint NOT NULL,
  `call_id` int NOT NULL,
  PRIMARY KEY (`unit_test_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Dumping data for table onedbi_template.dbut_unit_tests: ~0 rows (approximately)

-- Dumping structure for table onedbi_template.dbut_unit_test_cases
CREATE TABLE IF NOT EXISTS `dbut_unit_test_cases` (
  `unit_test_case_id` int NOT NULL AUTO_INCREMENT,
  `in_call_by` int NOT NULL,
  `in_function_name` varchar(255) NOT NULL,
  `in_args` json NOT NULL,
  `response` json NOT NULL,
  `case_desc` text NOT NULL,
  PRIMARY KEY (`unit_test_case_id`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Dumping data for table onedbi_template.dbut_unit_test_cases: ~3 rows (approximately)
INSERT INTO `dbut_unit_test_cases` (`unit_test_case_id`, `in_call_by`, `in_function_name`, `in_args`, `response`, `case_desc`) VALUES
	(1, 1, 'get_entry', '{"userId": 1, "entryId": 1}', '{"status": 201, "testmode": {"entry": {"amount": 1000.0, "entryId": 1, "entryDate": "2024-07-18", "entryDesc": "Entry 1", "debitAccountId": 1, "creditAccountId": 2, "debitAccountName": "Account 1", "creditAccountName": "Account 2 "}}}', 'Should be able to get a an entry if the user is correct.'),
	(2, 1, 'update_entry', '{"entry": {"amount": 10000, "entryId": 1, "entryDate": "2024-07-22", "entryDesc": "Test - Update", "debitAccountId": 2, "creditAccountId": 1}, "entryId": 1}', '{"status": 202, "testmode": {"result": {"message": "Entry 1 successfully updated."}}}', 'Should be able to update an entry if the user is correct.'),
	(3, 2, 'update_entry', '{"entry": {"amount": 10000, "entryId": 1, "entryDate": "2024-07-22", "entryDesc": "Test - Update", "debitAccountId": 2, "creditAccountId": 1}, "entryId": 1}', '{"status": 400, "testmode": {"error": {"message": "Bad Request: User 2 not authorised to update entry 1."}}}', 'Should not be able to update an entry if the user is not correct.');

-- Dumping structure for function onedbi_template.fn_clean_string
DELIMITER //
CREATE FUNCTION `fn_clean_string`(
	in_string VARCHAR(255)
) RETURNS text CHARSET utf8mb4
    DETERMINISTIC
BEGIN
DECLARE cleaned_string VARCHAR(255);

-- Remove leading and trailing spaces
SET cleaned_string = TRIM(in_string);

-- Replace multiple spaces with a single space
WHILE INSTR(cleaned_string, '  ') > 0 DO
	SET cleaned_string = REPLACE(cleaned_string, '  ', ' ');
END WHILE;

-- Replace spaces with underscores
SET cleaned_string = REPLACE(cleaned_string, ' ', '_');

-- Convert to lowercase
SET cleaned_string = LOWER(cleaned_string);

RETURN cleaned_string;
END//
DELIMITER ;

-- Dumping structure for function onedbi_template.fn_compare_json_paths
DELIMITER //
CREATE FUNCTION `fn_compare_json_paths`(
    json1 JSON,
    json2 JSON,
    fields_to_match JSON
) RETURNS json
    DETERMINISTIC
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE field_path VARCHAR(255);
    DECLARE num_fields INT;
    DECLARE failed_fields JSON DEFAULT JSON_ARRAY();
    DECLARE value1 JSON;
	DECLARE value2 JSON;
    DECLARE value1_str VARCHAR(255);
            DECLARE value2_str VARCHAR(255);

    -- Get the number of fields in the array
    SET num_fields = JSON_LENGTH(fields_to_match);

    -- Loop through each field path
    WHILE i < num_fields DO
        -- Extract the field path from the JSON array
        SET field_path = JSON_UNQUOTE(JSON_EXTRACT(fields_to_match, CONCAT('$[', i, ']')));

        -- Check if the path exists in both JSONs
        IF JSON_CONTAINS_PATH(json1, 'one', field_path) = 1 AND 
           JSON_CONTAINS_PATH(json2, 'one', field_path) = 1 THEN
           
            -- Extract values from both JSONs
            
            SET value1 = JSON_EXTRACT(json1, field_path);
            SET value2 = JSON_EXTRACT(json2, field_path);
            
            -- Convert values to strings for comparison
            
            SET value1_str = JSON_UNQUOTE(value1);
            SET value2_str = JSON_UNQUOTE(value2);
            
            -- Intelligent comparison
            IF value1_str != value2_str THEN
                -- Attempt numeric comparison if both values are numeric
                /*IF NOT CAST(value1_str AS DECIMAL(30,10)) = CAST(value2_str AS DECIMAL(30,10)) THEN
                    -- Append the failed field path to the JSON array
                    SET failed_fields = JSON_ARRAY_APPEND(failed_fields, '$', field_path);
                END IF;
                */
                -- turned this off as it does weird things to comparing JSONS
                
                SET failed_fields = JSON_ARRAY_APPEND(failed_fields, '$', field_path);
            END IF;
            
            
        ELSE
            -- Append the failed field path to the JSON array if the path does not exist in either JSON
            SET failed_fields = JSON_ARRAY_APPEND(failed_fields, '$', field_path);
        END IF;

        -- Increment the counter
        SET i = i + 1;
    END WHILE;

    -- Return the JSON array of failed fields
    RETURN failed_fields;
END//
DELIMITER ;

-- Dumping structure for function onedbi_template.fn_dbi_get_functionality_proc_name
DELIMITER //
CREATE FUNCTION `fn_dbi_get_functionality_proc_name`(
	in_function_name VARCHAR(255)
) RETURNS text CHARSET utf8mb4
BEGIN
RETURN (
SELECT CONCAT('dbi_fn_',fn_clean_string(a.function_name))
FROM dbi_functionality a
WHERE a.function_name = in_function_name
);
END//
DELIMITER ;

-- Dumping structure for function onedbi_template.fn_dbi_get_functionality_sql
DELIMITER //
CREATE FUNCTION `fn_dbi_get_functionality_sql`(
	in_function_name VARCHAR(255),
    in_params JSON
) RETURNS text CHARSET utf8mb4
    DETERMINISTIC
BEGIN

DECLARE proc_name TEXT DEFAULT fn_dbi_get_functionality_proc_name(in_function_name);

RETURN (
SELECT CONCAT('CALL ',proc_name,"('",in_params,"');")
);
END//
DELIMITER ;

-- Dumping structure for function onedbi_template.fn_dbi_get_response
DELIMITER //
CREATE FUNCTION `fn_dbi_get_response`() RETURNS json
BEGIN
RETURN CAST(@response_json AS JSON);
END//
DELIMITER ;

-- Dumping structure for function onedbi_template.fn_dbi_response_get_err_msg
DELIMITER //
CREATE FUNCTION `fn_dbi_response_get_err_msg`() RETURNS varchar(255) CHARSET utf8mb4
    DETERMINISTIC
BEGIN
RETURN JSON_EXTRACT(@response_json, '$.body.errorMessage');
END//
DELIMITER ;

-- Dumping structure for function onedbi_template.fn_dbi_response_get_status
DELIMITER //
CREATE FUNCTION `fn_dbi_response_get_status`() RETURNS int
    DETERMINISTIC
BEGIN
RETURN JSON_EXTRACT(@response_json, '$.status');
END//
DELIMITER ;

-- Dumping structure for function onedbi_template.fn_dbut_compare_responses
DELIMITER //
CREATE FUNCTION `fn_dbut_compare_responses`(
	in_function_id INT,
    in_expected_response JSON,
    in_actual_response JSON
) RETURNS tinyint
    DETERMINISTIC
BEGIN

RETURN JSON_CONTAINS(in_actual_response, in_expected_response);
END//
DELIMITER ;

-- Dumping structure for function onedbi_template.fn_force_json_array
DELIMITER //
CREATE FUNCTION `fn_force_json_array`(
	in_json JSON
) RETURNS json
BEGIN
RETURN CONCAT('[',TRIM(']' FROM TRIM('[' FROM in_json)),']');
END//
DELIMITER ;

-- Dumping structure for function onedbi_template.fn_ms_since_then
DELIMITER //
CREATE FUNCTION `fn_ms_since_then`(
	in_then DATETIME(4)
) RETURNS int
    DETERMINISTIC
BEGIN
RETURN (MICROSECOND(NOW(4)) - MICROSECOND(in_then)) / 1000
  + (UNIX_TIMESTAMP(NOW(4)) - UNIX_TIMESTAMP(in_then)) * 1000;
END//
DELIMITER ;

-- Dumping structure for procedure onedbi_template.mod_execute_queries
DELIMITER //
CREATE PROCEDURE `mod_execute_queries`()
BEGIN
	/*
Input: tmp_in_execute_mult_queries
	- qry
*/
	DECLARE done INT DEFAULT 0;
	DECLARE qry VARCHAR(2000);
	DECLARE cur CURSOR FOR SELECT * FROM tmp_in_execute_mult_queries;
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
	
	OPEN cur;
	start_loop: LOOP
		FETCH cur INTO qry;
		IF done = 1 THEN 
			LEAVE start_loop;
		END IF;
		
		CALL mod_execute_query(qry);
	END LOOP;
	
	CLOSE cur;
END//
DELIMITER ;

-- Dumping structure for procedure onedbi_template.mod_execute_query
DELIMITER //
CREATE PROCEDURE `mod_execute_query`(
    IN in_sql TEXT
)
BEGIN
    -- Set the SQL query to a session variable
    SET @in_sql = in_sql;

    -- Prepare the SQL statement
    PREPARE stmt FROM @in_sql;

    -- Execute the prepared statement
    EXECUTE stmt;

    -- Deallocate the prepared statement
    DEALLOCATE PREPARE stmt;
END//
DELIMITER ;

-- Dumping structure for table onedbi_template.trans_accounts
CREATE TABLE IF NOT EXISTS `trans_accounts` (
  `account_id` int NOT NULL AUTO_INCREMENT,
  `account_name` varchar(45) NOT NULL,
  `user_id` varchar(45) NOT NULL,
  PRIMARY KEY (`account_id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Dumping data for table onedbi_template.trans_accounts: ~2 rows (approximately)
INSERT INTO `trans_accounts` (`account_id`, `account_name`, `user_id`) VALUES
	(1, 'Account 1', '1'),
	(2, 'Account 2 ', '1');

-- Dumping structure for table onedbi_template.trans_entries
CREATE TABLE IF NOT EXISTS `trans_entries` (
  `entry_id` int NOT NULL AUTO_INCREMENT,
  `entry_date` date NOT NULL,
  `entry_desc` varchar(255) NOT NULL,
  `amount` decimal(10,5) NOT NULL,
  `debit_account_id` int NOT NULL,
  `credit_account_id` int NOT NULL,
  `user_id` int NOT NULL,
  PRIMARY KEY (`entry_id`),
  KEY `fk_accounts_idx` (`debit_account_id`),
  KEY `fk_cr_account_idx` (`credit_account_id`),
  CONSTRAINT `fk_cr_account` FOREIGN KEY (`credit_account_id`) REFERENCES `trans_accounts` (`account_id`),
  CONSTRAINT `fk_dr_account` FOREIGN KEY (`debit_account_id`) REFERENCES `trans_accounts` (`account_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Dumping data for table onedbi_template.trans_entries: ~1 rows (approximately)
INSERT INTO `trans_entries` (`entry_id`, `entry_date`, `entry_desc`, `amount`, `debit_account_id`, `credit_account_id`, `user_id`) VALUES
	(1, '2024-07-22', 'Test - Update', 10000.00000, 2, 1, 1);

-- Dumping structure for table onedbi_template._seed_trans_accounts
CREATE TABLE IF NOT EXISTS `_seed_trans_accounts` (
  `account_id` int NOT NULL AUTO_INCREMENT,
  `account_name` varchar(45) NOT NULL,
  `user_id` varchar(45) NOT NULL,
  PRIMARY KEY (`account_id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Dumping data for table onedbi_template._seed_trans_accounts: ~2 rows (approximately)
INSERT INTO `_seed_trans_accounts` (`account_id`, `account_name`, `user_id`) VALUES
	(1, 'Account 1', '1'),
	(2, 'Account 2 ', '1');

-- Dumping structure for table onedbi_template._seed_trans_entries
CREATE TABLE IF NOT EXISTS `_seed_trans_entries` (
  `entry_id` int NOT NULL AUTO_INCREMENT,
  `entry_date` date NOT NULL,
  `entry_desc` varchar(255) NOT NULL,
  `amount` decimal(10,5) NOT NULL,
  `debit_account_id` int NOT NULL,
  `credit_account_id` int NOT NULL,
  `user_id` int NOT NULL,
  PRIMARY KEY (`entry_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Dumping data for table onedbi_template._seed_trans_entries: ~1 rows (approximately)
INSERT INTO `_seed_trans_entries` (`entry_id`, `entry_date`, `entry_desc`, `amount`, `debit_account_id`, `credit_account_id`, `user_id`) VALUES
	(1, '2024-07-18', 'Entry 1', 1000.00000, 1, 2, 1);

-- Dumping structure for procedure onedbi_template._view_dbf_functions
DELIMITER //
CREATE PROCEDURE `_view_dbf_functions`()
BEGIN

SELECT a.function_id,
    a.function_name,
	fn_dbi_get_functionality_sql(function_name, a.eg_params) AS dbf_sql,
	fn_dbi_get_functionality_proc_name(function_name) AS dbf_proc,
    IF(c.specific_name IS NULL, 0, 1) AS dbf_does_exist    
FROM dbi_functionality a
LEFT JOIN (
	SELECT specific_name
	FROM INFORMATION_SCHEMA.ROUTINES
	WHERE routine_schema = DATABASE()
) c ON c.specific_name = fn_dbi_get_functionality_proc_name(a.function_name)
;

END//
DELIMITER ;

/*!40103 SET TIME_ZONE=IFNULL(@OLD_TIME_ZONE, 'system') */;
/*!40101 SET SQL_MODE=IFNULL(@OLD_SQL_MODE, '') */;
/*!40014 SET FOREIGN_KEY_CHECKS=IFNULL(@OLD_FOREIGN_KEY_CHECKS, 1) */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40111 SET SQL_NOTES=IFNULL(@OLD_SQL_NOTES, 1) */;
