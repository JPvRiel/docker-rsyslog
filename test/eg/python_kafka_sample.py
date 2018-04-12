#!/usr/bin/env python3
# Assumes a kafka broker is listening at test_kafka:9091 (PLAINTEXT) and test_kafka:9092 (SASL_SSL/PLAIN).
from kafka import KafkaProducer
from kafka import KafkaConsumer
from kafka.errors import KafkaError

insecure_producer = KafkaProducer(
        bootstrap_servers='test_kafka:9091'
    )
insecure_producer.send('test', b'Hello World!')

print("# Insecure consumer")
insecure_consumer = KafkaConsumer(
        'test',
        bootstrap_servers='test_kafka:9091',
        auto_offset_reset='earliest',
        consumer_timeout_ms=1000,
        value_deserializer=lambda m: m.decode('utf8')
    )
for kafka_message in insecure_consumer:
    print(kafka_message.value)

print("# Secure consumer")
secure_consumer = KafkaConsumer(
        'test',
        bootstrap_servers='test_kafka:9092',
        auto_offset_reset='earliest',
        consumer_timeout_ms=1000,
        value_deserializer=lambda m: m.decode('utf8'),
        security_protocol='SASL_SSL',
        sasl_mechanism='PLAIN',
        sasl_plain_username='test',
        sasl_plain_password='test-secret',
        ssl_cafile='/tmp/test_ca.cert.pem',
    )
for kafka_message in secure_consumer:
    print(kafka_message.value)
