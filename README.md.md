# OneDBI Template README

## Table of Contents
1. [Introduction](#introduction)
2. [Database Structure](#database-structure)
3. [Procedures](#procedures)
4. [Functions](#functions)
5. [Tables](#tables)
6. [Usage](#usage)
7. [Testing](#testing)
8. [Contributing](#contributing)
9. [License](#license)

## Introduction
The OneDBI Template is a MySQL-based framework designed to facilitate the development of a robust, flexible, and secure database interface. It includes predefined procedures, functions, and tables that manage database operations, authorization, and testing.

## Database Structure
The database is structured to include various procedures, functions, and tables to handle different aspects of database operations. The primary components are:
- **Procedures**: For handling specific tasks such as authorization, logging, and executing queries.
- **Functions**: For utility operations like cleaning strings, comparing JSON paths, and fetching responses.
- **Tables**: For storing calls, entries, accounts, functionality details, and test data.

## Procedures

### dbi_authorise
This procedure handles authorization checks for specific functions. It ensures that the user calling a function has the necessary permissions to perform the action.

### dbi_call
This procedure logs a call to the database interface and handles the execution of the requested function. It includes error handling and logging of the results.

### dbi_fn_get_entry
Fetches details of a specific entry based on the provided arguments.

### dbi_fn_update_entry
Updates the details of a specific entry based on the provided arguments.

### dbi_response_initiate
Initializes the response JSON for a call.

### dbi_response_set_body_field
Sets a specific field in the response JSON body.

### dbi_response_set_err_msg
Sets the error message in the response JSON.

### dbi_response_set_status
Sets the status code in the response JSON.

### dbut_run
Runs all unit tests and logs the results.

### dbut_run_tests
Runs the defined unit tests and returns the results of the tests.

### dbut_seed_database
Seeds the database with initial data from predefined seed tables.

### dbut_test_functionality
Tests all functionalities and logs the results in the unit tests table.

### dbut_truncate_before_template
Truncates the necessary tables before running the template.

### framework_refresh
Refreshes the framework by dropping seed tables and truncating functionality tables.

### mod_execute_queries
Executes multiple queries from a temporary table.

### mod_execute_query
Executes a single query.

### mod_get_seed_tables
Fetches all seed tables based on a predefined prefix.

## Functions

### fn_clean_string
Cleans a given string by trimming spaces, replacing multiple spaces with a single space, replacing spaces with underscores, and converting the string to lowercase.

### fn_compare_json_paths
Compares JSON paths between two JSON objects and returns the failed fields.

### fn_dbi_get_functionality_proc_name
Returns the procedure name for a given function name.

### fn_dbi_get_functionality_sql
Returns the SQL for a given function name and parameters.

### fn_dbi_get_response
Fetches the current response JSON.

### fn_dbi_response_get_err_msg
Fetches the error message from the response JSON.

### fn_dbi_response_get_status
Fetches the status from the response JSON.

### fn_dbut_compare_responses
Compares the expected and actual responses and returns whether they match.

### fn_dbut_get_seed_prefix
Returns the prefix for the seed tables.

### fn_force_json_array
Ensures a JSON object is treated as an array.

### fn_ms_since_then
Calculates the milliseconds elapsed since a given datetime.

## Tables

### dbi_calls
Logs all calls to the database interface.

### dbi_functionality
Stores details about the available functionalities.

### dbi_statuses
Stores status codes and their descriptions.

### dbut_tests
Stores test runs.

### dbut_unit_tests
Stores unit test results.

### dbut_unit_test_cases
Stores unit test cases.

### _seed_trans_accounts
Seed data for transaction accounts.

### _seed_trans_entries
Seed data for transaction entries.

## Usage
1. **Setup the Database**: Import the SQL file to your MySQL database server.
2. **Run Procedures**: Use the procedures to interact with the database.
3. **Check Responses**: Responses from calls can be checked by querying the `dbi_calls` table or the response functions.

## Testing
1. **Run Tests**: Execute `CALL dbut_run_tests();` to run all unit tests.
2. **Check Results**: Review the test results in the `dbut_tests` and `dbut_unit_tests` tables.

## Contributing
1. **Fork the Repository**: Create a fork of the repository to make your changes.
2. **Create a Branch**: Create a new branch for your changes.
3. **Make Changes**: Make your changes and commit them with clear messages.
4. **Submit a Pull Request**: Submit a pull request to the main repository.

---

This README file provides a comprehensive guide to understanding the OneDBI Template, including its structure, components, and usage. For more detailed explanations of each component, refer to the comments within the SQL file.
