# From Phone Sensor to Snowflake: A Real-Time Activity Tracking Adventure

Ever wondered how to build a system that takes raw sensor data from your phone, processes it in real-time, and stores it in a modern data warehouse like Snowflake? I recently embarked on such a project, primarily as a learning exercise to dive into technologies I hadn't extensively used in my career: real-time/near real-time streaming pipelines and Snowflake. I was familiar with the "Sensor Logger" app, which can stream various phone sensor data, and an idea sparked: why not build an end-to-end activity tracker?

This post documents my journey, the architecture, the challenges, and how you can take such a project идея from a learning sandbox to something more robust.

## The "Why": Diving into New Tech

My main motivation was hands-on experience. While I understood the concepts, I wanted to get my hands dirty with:
*   **Real-time data ingestion and processing:** Moving beyond batch processing.
*   **Apache Spark Streaming:** A powerful engine for stream processing.
*   **Apache Kafka:** The de-facto standard for distributed streaming platforms.
*   **Snowflake:** A cloud-native data warehouse I was eager to explore.

Initially, I considered using PostgreSQL with the TimescaleDB extension for time-series data. However, to maximize my learning, I decided to pivot to Snowflake. This meant figuring out how to integrate it into a streaming pipeline.

## The Architecture: A Flow of Data

Here's a high-level look at the system that emerged:

**[Phone Sensor (Sensor Logger App)] → [Flask API] → [Apache Kafka] → [Apache Spark Streaming] → [Snowflake] → [Grafana]**

Let's break down each component:

### 1. Data Ingestion: Sensor Logger to Flask API

*   **Sensor Logger App:** This fantastic app (available on Android) can stream various sensor readings (accelerometer, gyroscope, etc.) via HTTP POST requests to a specified endpoint. I configured it to send `accelerometer` data (linear acceleration, excluding gravity).
*   **Flask API (`flaskserver/app.py`):** A simple Python Flask server receives the JSON payloads from the Sensor Logger app. It does minimal processing – mainly extracting relevant fields and forwarding the data to a Kafka topic.

    *   **Production Tip:** For a production setup, you'd want a more robust API:
        *   Use a production-grade WSGI server (like Gunicorn or uWSGI) behind a reverse proxy (like Nginx).
        *   Implement proper error handling, input validation, and potentially rate limiting.
        *   Secure the endpoint (e.g., with API keys or OAuth) if it's exposed publicly.
        *   Consider asynchronous request handling for better performance under load.

### 2. Data Streaming: Apache Kafka

*   **Kafka Topics:**
    *   `raw_sensor_data`: The Flask API publishes raw sensor readings here.
    *   `processed_activity`: Spark Streaming publishes the classified user activity (stationary, walking, running, sprinting) to this topic.
*   **Why Kafka?** It decouples the data producers (Flask API) from consumers (Spark Streaming, Kafka Connect), provides durability, and can handle high throughput.

    *   **Production Tip:**
        *   **Schema Management:** Use a Schema Registry (like Confluent Schema Registry) to manage and enforce schemas for your Kafka messages. This prevents data quality issues when producers or consumers change.
        *   **Topic Configuration:** Carefully plan topic partitioning and replication factors for scalability and fault tolerance.
        *   **Monitoring:** Set up monitoring for Kafka brokers, topics (lag, throughput), and consumer groups.
        *   **Security:** Enable SASL for authentication and SSL/TLS for encryption.

### 3. Real-Time Processing: Spark Streaming (`spark-streaming/activity_detection.py`)

This is where the magic happens! A PySpark Streaming application consumes data from the `raw_sensor_data` topic, performs transformations, and classifies user activity.

