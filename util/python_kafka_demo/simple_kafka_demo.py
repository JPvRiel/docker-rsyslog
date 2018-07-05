#!/usr/bin/env python3

# Demo for 2 kafka python modules, kafka-python (native python) and confluent-kafka (wraps librdkafka)
# See http://matthewrocklin.com/blog/work/2017/10/10/kafka-python
# Assumes a kafka server at localhost
# E.g.
# git clone https://github.com/confluentinc/cp-docker-images
# cd examples/kafka-single-node
# docker-compose up -d
# docker-compose exec kafka kafka-topics --create --topic test --partitions 1 --replication-factor 1 --if-not-exists --zookeeper localhost:2181

import time

# demo settings
demo_kafka_python = True
demo_confluent_kafka = True
topic = 'test'
timeout = 30


if demo_kafka_python:

    from kafka import KafkaProducer, KafkaConsumer
    from kafka.errors import KafkaError

    print("\nDemo for kafka-python\n")
    broker_list = ['localhost:9092']
    message = 'hello world from kafka-python (pure python)'

    # produce a message
    print('Producing "{}" on topic \'{}\''.format(message, topic))
    try:
        producer = KafkaProducer(
            bootstrap_servers=broker_list,
            batch_size=1,
            linger_ms=100,
            #sasl_mechanism='PLAIN',
            #sasl_plain_username='test',
            #sasl_plain_password='test-secret',
            #security_protocol='SASL_SSL',
            #ssl_cafile=getattr(context, 'ca_file')
        )
        future = producer.send(topic, message.encode())
        record_metadata = future.get(timeout=timeout)
        print('Message produced. Metadata:')
        print(record_metadata)
    except Exception as e:
        print(
            'Unable to send the message to kafka broker(s) \'{}\' '
            'and topic \'{}\'. Exception: {}'.format(
                broker_list,
                topic,
                str(e)
            )
        )

    time.sleep(1)

    # consume a message
    print('Consuming on topic \'{}\''.format(topic))
    message_found = None
    try:
        # use kafka.consumer (but always re-read all messages to try match)
        consumer = KafkaConsumer(
            topic,
            bootstrap_servers=broker_list,
            group_id='test_kafka_python',
            auto_offset_reset='smallest',
            enable_auto_commit=True,
            consumer_timeout_ms=int(timeout) * 1000,
            #sasl_mechanism='PLAIN',
            #sasl_plain_username='test',
            #sasl_plain_password='test-secret',
            #security_protocol='SASL_SSL',
            #ssl_cafile=getattr(context, 'ca_file')
        )
        # Read and print all messages from test topic
        message_found = False
        for consumed_message in consumer:
            if message in consumed_message.value.decode():
                message_found = True
                break
    except Exception as e:
        print(
            'Unable to search for the message on kafka broker(s) \'{}\' '
            'and topic \'{}\'. Exception: {}'.format(
                broker_list,
                topic,
                str(e)
            )
        )
    if message_found:
        print('Found "{}" in topic \'{}\''.format(message, topic))


if demo_confluent_kafka:

    from confluent_kafka import Producer, Consumer, KafkaError

    print("\nDemo for confluent-kafka\n")
    broker_list = 'localhost'
    message = 'hello world from confluent-kafka (librdkafka wrapper)'

    # callback function to report on delivery
    def delivery_report(err, msg):
        ''' Called once for each message produced to indicate delivery result.
            Triggered by poll() or flush(). '''
        if err is not None:
            print('Message delivery failed: {}'.format(err))
        else:
            print('Message delivered to topic \'{}\' in partition {}'.format(
                    msg.topic(),
                    msg.partition()
                )
            )

    # produce a message
    print('Producing "{}" on topic \'{}\''.format(message, topic))
    p = Producer(
        {
            'bootstrap.servers': broker_list,
            'batch.num.messages': 1,
            'linger.ms': 100,
            'message.timeout.ms': int(timeout) * 1000
        }
    )
    for m in [message]:
        # Trigger any available delivery report callbacks from previous
        # produce() calls
        p.poll(0.0)
        # Asynchronously produce a message, the delivery report callback
        # will be triggered from poll() above, or flush() below, when the
        # message has been successfully delivered or failed permanently.
        p.produce(topic, m.encode(), callback=delivery_report)
    # Wait for any outstanding messages to be delivered and delivery report
    # callbacks to be triggered.
    p.flush(timeout)

    time.sleep(1)

    # consume a message
    print('Consuming on topic \'{}\''.format(topic))
    message_found = None
    c = Consumer(
        {
            'bootstrap.servers': broker_list,
            'client.id': 'confluent_kafka',
            'group.id': 'test_confluent_kafka',
            'enable.auto.commit': True,
            'default.topic.config': {
                'auto.offset.reset': 'smallest'
            }
        }
    )
    c.subscribe([topic])
    deadline = time.time() + timeout
    polls = 0
    while time.time() < deadline:
        # poll every second to consume messages
        polls += 1
        consumed_message = c.poll(1.0)
        if consumed_message is None:
            print('No messages consumed after {} polls'.format(polls))
        elif not consumed_message.error():
            print('Received message: {}'.format(
                    consumed_message.value().decode()
                )
            )
            if message in consumed_message.value().decode():
                message_found = True
        else:
            if consumed_message.error().code() == KafkaError._PARTITION_EOF:
                print('End of partition {} reached on topic \'{}\' after {} polls'.format(
                        consumed_message.partition(),
                        consumed_message.topic(),
                        polls
                    )
                )
                break
            else:
                print('Error occured: {0}'.format(
                        consumed_message.error().str()
                    )
                )
                break
    c.close()
    if message_found:
        print('Found "{}" in topic \'{}\''.format(message, topic))
