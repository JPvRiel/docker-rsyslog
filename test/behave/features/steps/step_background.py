import os
import time
import socket
import logging

from behave import *
from hamcrest import *


@given('a valid rsyslog configuration')
# Note:
# - no neat/simple way to observe output from other containers with sut
# - work-arround is a shared volume and extra container just to check config
# - hardcoded and dependant on 'test_syslog_server_config' service running once
# - see ../docker-compose.test.yml
def step_impl(context):
    rsyslog_config_text_exit_code = None
    with open('/tmp/config_check/rsyslog_n1_exit_code.txt', 'r') as f_exit:
        rsyslog_config_text_exit_code = f_exit.read().rstrip('\n')
    if (rsyslog_config_text_exit_code != '0'):
        with open('/tmp/config_check/rsyslog_n1_output.txt', 'r') as f_output:
            logging.error(
                "rsyslog configuration invalid. Output:\n{0:s}".format(
                    f_output.read()
                )
            )
    assert_that(rsyslog_config_text_exit_code, equal_to('0'))


@given('a server "{server_name}"')
def step_impl(context, server_name):
    try:
        socket.gethostbyname(server_name)
        hostname_resolvable = True
    except socket.error as e:
        logging.error(
            'Failed to get host {}. Exception:\n{}'.format(
                server_name,
                str(e)
            )
        )
        hostname_resolvable = False
    assert_that(hostname_resolvable, equal_to(True))
    context.server_name = server_name


@given('an environment variable file "{env_file}"')
def step_impl(context, env_file):
    assert_that(os.path.isfile(env_file), equal_to(True))
    context.env_file = env_file
