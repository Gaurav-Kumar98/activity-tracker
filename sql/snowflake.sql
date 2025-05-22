-- Best practice: Use a role that has privileges to create these objects,
-- like ACCOUNTADMIN for initial setup, or a dedicated setup role.
-- For simplicity here, we assume you are using a role with sufficient privileges (e.g., ACCOUNTADMIN).

-- 1. Create a Warehouse (e.g., KAFKA_CONNECT_WH)
CREATE WAREHOUSE IF NOT EXISTS KAFKA_CONNECT_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60 -- Suspends after 60 seconds of inactivity
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Warehouse for Kafka Connector and data loading';

-- 2. Create a Database (e.g., ACTIVITY_DB)
CREATE DATABASE IF NOT EXISTS ACTIVITY_DB
  COMMENT = 'Database for sensor activity data';

-- 3. Create a Schema (e.g., RAW_DATA)
CREATE SCHEMA IF NOT EXISTS ACTIVITY_DB.RAW_DATA
  COMMENT = 'Schema for raw sensor data from Kafka';

CREATE SCHEMA IF NOT EXISTS ACTIVITY_DB.PROCESSED_DATA
  COMMENT = 'Schema for raw sensor data from Kafka';

-- Use the created objects for the current session (optional, but good practice)
USE WAREHOUSE KAFKA_CONNECT_WH;
USE DATABASE ACTIVITY_DB;
USE SCHEMA RAW_DATA;
USE SCHEMA PROCESSED_DATA;


-- Ensure you are using a role with user and role creation privileges (e.g., SECURITYADMIN or ACCOUNTADMIN)
-- USE ROLE SECURITYADMIN; -- Uncomment and run if you need to switch roles

-- 4. Create a Role (e.g., KAFKA_CONNECTOR_ROLE)
CREATE ROLE IF NOT EXISTS KAFKA_CONNECTOR_ROLE
  COMMENT = 'Role for Kafka Connector access';

-- Grant privileges to the role:
-- Usage on the warehouse
GRANT USAGE ON WAREHOUSE KAFKA_CONNECT_WH TO ROLE KAFKA_CONNECTOR_ROLE;
-- Usage on the database
GRANT USAGE ON DATABASE ACTIVITY_DB TO ROLE KAFKA_CONNECTOR_ROLE;
-- Usage on the schema
GRANT USAGE ON SCHEMA ACTIVITY_DB.RAW_DATA TO ROLE KAFKA_CONNECTOR_ROLE;
GRANT USAGE ON SCHEMA ACTIVITY_DB.PROCESSED_DATA TO ROLE KAFKA_CONNECTOR_ROLE;
-- Privileges to create tables and stages in the schema (the connector needs this)
GRANT CREATE TABLE ON SCHEMA ACTIVITY_DB.RAW_DATA TO ROLE KAFKA_CONNECTOR_ROLE;
GRANT CREATE STAGE ON SCHEMA ACTIVITY_DB.RAW_DATA TO ROLE KAFKA_CONNECTOR_ROLE;
GRANT CREATE PIPE ON SCHEMA ACTIVITY_DB.RAW_DATA TO ROLE KAFKA_CONNECTOR_ROLE;
GRANT INSERT, SELECT ON TABLE ACTIVITY_DB.RAW_DATA.ACTIVITY_RECORDS TO ROLE KAFKA_CONNECTOR_ROLE;

GRANT CREATE TABLE ON SCHEMA ACTIVITY_DB.PROCESSED_DATA TO ROLE KAFKA_CONNECTOR_ROLE;
GRANT CREATE STAGE ON SCHEMA ACTIVITY_DB.PROCESSED_DATA TO ROLE KAFKA_CONNECTOR_ROLE;
GRANT CREATE PIPE ON SCHEMA ACTIVITY_DB.PROCESSED_DATA TO ROLE KAFKA_CONNECTOR_ROLE;
-- Add any other necessary DML privileges if the connector needs to modify data beyond inserts,
-- but for typical sink connectors, INSERT is handled via table/stage creation.

-- 5. Create a User (e.g., KAFKA_SINK_USER)
-- YOU WILL SET THE RSA_PUBLIC_KEY IN THE NEXT STEP.
-- For now, we create the user. Replace 'your_strong_password' with a secure password if you plan to use password auth temporarily.
-- However, key-pair authentication is recommended and what we are setting up.
CREATE USER IF NOT EXISTS KAFKA_SINK_USER
  -- PASSWORD = 'your_strong_password' -- Comment out or remove if using only key-pair auth
  LOGIN_NAME = 'KAFKA_SINK_USER'       -- This is the username you'll use
  DISPLAY_NAME = 'Kafka Sink User'
  DEFAULT_WAREHOUSE = 'KAFKA_CONNECT_WH'
  DEFAULT_ROLE = 'KAFKA_CONNECTOR_ROLE'
  DEFAULT_NAMESPACE = 'ACTIVITY_DB.RAW_DATA'
  MUST_CHANGE_PASSWORD = FALSE
  COMMENT = 'User for Kafka Connector to sink data into Snowflake';

