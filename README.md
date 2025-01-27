# MySQL Logic Base Template

A MySQL-based framework for building robust, flexible, and secure database interfaces with built-in authorization, logging, and testing capabilities.

## Table of Contents

1. [Introduction](#introduction)
2. [Database Structure](#database-structure)
3. [Core Components](#core-components)
   - [Procedures](#procedures)
   - [Functions](#functions)
   - [Tables](#tables)
4. [Usage Guide](#usage)
5. [Testing](#testing)
6. [Contributing](#contributing)
7. [License](#license)

## Introduction

The MySQL Logic Base Template provides a structured foundation for database operations, featuring:

- Authorization management
- Request/response handling
- Comprehensive logging
- Built-in testing framework
- Seed data management

## Database Structure

The framework consists of three main component types:

- **📝 Procedures**: Handle authorization, logging, and query execution
- **⚙️ Functions**: Provide utility operations (string cleaning, JSON handling, etc.)
- **📊 Tables**: Store operational and test data

## Core Components

### Procedures

#### Database Interface (DBI)

- `dbi_authorise`: Handles permission checks
- `dbi_call`: Main entry point for function execution
- `dbi_fn_get_entry`: Retrieves entry details
- `dbi_fn_update_entry`: Updates entry information

#### Response Handling

- `dbi_response_initiate`: Creates initial response structure
- `dbi_response_set_body_field`: Updates response body
- `dbi_response_set_err_msg`: Sets error messages
- `dbi_response_set_status`: Updates response status

#### Testing & Utilities

- `dbut_run`: Executes test suite
- `dbut_run_tests`: Runs and reports test results
- `dbut_seed_database`: Initializes test data
- `dbut_test_functionality`: Tests specific functions
- `dbut_truncate_before_template`: Cleans test environment

#### Module Operations

- `mod_execute_queries`: Runs multiple queries
- `mod_execute_query`: Executes single query
- `mod_get_seed_tables`: Manages seed data tables

### Functions

#### String & JSON Operations

- `fn_clean_string`: Standardizes string format
- `fn_compare_json_paths`: Compares JSON structures
- `fn_force_json_array`: Ensures JSON array format

#### DBI Utilities

- `fn_dbi_get_functionality_proc_name`: Gets procedure names
- `fn_dbi_get_functionality_sql`: Generates SQL
- `fn_dbi_get_response`: Retrieves response data
- `fn_dbi_response_get_err_msg`: Gets error messages
- `fn_dbi_response_get_status`: Gets response status

#### Testing & Time

- `fn_dbut_compare_responses`: Validates test responses
- `fn_dbut_get_seed_prefix`: Manages seed data prefixes
- `fn_ms_since_then`: Calculates time differences

### Tables

#### Core Tables

- `dbi_calls`: Request/response logs
- `dbi_functionality`: Available functions
- `dbi_statuses`: HTTP-style status codes

#### Testing Tables

- `dbut_tests`: Test execution records
- `dbut_unit_tests`: Test results
- `dbut_unit_test_cases`: Test definitions

#### Seed Data

- `_seed_trans_accounts`: Account test data
- `_seed_trans_entries`: Entry test data

## Usage Guide

1. **Initial Setup**

   ```sql
   -- Import the template
   SOURCE template.sql
   ```

2. **Making Calls**

   ```sql
   -- Example: Get an entry
   CALL dbi_call('get_entry', 1, '{"userId": 1, "entryId": 1}', @call_id);
   ```

3. **Checking Results**
   ```sql
   -- View call response
   SELECT * FROM dbi_calls WHERE call_id = @call_id;
   ```

## Testing

1. **Run All Tests**

   ```sql
   CALL dbut_run_tests();
   ```

2. **View Results**
   ```sql
   SELECT * FROM dbut_tests;
   SELECT * FROM dbut_unit_tests;
   ```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
