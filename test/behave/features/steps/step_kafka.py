import ast
import time
import logging
from confluent_kafka import Producer, Consumer, KafkaError
from behave import *
from hamcrest import *


# callback function to report on delivery
def delivery_report(error, message):
    ''' Called once for each message produced to indicate delivery result.
        Triggered by poll() or flush().
    '''
    if error is not None:
        logging.error('Message delivery failed: {}'.format(error))
    else:
        logging.info(
            'Message delivered to topic \'{}\' in partition {}'.format(
                message.topic(),
                message.partition()
            )
        )
    assert_that(error, none())


@When(
    'producing the kafka message "{message}" to the topic "{topic}" at '
    'broker(s) "{broker_list}"'
)
def step_impl(context, message, topic, broker_list):
    context.broker_list = broker_list
    context.topic = topic
    context.message = message
    #context.message_sent = None
    timeout = 30
    try:
        producer = Producer(
            {
                'bootstrap.servers': broker_list,
                'batch.num.messages': 1,
                'linger.ms': 100,
                'message.timeout.ms': int(timeout) * 1000,
                'sasl.mechanisms': 'PLAIN',
                'sasl.username': 'test',
                'sasl.password': 'test-secret',
                'security.protocol': 'sasl_ssl',
                'ssl.ca.location': getattr(context, 'ca_file')
            }
        )
        producer.produce(topic, message.encode(), callback=delivery_report)
        producer.flush(timeout)
        #context.message_sent = True
    except Exception as e:
        logging.error(
            'Unable to send the message to kafka broker(s) "{}" and topic '
            '"{}". Exception:\n{}'.format(
                context.broker_list,
                context.topic,
                str(e)
            )
        )
    #assert_that(context.message_sent, equal_to(True))


@then(
    'the env configured kafka topic should have the the message within '
    '"{timeout}" seconds'
)
def step_impl(context, timeout):
    consumed_message = None
    message_found = None
    broker_list = ','.join(
        ast.literal_eval(context.env['rsyslog_omkafka_broker'])
    )
    topic = context.env['rsyslog_omkafka_topic']
    # see https://github.com/confluentinc/confluent-kafka-python/blob/master/examples/consumer.py
    try:
        consumer = Consumer(
                {
                    'bootstrap.servers': broker_list,
                    'client.id': 'python_confluent_kafka',
                    'group.id': 'test_confluent_kafka',
                    'enable.auto.commit': True,
                    'default.topic.config': {
                        'auto.offset.reset': 'earliest'
                    },
                    'batch.num.messages': 1,
                    'queue.buffering.max.ms': 100,
                    'sasl.mechanisms': 'PLAIN',
                    'sasl.username': 'test',
                    'sasl.password': 'test-secret',
                    'security.protocol': 'sasl_ssl',
                    'ssl.ca.location': getattr(context, 'ca_file')
                }
            )
        # Assume a single topic is set for rsyslog kafka config.
        # The lib expects a list of topics.
        consumer.subscribe([topic])
        logging.info('Consumer subscribed to topic {}'.format(topic))
        deadline = time.time() + float(timeout)
        polls = 0
        while time.time() < deadline:
            polls += 1
            consumed_message = consumer.poll(1.0)
            if consumed_message is None:
                continue
            elif not consumed_message.error():
                if context.message in consumed_message.value().decode():
                    message_found = consumed_message.value().decode()
                    logging.debug(
                        'Message found on partition {} at offset {} '
                        'for topic {}'.format(
                            consumed_message.partition(),
                            consumed_message.offset(),
                            consumed_message.topic(),
                        )
                    )
                    break
            else:
                if consumed_message.error().code() == KafkaError._PARTITION_EOF:
                    logging.info(
                        'End of partition {} reached at offset {} on topic '
                        '\'{}\' after {} polls, but will try again in case '
                        'produced message was delayed'.format(
                            consumed_message.partition(),
                            consumed_message.offset(),
                            consumed_message.topic(),
                            polls
                        )
                    )
                    # Don't break. Message might not have been produced yet
                    # (async behaviour), so keep polling till timeout reached
                    # or message found.
                else:
                    raise KafkaException(consumed_message.error())
    except KeyboardInterrupt:
        pass
    except Exception as e:
        logging.error(
            'Unable to search for the message on kafka broker(s) "{}" '
            'and topic "{}". Exception:\n{}'.format(
                broker_list,
                topic,
                str(e)
            )
        )
    finally:
        consumer.close()
    assert_that(message_found, contains_string(context.message))
