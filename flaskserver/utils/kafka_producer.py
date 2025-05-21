from confluent_kafka import Producer
# from config.kafka import CONFLUENT_CONFIG
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
            # Combine fields into a single string
            combined = f"{data['timestamp']}-{data['sensorType']}"
            
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