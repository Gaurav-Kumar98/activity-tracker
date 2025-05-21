# Activity Tracker Project

## Overview

This project implements a real-time activity tracking system. Sensor data (specifically accelerometer readings) is collected from a mobile device, sent to a Flask API, processed using Spark Streaming to detect user activity (e.g., stationary, walking, running), and then stored in Snowflake. The processed data can then be visualized using Grafana.

## Architecture

The data flows through the system as follows:

`[Mobile Device Sensor] -> [Flask API] -> [Kafka (raw_sensor_data topic)] -> [Spark Streaming] -> [Kafka (processed_activity topic)] -> [Kafka Connect (Snowflake Sink)] -> [Snowflake] -> [Grafana]`

## Technology Stack

*   **Data Ingestion:** Flask (Python)
*   **Message Broker:** Apache Kafka
*   **Real-time Processing:** Apache Spark Streaming (PySpark)
*   **Data Storage:** Snowflake
*   **Data Sink:** Kafka Connect with Snowflake Connector
*   **Visualization:** Grafana
*   **Containerization:** Docker, Docker Compose

## Project Structure

```
.
├── spark-streaming/
│   └── activity_detection.py  # Spark Streaming job for activity classification
├── flaskserver/
│   └── app.py                 # Flask API to receive sensor data
├── connector-configs/
│   ├── snowflake-sink-raw-config.json      # Kafka Connect config for raw data to Snowflake
│   └── snowflake-sink-processed-config.json # Kafka Connect config for processed data to Snowflake
├── snowflake-keys/
│   └── rsa_key.p8             # Private key for Snowflake connection (ensure this is in .gitignore)
├── docker-compose.yml         # Docker Compose configuration
├── README.md                  # This file
└── (other configuration files like .env if used)
```

## Setup and Installation

1.  **Prerequisites:**
    *   Docker and Docker Compose installed.
    *   Snowflake account and database (`ACTIVITY_DB`) created.
    *   Snowflake user with appropriate permissions and RSA key pair generated. Place the private key (`rsa_key.p8`) in the `snowflake-keys/` directory.
    *   Update `.env` (you might need to create this file) with your Snowflake connection details:
        ```env
        SNOWFLAKE_USER=your_user
        SNOWFLAKE_PRIVATE_KEY_PATH=/path/in/container/to/rsa_key.p8 
        SNOWFLAKE_ACCOUNT=your_account_identifier
        SNOWFLAKE_WAREHOUSE=your_warehouse
        SNOWFLAKE_DATABASE=ACTIVITY_DB
        SNOWFLAKE_RAW_SCHEMA=RAW_DATA
        SNOWFLAKE_PROCESSED_SCHEMA=PROCESSED_DATA
        ```
        *Note: `SNOWFLAKE_PRIVATE_KEY_PATH` in the `.env` should correspond to the path *inside* the Kafka Connect container as mounted in `docker-compose.yml`.*

2.  **Environment Variables for Kafka Connect:**
    The `docker-compose.yml` file should mount the `snowflake-keys` directory and pass necessary environment variables to the Kafka Connect service for Snowflake connectivity. These are typically set in the `environment` section of the `connect` service in `docker-compose.yml`, referencing the `.env` file.

3.  **Build and Run Docker Containers:**
    ```bash
    docker-compose up --build -d
    ```

## Running the Application

1.  Start all services using `docker-compose up --build -d`.
2.  Send sensor data to the Flask API endpoint (typically `http://localhost:5000/data` if running locally mapped). The expected payload format for accelerometer data should include `sensor_reading["name"]` as `"accelerometer"` and a `values` array `[x, y, z]`.
    Example:
    ```json
    {
      "messageId": "some-uuid-message",
      "sessionId": "some-uuid-session",
      "deviceId": "some-uuid-device",
      "sensorReadings": [
        {
          "name": "accelerometer",
          "timestamp": 1678886400000,
          "values": [0.1, 0.2, 9.8]
        }
      ]
    }
    ```
3.  Monitor logs for each service:
    ```bash
    docker-compose logs -f spark
    docker-compose logs -f connect
    docker-compose logs -f kafka
    docker-compose logs -f flaskserver
    ```

## Data Flow

1.  **Raw Data:**
    *   The Flask API (`flaskserver/app.py`) receives sensor data and publishes it to the `raw_sensor_data` Kafka topic.
    *   Kafka Connect, using `connector-configs/snowflake-sink-raw-config.json`, sinks messages from `raw_sensor_data` to the `ACTIVITY_RECORDS` table in the `RAW_DATA` schema of the `ACTIVITY_DB` Snowflake database.

2.  **Processed Data:**
    *   The Spark Streaming job (`spark-streaming/activity_detection.py`) consumes data from `raw_sensor_data`.
    *   It filters for `accelerometer` sensor types, calculates the magnitude of acceleration, and classifies activity (e.g., stationary, walking, running) based on windowed aggregations (currently using magnitude, previously standard deviation of magnitude).
    *   The processed data, including `messageId`, `sessionId`, `deviceId`, `timestamp`, `magnitude`, and `activity`, is published to the `processed_activity` Kafka topic.
    *   Kafka Connect, using `connector-configs/snowflake-sink-processed-config.json`, sinks messages from `processed_activity` to the `USER_ACTIVITY_PROCESSED` table in the `PROCESSED_DATA` schema of `ACTIVITY_DB`.

## Real-time Processing (`spark-streaming/activity_detection.py`)

*   Connects to Kafka to read from the `raw_sensor_data` topic.
*   Parses the JSON messages.
*   Filters for `sensorType == "accelerometer"` (gravity-compensated readings).
*   Calculates the magnitude of the acceleration vector: `sqrt(x^2 + y^2 + z^2)`.
*   Performs a windowed aggregation (e.g., average magnitude, or standard deviation of magnitude) over a defined time window and slide duration.
*   Classifies activity based on thresholds applied to the aggregated metric.
*   Writes the classified activity data (including `messageId`, `sessionId`, `deviceId`, `timestamp`, calculated metric, and `activity` type) to the `processed_activity` Kafka topic.
*   Includes debug streams (commented out by default) to output intermediate dataframes to the console for troubleshooting.

**Important for Spark Checkpointing:**
The Spark job uses checkpointing. If you change the schema of the data being processed or the aggregation logic (e.g., columns in `groupBy`), you **must** clear the checkpoint directory (`/tmp/checkpoint/activity_detection_kafka` inside the Spark container) before restarting the Spark application. This can be done by:
  *   `docker exec -it <spark_container_id_or_name> rm -rf /tmp/checkpoint/activity_detection_kafka`
  *   Or, by adding a command to `docker-compose.yml` to remove it on startup (less ideal for production but useful for dev).

## Visualization

*   Grafana can be configured with Snowflake as a data source.
*   Create dashboards in Grafana to visualize the data from the `USER_ACTIVITY_PROCESSED` table (and potentially `ACTIVITY_RECORDS`) in Snowflake.
*   Example visualizations could include:
    *   Time series of activity types.
    *   Count of activities over time.
    *   Magnitude or standard deviation of magnitude values.

---

This README provides a comprehensive guide to the project. Remember to keep it updated as the project evolves.
Ensure that `snowflake-keys/rsa_key.p8` and any files containing sensitive credentials (like a `.env` file) are added to your `.gitignore` file.
