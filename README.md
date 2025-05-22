# Activity Tracker Project

## Overview

This project implements a real-time activity tracking system. Sensor data (specifically accelerometer readings) is collected from a mobile device, sent to a Flask API, processed using Spark Streaming to detect user activity (e.g., stationary, walking, running), and then stored in Snowflake. The processed data can then be visualized using Grafana Cloud.

## Architecture

The data flows through the system as follows:

`[Mobile Device Sensor] -> [Flask API (Local)] -> [Kafka (raw_sensor_data topic)] -> [Spark Streaming] -> [Kafka (processed_activity topic)] -> [Kafka Connect (Snowflake Sink)] -> [Snowflake] -> [Grafana Cloud]`

## Technology Stack

*   **Data Ingestion:** Flask (Python, running locally)
*   **Message Broker:** Apache Kafka
*   **Real-time Processing:** Apache Spark Streaming (PySpark)
*   **Data Storage:** Snowflake
*   **Data Sink:** Kafka Connect with Snowflake Connector
*   **Visualization:** Grafana Cloud
*   **Containerization:** Docker, Docker Compose (for Kafka, Spark, and Kafka Connect)

## Project Structure

```
.
├── spark-streaming/
│   └── activity_detection.py  # Spark Streaming job for activity classification
├── flaskserver/
│   └── app.py                 # Flask API to receive sensor data (runs locally)
├── connector-configs/
│   ├── snowflake-sink-raw-config.json      # Kafka Connect config for raw data to Snowflake
│   └── snowflake-sink-processed-config.json # Kafka Connect config for processed data to Snowflake
├── docker/
│   └── grafana-dashboards/
│       └── activity_monitoring_dashboard.json  # Pre-configured Grafana dashboard
├── docker-compose.yml         # Docker Compose configuration
└── README.md                  # This file
```

## Setup and Installation

1.  **Prerequisites:**
    *   Docker and Docker Compose installed for running Kafka, Spark, and Kafka Connect.
    *   Python environment for running the Flask server locally.
    *   Snowflake account and database (`ACTIVITY_DB`) created.
    *   Snowflake user with appropriate permissions and RSA key pair generated.
    *   Grafana Cloud account with Snowflake data source configured.

2.  **Snowflake Configuration:**
    *   Snowflake private key is embedded directly within the Kafka Connect configuration JSON files in the `connector-configs/` directory.
    *   Ensure your Snowflake user has the necessary permissions to access the specified database and schemas.

3.  **Build and Run Docker Containers:**
    ```bash
    docker-compose up --build -d
    ```

4.  **Start Flask Server Locally:**
    ```bash
    cd flaskserver
    python app.py
    ```

## Running the Application

1.  Start the Kafka, Spark, and Kafka Connect services using `docker-compose up --build -d`.
2.  Start the Flask server locally.
3.  Send sensor data to the Flask API endpoint (typically `http://localhost:5000/sensor-data` if running locally). The expected payload format for accelerometer data should include `sensor_reading["name"]` as `"accelerometer"` and a `values` array `[x, y, z]`.
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
4.  Monitor logs for each service:
    ```bash
    docker-compose logs -f spark
    docker-compose logs -f connect
    docker-compose logs -f kafka
    ```
5.  View logs for the Flask server in its terminal window.

## Data Flow

1.  **Raw Data:**
    *   The Flask API (`flaskserver/app.py`) running locally receives sensor data and publishes it to the `raw_sensor_data` Kafka topic.
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

*   Configure Grafana Cloud with Snowflake as a data source.
*   Create dashboards in Grafana Cloud to visualize the data from the `USER_ACTIVITY_PROCESSED` table (and potentially `ACTIVITY_RECORDS`) in Snowflake.
*   A pre-configured dashboard is available in the `docker/grafana-dashboards/activity_monitoring_dashboard.json` file, which can be imported directly into Grafana Cloud.
*   The dashboard includes:
    *   Current activity state display
    *   Confidence level gauge
    *   Average magnitude visualizations
    *   Activity timeline
    *   Activity distribution pie chart
    *   Recent activity records table

---

This README provides a comprehensive guide to the project. Remember to keep it updated as the project evolves.
Ensure that any files containing sensitive credentials are properly secured and not committed to version control.

## Related Articles

For more detailed insights and explanations about this project:

* [Medium Article: From My Phone to the Cloud: Building a Real-Time Activity Tracker with Kafka, Spark, and Snowflake](https://medium.com/@gk0415439/from-my-phone-to-the-cloud-building-a-real-time-activity-tracker-with-kafka-spark-and-snowflake-4e528d0e83a7)
* [LinkedIn Article: Project Deep Dive: Architecting and Implementing a Streaming Data Pipeline with Kafka, Spark, Snowflake, and Grafana](https://www.linkedin.com/pulse/project-deep-dive-architecting-implementing-streaming-gaurav-kumar-a0w7c)
