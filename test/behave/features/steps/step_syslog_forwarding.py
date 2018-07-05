import socket
import logging
import logging.handlers

from behave import *
from hamcrest import *


@when('sending the syslog message "{message}" in "{sending_format}" format')
def step_impl(context, message, sending_format):
    context.sending_format = sending_format
    context.message = message
    context.message_sent = None
    try:
        logging.info("Sending message \"{0:s}\" to {1:s}:{2:d} in "
            "{3:s} format".format(
                context.message,
                context.server_name,
                logging.handlers.SYSLOG_TCP_PORT,
                context.sending_format
            )
        )
        syslogger = logging.getLogger('syslog')
        syslogger.setLevel(logging.DEBUG)
        syslog_handler = logging.handlers.SysLogHandler(
            address=(
                context.server_name,
                logging.handlers.SYSLOG_TCP_PORT
            ),
            facility=logging.handlers.SysLogHandler.LOG_USER,
            socktype=socket.SOCK_STREAM,
        )
        syslog_handler.append_nul=False
        # Note SysLogHandler TCP doesnt do "Octet-counting" and needs a
        # newline added for "Non-Transparent-Framing". See RFC6587.
        syslog_3164_formatter = logging.Formatter(
            "%(asctime)s behave %(processName)s[%(process)d]: "
            "%(module)s.%(funcName)s: %(message)s\n",
            datefmt='%b %d %H:%M:%S'
            )
        if (sending_format == 'RFC3164'):
            syslog_handler.setFormatter(syslog_3164_formatter)
        elif (sending_format == 'RFC5424'):
            raise NotImplementedError(
                'syslog_handler can\'t yet output RFC5424 format'
            )
        else:
            raise ValueError('Unkown format requested')
        syslogger.addHandler(syslog_handler)
        syslogger.info(message)
        context.message_sent = True
    except Exception as e:
        logging.error(
            'Unable to send the message "{}" to "{}". Exception:\n{}'.format(
                context.message,
                context.server_name,
                str(e)
            )
        )
        context.message_sent = False
    assert_that(context.message_sent, equal_to(True))