CREATE USER IF NOT EXISTS KAFKA_SINK_PROCESSED_USER
  -- PASSWORD = 'your_strong_password' -- Comment out or remove if using only key-pair auth
  LOGIN_NAME = 'KAFKA_SINK_PROCESSED_USER'       -- This is the username you'll use
  DISPLAY_NAME = 'Kafka Sink Processed User'
  DEFAULT_WAREHOUSE = 'KAFKA_CONNECT_WH'
  DEFAULT_ROLE = 'KAFKA_CONNECTOR_ROLE'
  DEFAULT_NAMESPACE = 'ACTIVITY_DB.PROCESSED_DATA'
  MUST_CHANGE_PASSWORD = FALSE
  COMMENT = 'User for Kafka Connector to sink processed data into Snowflake';

-- Grant the role to the user
GRANT ROLE KAFKA_CONNECTOR_ROLE TO USER KAFKA_SINK_USER;
GRANT ROLE KAFKA_CONNECTOR_ROLE TO USER KAFKA_SINK_PROCESSED_USER;

-- It's good practice to also grant the role to your admin role (e.g., ACCOUNTADMIN)
-- if you want to easily manage objects created by the KAFKA_CONNECTOR_ROLE.
GRANT ROLE KAFKA_CONNECTOR_ROLE TO ROLE ACCOUNTADMIN; -- Uncomment if needed



-- Ensure you are using a role with privileges to alter users (e.g., SECURITYADMIN or ACCOUNTADMIN)
-- USE ROLE SECURITYADMIN; -- Uncomment and run if you need to switch roles if not already set

ALTER USER KAFKA_SINK_USER SET RSA_PUBLIC_KEY = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvJCXzQHmmnnPXpotvMi2zXD7G44UcvbuhYswlRdcVwjSuX9E3A24cM+jrVqcHLZYZ2YcHkbNjrAN4Spx7wXp1oKZIrE9wgQtTFB/tH5hsWcJR+pzut0IMZkNRLxp8JGukyAlqmq/2XIgzcHzR1xhyI88+CI3RyGvYicp9MlNuI5fA8IDRyjvZTtyNA16BZwfb1+RgnVwznMRP3qvSnLn2IzNiMgdHuAjJcuARtfOH395hQJDsEuIMd8R8TFTA3Z0m/pxNjgDZQYgXSy49DaXgucPv9esvU6M/JWHHi52LVttn6oEsikpX7WQxm8INja4eyjS+2sOwl8DFeuusShfIwIDAQAB';

ALTER USER KAFKA_SINK_PROCESSED_USER SET RSA_PUBLIC_KEY = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvJCXzQHmmnnPXpotvMi2zXD7G44UcvbuhYswlRdcVwjSuX9E3A24cM+jrVqcHLZYZ2YcHkbNjrAN4Spx7wXp1oKZIrE9wgQtTFB/tH5hsWcJR+pzut0IMZkNRLxp8JGukyAlqmq/2XIgzcHzR1xhyI88+CI3RyGvYicp9MlNuI5fA8IDRyjvZTtyNA16BZwfb1+RgnVwznMRP3qvSnLn2IzNiMgdHuAjJcuARtfOH395hQJDsEuIMd8R8TFTA3Z0m/pxNjgDZQYgXSy49DaXgucPv9esvU6M/JWHHi52LVttn6oEsikpX7WQxm8INja4eyjS+2sOwl8DFeuusShfIwIDAQAB';

-- 1. Create a role for Grafana
CREATE ROLE grafana_role;

-- 3. Grant the role usage on the warehouse
GRANT USAGE ON WAREHOUSE kafka_connect_wh TO ROLE grafana_role;

-- 4. Grant the role usage on your target database
-- Replace 'YOUR_TARGET_DATABASE' with your actual database name
GRANT USAGE ON DATABASE activity_db TO ROLE grafana_role;

-- 5. Grant the role usage on your target schema
-- Replace 'YOUR_TARGET_DATABASE' and 'YOUR_TARGET_SCHEMA'
GRANT USAGE ON SCHEMA activity_db.processed_data TO ROLE grafana_role;

-- 6. Grant the role select permissions on tables/views in the schema
-- This grants select on all tables and views. Adjust if you need more granular control.
GRANT SELECT ON ALL TABLES IN SCHEMA activity_db.processed_data TO ROLE grafana_role;
GRANT SELECT ON ALL VIEWS IN SCHEMA activity_db.processed_data TO ROLE grafana_role;

DROP USER IF EXISTS grafana_user;

-- 7. Create a user for Grafana
CREATE USER grafana_user
  PASSWORD = 'T3mp.4ccount' -- IMPORTANT: Use a strong, unique password
  LOGIN_NAME = 'grafana_user' -- Ensure this is unique
  MUST_CHANGE_PASSWORD = FALSE
  DEFAULT_ROLE = grafana_role
  DEFAULT_WAREHOUSE = kafka_connect_wh
  DEFAULT_NAMESPACE = 'activity_db.processed_data'; -- Optional: sets default db and schema

-- 8. Grant the role to the user
GRANT ROLE grafana_role TO USER grafana_user;