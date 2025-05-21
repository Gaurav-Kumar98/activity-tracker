Here's a structured, step-by-step plan to build your real-time activity tracker using the specified tech stack:

---

### **Project Architecture Overview**
```
[Phone Sensor] → [Flask API] → [Kafka] → [Spark Streaming] → [Snowflake] → [Grafana]
```

---

### **Step 1: Local Environment Setup**
**Objective**: Prepare free/local tools for development.

1. **Docker Installation** 
   - Use Docker Desktop to containerize services (Kafka, Spark, Grafana).  
   - Create a `docker-compose.yml` file to deploy:  
     - Zookeeper + Kafka Broker  
     - Kafka Connect (with Snowflake connector)  
     - Spark  
     - Grafana  

2. **Python Environment**  
   - Create a virtual environment for Flask and Kafka Python libraries (`confluent-kafka`, `flask`).  

3. **Android Sensor Logger Setup**  
   - Configure the app to send sensor data to `http://localhost:5000/sensor-data` (accelerometer + gyroscope at 1Hz).  

---

### **Step 2: Project Structure**
```
activity-tracker/  
├── docker/  
│   ├── connector-configs/      # Snowflake connector configs  
│   └── grafana-dashboards/        # Preloaded dashboard JSON  
├── flaskserver/  
│   ├── app.py                     # Flask API endpoint  
│   └── requirements.txt           # Flask, confluent-kafka  
├── spark-streaming/             # Spark Streaming processing logic (Python)  
├── sql/                           # DDL for Snowflake tables (if manually managed)  
└── README.md                      # Setup instructions  
```

---

### **Step 3: Data Ingestion Pipeline**
**Objective**: Stream sensor data from phone to Kafka.

1. **Flask API (Producer)**  
   - Endpoint: `POST /sensor-data` to receive JSON payload from the phone.  
   - Data Format:  
     ```json
     {
       "timestamp": "2023-09-20T12:00:00",
       "sensor_type": "accelerometer",
       "x": 0.5, "y": -0.2, "z": 9.8
     }
     ```
   - Forward each event to a Kafka topic `raw_sensor_data` using `confluent-kafka` Python client.  

2. **Kafka Topic Initialization**  
   - Create topics:  
     - `raw_sensor_data` (unprocessed data)  
     - `processed_activity` (activity classification output)  

---

### **Step 4: Real-Time Processing**
**Objective**: Detect activities (walking, running, stationary) using accelerometer data.

1. **Spark Streaming Setup**  
   - Use PySpark to process data from the `raw_sensor_data` Kafka topic.
   - Employ a sliding window (e.g., 1-second window, sliding every 500 milliseconds as per `activity_detection.py`) to calculate:  
     - **Magnitude**: `SQRT(x² + y² + z²)`  
     - **Average Magnitude**: Identify movement intensity.  
   - Apply thresholds to classify activities:  
     - (Example thresholds, adjust based on `activity_detection.py` or further analysis) 
     - Avg Magnitude < threshold1 → Stationary  
     - threshold1 ≤ Avg Magnitude < threshold2 → Walking  
     - Avg Magnitude ≥ threshold2 → Running  

2. **Output Stream**  
   - Write classified activities to `processed_activity` Kafka topic with schema (example, adjust based on `activity_detection.py`):  
     ```json
     {
       "timestamp": "2023-09-20T12:00:00",
       "activity": "walking",
       "confidence": 0.85
     }
     ```

---

### **Step 5: Storage & Batch Analysis**
**Objective**: Store raw and processed data for visualization.

1. **Snowflake Setup**  
   - Create database (e.g., `ACTIVITY_DB`) and schemas (e.g., `RAW_DATA`, `PROCESSED_DATA`).
   - Define tables (example, actual schema might differ based on Snowflake connector behavior):  
     - `RAW_DATA.ACTIVITY_RECORDS` (for `raw_sensor_data` topic)
     - `PROCESSED_DATA.USER_ACTIVITY_PROCESSED` (for `processed_activity` topic)
     - Columns will likely be inferred by the Snowflake Kafka Connector based on the JSON data structure.

2. **Kafka Connect Sink (Snowflake)**  
   - Configure Snowflake Kafka connector to auto-ingest:  
     - `raw_sensor_data` topic → `ACTIVITY_DB.RAW_DATA.ACTIVITY_RECORDS` table  
     - `processed_activity` topic → `ACTIVITY_DB.PROCESSED_DATA.USER_ACTIVITY_PROCESSED` table  
   - Connector configurations are in `connector-configs/snowflake-sink-raw-config.json` and `connector-configs/snowflake-sink-processed-config.json`.

---

### **Step 6: Visualization & Monitoring**
**Objective**: Build real-time dashboards.

1. **Grafana Setup**  
   - Connect to Snowflake as a data source (using the Grafana Snowflake plugin).  
   - Create two dashboards:  
     - **Raw Sensor Data**: Time-series plot of accelerometer/gyroscope values.  
     - **Activity Recognition**:  
       - Gauge for current activity state.  
       - Histogram of daily activity distribution.  

2. **Alerting (Optional)**  
   - Configure Grafana alerts for anomalies (e.g., prolonged high magnitude = "fall detection").  

---

### **Step 7: Testing & Validation**
1. **End-to-End Test**  
   - Send test data from phone → Verify Kafka topics → Check Snowflake tables → Validate Grafana charts.  

2. **Performance Tuning**  
   - Optimize Kafka partition count/consumer groups.  
   - Optimize Spark Streaming job (e.g., executor resources, windowing strategy).
   - Review Snowflake query performance and warehouse sizing.  

---

### **Step 8: Deployment & Documentation**
1. **GitHub Repository**  
   - Include:  
     - `docker-compose.yml`  
     - Kafka Connect configurations for Snowflake  
     - Spark Streaming scripts
     - SQL DDL for Snowflake (if any are manually managed)  
     - Screenshots of Grafana dashboards  

2. **Portfolio Summary**  
   - Highlight:  
     - Real-time processing with Spark Streaming  
     - Dockerized architecture  
     - Scalable data warehousing with Snowflake  

---

### **Tools Summary**
| Component       | Tool                 | Use Case                          |
|-----------------|----------------------|-----------------------------------|
| Ingestion       | Flask + Kafka        | Receive and forward sensor data   |
| Processing      | Spark Streaming      | Activity classification           |
| Storage         | Snowflake            | Scalable data warehousing         |
| Visualization   | Grafana              | Real-time dashboards              |
| Orchestration   | Docker               | Local container management        |

---

### **Next Action Plan**
1. Set up Docker containers for Kafka/Spark/Grafana.  
2. Build the Flask producer and test data flow to Kafka.  
3. Configure Snowflake Kafka Connect sink connectors.  
4. Implement activity classification logic in Spark Streaming (Python).  
5. Build Grafana dashboards connecting to Snowflake.  

This structure ensures modular development and showcases your ability to design a production-like real-time system.