*   **Core Logic:**
    1.  **Read from Kafka:** Connects to Kafka and subscribes to `raw_sensor_data`.
    2.  **Parse JSON:** Deserializes the JSON messages using a predefined schema.
    3.  **Filter Sensor Data:** Filters for `accelerometer` readings (as I decided to use the data without gravity's influence).
    4.  **Calculate Magnitude:** Computes the magnitude of the 3-axis acceleration: `sqrt(x² + y² + z²)`.
    5.  **Windowed Aggregation:**
        *   Groups data into time windows (e.g., 10-second windows sliding every 2 seconds). This helps smooth out instantaneous fluctuations.
        *   Uses watermarking (`withWatermark`) to handle late-arriving data.
        *   Calculates the average magnitude (`avg_magnitude`) within each window for each user session and device.
    6.  **Activity Classification:** Based on the `avg_magnitude`, classifies activity:
        *   `avg_magnitude < 2.0 m/s²`: Stationary
        *   `avg_magnitude < 8.0 m/s²`: Walking
        *   `avg_magnitude < 20.0 m/s²`: Running
        *   `Otherwise`: Sprinting
        (These thresholds were tuned by observing the magnitude values for different activities using the gravity-excluded accelerometer.)
    7.  **Output to Kafka:** Publishes the classified activity (including session ID, device ID, activity type, confidence score, and average magnitude) as a JSON string to the `processed_activity` topic.

*   **Challenges & Learnings (Spark):**
    *   **Checkpointing & Schema Evolution:** Spark Streaming uses checkpointing to store intermediate state for fault tolerance. A major hurdle was when I modified the schema of the data being aggregated (e.g., adding fields to the `groupBy` clause). This caused `Provided schema doesn't match to the schema for existing state!` errors.
        *   **Solution:** For this project, I cleared the checkpoint directory (`/tmp/checkpoint/activity_detection_kafka` *inside the Spark container*) after schema changes.
        *   **Production Tip:** Handling schema evolution in stateful streaming applications is crucial. Strategies include versioning your state, using more flexible serialization formats (like Avro with schema evolution support), or planning for migration paths.
    *   **Debugging Streams:** `writeStream.format("console")` is your best friend for debugging Spark Streaming jobs at various stages. I used it to inspect raw Kafka data, parsed data, and intermediate calculations.
    *   **Threshold Tuning:** Activity classification thresholds are highly dependent on the specific sensor data and features used. I initially tried average magnitude including gravity, then standard deviation, and finally settled on average magnitude of the gravity-excluded accelerometer data, requiring careful tuning.

    *   **Production Tips (Spark Streaming):**
        *   **Code Modularity & Testing:** Structure your Spark code into reusable functions/classes and write unit/integration tests.
        *   **Configuration Management:** Externalize configurations (Kafka brokers, topics, window parameters, thresholds) instead of hardcoding.
        *   **Performance:** Monitor Spark UI for bottlenecks. Optimize resource allocation, manage backpressure, and choose appropriate shuffle partition sizes.
        *   **Reliability:** Implement robust error handling, alerting for job failures, and consider dead-letter queues for messages that fail processing.

### 4. Data Warehousing: Snowflake

*   **Snowflake Setup:**
    *   Database: `ACTIVITY_DB`
    *   Schemas:
        *   `RAW_DATA`: Stores raw sensor readings.
        *   `PROCESSED_DATA`: Stores classified user activities.
    *   Tables:
        *   `RAW_DATA.ACTIVITY_RECORDS`: Populated from `raw_sensor_data` Kafka topic.
        *   `PROCESSED_DATA.USER_ACTIVITY_PROCESSED`: Populated from `processed_activity` Kafka topic.
*   **Kafka Connect for Snowflake:** I used the official Snowflake Kafka Connector to sink data from Kafka topics directly into Snowflake tables. This is configured via JSON files (e.g., `snowflake-sink-raw-config.json`, `snowflake-sink-processed-config.json`) in the `connector-configs/` directory.

    *   **Production Tips (Snowflake):**
        *   **Security:**
            *   **Key Management:** Instead of committing credentials, use secure methods like Snowflake's key pair authentication, environment variables injected into your Docker containers (e.g., via Docker Compose or Kubernetes secrets), or a secrets management tool like HashiCorp Vault. *My approach for this project involved mounting the Snowflake keys file into the Kafka Connect container, which is a good step towards securing them.*
            *   **Network Policies & RBAC:** Use Snowflake's network policies to restrict access and Role-Based Access Control (RBAC) for fine-grained permissions.
        *   **Cost Optimization:**
            *   Choose appropriate virtual warehouse sizes and configure auto-suspend/resume.
            *   Define clustering keys on large tables to optimize query performance.
            *   Monitor query history and costs.
        *   **Data Governance:** Implement data quality checks, and define backup and recovery strategies (Snowflake's Time Travel is a great feature here).
        *   **Schema Design:** Design schemas for performance and to allow for evolution. Consider using `VARIANT` columns for semi-structured data if the schema is highly dynamic, though parsing it at read time has performance implications.

### 5. Visualization: Grafana

*   Grafana is set up to connect to Snowflake as a data source. This allows for creating dashboards to visualize the raw sensor data trends and the classified user activities over time.

    *   **Production Tip:** Optimize Grafana dashboards for performance, especially with large datasets. Use appropriate aggregations in your queries. Manage user roles and permissions for dashboard access.

## Dockerizing the System (`docker-compose.yml`)

The entire stack (Kafka, Zookeeper, Spark, Kafka Connect, Flask API, Grafana) is orchestrated using Docker Compose. This makes it easy to spin up and tear down the environment.

*   **Production Tip:**
    *   **Optimized Images:** Create lean Docker images. Use multi-stage builds.
    *   **CI/CD:** Implement a CI/CD pipeline (e.g., Jenkins, GitLab CI, GitHub Actions) for automated builds, testing, and deployment.
    *   **Infrastructure as Code (IaC):** For more complex deployments, consider tools like Terraform or CloudFormation to manage your cloud infrastructure.
    *   **Centralized Logging & Monitoring:** Use a centralized logging solution (e.g., ELK stack, Splunk, Grafana Loki) and comprehensive monitoring (e.g., Prometheus, Grafana) across all components.

## Key Takeaways & Project Highlights

*   **The Power of Streaming:** Building this pipeline highlighted the power of processing data on the fly, enabling near real-time insights.
*   **Snowflake's Ease of Integration:** The Kafka connector made sinking data into Snowflake surprisingly straightforward.
*   **Iterative Development:** The activity detection logic evolved. Don't be afraid to start simple, test, and refine.
*   **Importance of Debugging Tools:** Console outputs in Spark, Kafka consumer tools, and checking Snowflake table counts were invaluable.

This project was a fantastic learning experience. It's not a production-ready system out-of-the-box, but it provides a solid foundation and illustrates how these powerful technologies can work together.

## What's Next? (Future Enhancements)

*   More sophisticated activity detection models (perhaps using machine learning).
*   Alerting for specific activity patterns.
*   User-specific dashboards and historical analysis.
*   Deploying to a cloud environment (e.g., AWS, GCP, Azure) using Kubernetes.

## Conclusion

If you're looking to get hands-on experience with real-time data pipelines, Spark Streaming, or Snowflake, I highly recommend undertaking a similar project. Start with a simple use case, leverage available tools like the Sensor Logger app, and build iteratively. The journey from raw phone sensor pings to structured insights in a cloud data warehouse is incredibly rewarding!

---

I hope this draft is a good starting point! You can, of course, add more personal anecdotes, specific code snippets you're proud of, or dive deeper into areas you found particularly interesting. Let me know if you'd like any section expanded or modified.

**Remember to:**
*   Add a link to your GitHub repository if you plan to make it public.
*   Include some screenshots of your Grafana dashboards if possible.
*   Tailor the tone slightly for LinkedIn (perhaps a bit more concise and focused on skills learned) versus Medium (where you can be more narrative).

Good luck with your blog post!