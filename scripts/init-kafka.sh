#!/bin/sh
set -e

echo "Waiting for Kafka to be ready..."
# Use cub tool to check Kafka status (cub is part of confluentinc/cp-kafka images)
# Or a more robust Kafka health check if needed.
# This is a simple check, might need adjustment based on your Kafka setup.
until kafka-topics --bootstrap-server kafka:29092 --list > /dev/null 2>&1; do
  echo "Kafka not ready, sleeping..."
  sleep 5
done
echo "Kafka is ready."

echo "Creating Kafka topic: processed_activity"
kafka-topics --bootstrap-server kafka:29092 --create --if-not-exists --topic processed_activity --partitions 1 --replication-factor 1
echo "Topic processed_activity creation command executed."

echo "Waiting for Kafka Connect to be ready..."
until curl -s -f http://kafka-connect:8083/connectors > /dev/null; do
  echo "Kafka Connect not ready, sleeping..."
  sleep 5
done
echo "Kafka Connect is ready."

# Define connector configurations
RAW_CONNECTOR_CONFIG_FILE="/config/snowflake-sink-raw-config.json"
PROCESSED_CONNECTOR_CONFIG_FILE="/config/snowflake-sink-processed-config.json"
RAW_CONNECTOR_NAME="snowflake-sink-raw-connector"
PROCESSED_CONNECTOR_NAME="snowflake-sink-processed-connector"

# Function to check and create connector
check_and_create_connector() {
  CONNECTOR_NAME=$1
  CONFIG_FILE=$2
  echo "Checking connector: $CONNECTOR_NAME"
  STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://kafka-connect:8083/connectors/$CONNECTOR_NAME/status)
  if [ "$STATUS_CODE" -eq 200 ]; then
    echo "Connector $CONNECTOR_NAME already exists."
  elif [ "$STATUS_CODE" -eq 404 ]; then
    echo "Connector $CONNECTOR_NAME does not exist. Creating..."
    curl -X POST -H "Content-Type: application/json" --data "@$CONFIG_FILE" http://kafka-connect:8083/connectors
    echo "\nConnector $CONNECTOR_NAME creation command sent."
    # Add a small delay to allow connector to initialize before checking status, if needed for further logic
    sleep 5 
  else
    echo "Error checking connector $CONNECTOR_NAME. HTTP Status: $STATUS_CODE"
    # Consider exiting or retrying
  fi
}

# Check and create raw connector
if [ -f "$RAW_CONNECTOR_CONFIG_FILE" ]; then
  check_and_create_connector $RAW_CONNECTOR_NAME $RAW_CONNECTOR_CONFIG_FILE
else
  echo "Raw connector config $RAW_CONNECTOR_CONFIG_FILE not found. Skipping."
fi

# Check and create processed connector
if [ -f "$PROCESSED_CONNECTOR_CONFIG_FILE" ]; then
  check_and_create_connector $PROCESSED_CONNECTOR_NAME $PROCESSED_CONNECTOR_CONFIG_FILE
else
  echo "Processed connector config $PROCESSED_CONNECTOR_CONFIG_FILE not found. Skipping."
fi

echo "Kafka initialization script finished." 