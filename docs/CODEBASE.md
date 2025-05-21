# Project Files

## ACTIVITY-TRACKER/flaskserver/app.py
```python
from flask import Flask, request, jsonify
from utils.kafka_producer import KafkaProducer
import logging

app = Flask(__name__)
producer = KafkaProducer()

@app.route('/sensor-data', methods=['POST'])
def receive_data():
    try:
        sensor_data = request.json
        print(f"Received data: {sensor_data}")
        
        # Send to Kafka
        producer.send_to_kafka(sensor_data)
        
        return jsonify({"status": "success"}), 200
    except Exception as e:
        logging.error(f"Error: {e}")
        return jsonify({"status": "error"}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

## ACTIVITY-TRACKER/flaskserver/utils/kafka_producer.py
```python
from confluent_kafka import Producer
import json
import hashlib

with open('flaskserver/config/kafka_config.json') as f:
    kafka_config = json.load(f)

class KafkaProducer:
    def __init__(self):
        self.producer = Producer(kafka_config)
        self.topic = "raw_sensor_data"

    def delivery_report(self, err, msg):
        if err:
            print(f'Message delivery failed: {err}')
        else:
            print(f'Message delivered to {msg.topic()} [{msg.partition()}]')

    def _generate_key(self, data: dict) -> str:
        """
        Generate a SHA-1 hash key from message_id, session_id, and device_id.
        """
        try:
            # Extract required fields
            messageId = data['messageId']
            sessionId = data['sessionId']
            deviceId = data['deviceId']
            
            # Combine fields into a single string
            combined = f"{messageId}-{sessionId}-{deviceId}"
            
            # Generate SHA-1 hash
            return hashlib.sha1(combined.encode()).hexdigest()
            
        except KeyError as e:
            print(f"Missing field for key generation: {e}. Using fallback key.")
            return "fallback_key"

    def send_to_kafka(self, data):
        try:
            # Generate the key
            key = self._generate_key(data)
            
            self.producer.produce(
                self.topic,
                key=key,
                value=json.dumps(data),
                callback=self.delivery_report
            )
            self.producer.poll(0)
        except Exception as e:
            print(f"Error sending to Kafka: {e}")
```

## ACTIVITY-TRACKER/docker-compose.yml
```yaml
version: '3'

services:
  # Kafka Ecosystem
  zookeeper:
    image: confluentinc/cp-zookeeper:7.4.0
    ports:
      - "2181:2181"
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181

  kafka:
    image: confluentinc/cp-kafka:7.4.0
    depends_on:
      - zookeeper
    ports:
      - "9092:9092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:29092,PLAINTEXT_HOST://localhost:9092
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1

  kafka-connect:
    image: confluentinc/cp-kafka-connect:7.4.0
    depends_on:
      - kafka
    ports:
      - "8083:8083"
    environment:
      CONNECT_BOOTSTRAP_SERVERS: kafka:29092
      CONNECT_REST_ADVERTISED_HOST_NAME: kafka-connect
      CONNECT_GROUP_ID: compose-connect-group
      CONNECT_CONFIG_STORAGE_TOPIC: docker-connect-configs
      CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_OFFSET_STORAGE_TOPIC: docker-connect-offsets
      CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_STATUS_STORAGE_TOPIC: docker-connect-status
      CONNECT_STATUS_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_KEY_CONVERTER: org.apache.kafka.connect.storage.StringConverter
      CONNECT_VALUE_CONVERTER: org.apache.kafka.connect.json.JsonConverter
      CONNECT_PLUGIN_PATH: "/usr/share/java,/usr/share/confluent-hub-components"
    # Install JDBC connector for Postgres
    command: 
      - bash 
      - -c 
      - |
        confluent-hub install --no-prompt confluentinc/kafka-connect-jdbc:10.7.0 &&
        /etc/confluent/docker/run

  # Kafka Console (UI)
  kafka-ui:
    image: provectuslabs/kafka-ui:latest
    depends_on:
      - kafka
    ports:
      - "8080:8080"
    environment:
      KAFKA_CLUSTERS_0_NAME: local
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka:29092
      KAFKA_CLUSTERS_0_ZOOKEEPER: zookeeper:2181

  # Database
  postgres:
    image: timescale/timescaledb:latest-pg14
    ports:
      - "5432:5432"
    environment:
      POSTGRES_DB: sensordb
      POSTGRES_USER: sensoruser
      POSTGRES_PASSWORD: sensorpass
    volumes:
      - postgres-data:/var/lib/postgresql/data

  # Visualization
  grafana:
    image: grafana/grafana:latest
    depends_on:
      - postgres
    ports:
      - "3000:3000"
    volumes:
      - grafana-data:/var/lib/grafana

volumes:
  postgres-data:
  grafana-data:
```

## ACTIVITY-TRACKER/flaskserver/app.py
```python
from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.types import *

spark = SparkSession.builder \
    .appName("ActivityDetection") \
    .config("spark.jars.packages", "org.apache.spark:spark-sql-kafka-0-10_2.12:3.3.0") \
    .getOrCreate()

# Schema (updated)
schema = StructType([
    StructField("messageId", LongType()),
    StructField("sessionId", StringType()),
    StructField("deviceId", StringType()),
    StructField("sensorType", StringType()),
    StructField("x", DoubleType()),
    StructField("y", DoubleType()),
    StructField("z", DoubleType()),
    StructField("accuracy", IntegerType()),
    StructField("timestamp", LongType())
])

df = spark.readStream \
    .format("kafka") \
    .option("kafka.bootstrap.servers", "kafka:29092") \
    .option("subscribe", "raw_sensor_data") \
    .load()

# Parse with timestamp casting
parsed_df = df.select(
    from_json(col("value").cast("string"), schema).alias("data")
).select(
    col("data.messageId"),
    col("data.sensorType"),
    col("data.x"),
    col("data.y"),
    col("data.z"),
    from_unixtime(col("data.timestamp") / 1e9).cast(TimestampType()).alias("timestamp")
).filter(
    col("sensorType") == "accelerometer"
)

# Magnitude calculation
magnitude_df = parsed_df.withColumn(
    "magnitude", 
    sqrt(col("x")**2 + col("y")**2 + col("z")**2)
)

# Simplified windowing (for testing)
windowed_df = magnitude_df.groupBy(
    window(current_timestamp(), "5 seconds", "1 second")
).agg(
    avg("magnitude").alias("avg_magnitude")
)

# Classification
activity_df = windowed_df.withColumn(
    "activity",
    when(col("avg_magnitude") < 1.1, "stationary")
    .otherwise("running")
).withColumn("confidence", lit(0.85)) \
 .select(
    col("window.end").alias("timestamp"),
    col("activity"),
    col("confidence")
)

# Debug to console
debug_query = activity_df.writeStream \
    .format("console") \
    .outputMode("append") \
    .start()

# Write to Kafka
query = activity_df.select(
    to_json(struct("timestamp", "activity", "confidence")).alias("value")
).writeStream \
    .format("kafka") \
    .option("kafka.bootstrap.servers", "kafka:29092") \
    .option("topic", "processed_activity") \
    .option("checkpointLocation", "/tmp/checkpoint") \
    .outputMode("append") \
    .start()

query.awaitTermination()
```
