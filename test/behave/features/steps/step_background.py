import os
import socket
import logging

from behave import *
from hamcrest import *


@given('a server "{server_name}"')
def step_impl(context, server_name):
    try:
        socket.gethostbyname(server_name)
        hostname_resolvable = True
    except socket.error as e:
        logging.error(
            "Failed to get host {0:s}. Exception: {1:s}".format(
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
