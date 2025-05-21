from flask import Flask, request, jsonify
from utils.kafka_producer import KafkaProducer
import logging

app = Flask(__name__)
producer = KafkaProducer()

@app.route('/sensor-data', methods=['POST'])
def receive_data():
    try:
        incoming_data = request.json
        print(f"Received message ID: {incoming_data}")
        
        # Extract metadata
        metadata = {
            "messageId": incoming_data["messageId"],
            "sessionId": incoming_data["sessionId"],
            "deviceId": incoming_data["deviceId"]
        }
        
        # Process each sensor reading in the payload
        for sensor_reading in incoming_data["payload"]:
            # Create enriched message with metadata
            kafka_message = {
                **metadata,
                "sensorType": sensor_reading["name"],
                "x": sensor_reading["values"]["x"],
                "y": sensor_reading["values"]["y"],
                "z": sensor_reading["values"]["z"],
                "accuracy": sensor_reading["accuracy"],
                "timestamp": sensor_reading["time"]
            }
            
            # Send to Kafka
            producer.send_to_kafka(kafka_message)
            print(f"Sent {sensor_reading['name']} data to Kafka")
        
        return jsonify({"status": "success", "processed_readings": len(incoming_data["payload"])}), 200
    except Exception as e:
        logging.error(f"Error: {str(e)}", exc_info=True)
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)