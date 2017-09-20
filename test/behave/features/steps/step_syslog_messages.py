import os
import logging
import re
import json

from behave import *
from hamcrest import *


@given('a file "{log_file}"')
def step_impl(context, log_file):
    assert_that(os.path.isfile(log_file), equal_to(True))
    context.log_file = log_file


@when('sending the raw message "{message}"')
def step_impl(context, message):
    context.sending_format = 'raw'
    context.message = message
    context.message_sent = None
    try:
        logging.info("Sending message \"{0:s}\" to {1:s}:{2:d} in "
            "{3:s} format".format(
                context.message,
                context.server_name,
                context.port,
                context.sending_format
            )
        )
        context.socket.send("{0:s}\n".format(message).encode('ascii'))
        context.message_sent = True
    except Exception as e:
        logging.error(
            "Unable to send the message \"{0:s}\" to \"{1:s}\". Exception: "
            "{2:s}".format(
                context.message,
                context.server_name,
                str(e)
            )
        )
        context.message_sent = False
    assert_that(context.message_sent, equal_to(True))


@when('searching lines for the pattern "{regex}"')
def step_impl(context, regex):
    try:
        context.re = re.compile(regex, re.IGNORECASE)
    except Exception as e:
        logging.error(
            "Cannot compile regex pattern \"{0:s}\". Exception: {1:s}".format(
                regex,
                str(e)
            )
        )
        context.re = None
    assert_that(context.re, not_none())
    search_complete = None
    try:
        with open(context.log_file, 'r') as f:
            for line in f:
                context.re_match = context.re.search(line)
                if context.re_match:
                    context.matched_line = context.re_match.group(0)
                    break
        search_complete = True
    except Exception as e:
        logging.error(
            "Unable to search \"{0:s}\" file for pattern \"{1:s}\". Exception: "
            "{2:s}".format(
                context.log_file,
                context.re.pattern,
                str(e)
            )
        )
        search_complete = False
    assert_that(search_complete, equal_to(True))


@then('the pattern should be found')
def step_impl(context):
    if not context.re_match:
        logging.error(
            "Cannot match regex pattern \"{0:s}\" in file \"{1:s}\"".format(
                context.re.pattern,
                context.log_file
            )
        )
    assert_that(context.re_match, not_none())


@then('a JSON entry should contain "{json_element}"')
def step_impl(context, json_element):
    json_obj = None
    try:
        json_obj = json.loads(context.matched_line)
        json_find = json.loads(json_element)
    except Exception as e:
        logging.error(
            "Unable to match JSON element \"{0:s}\" on line \"{1:s}\". Exception: "
            "{2:s}".format(
                json_element,
                context.matched_line,
                str(e)
            )
        )
    assert_that(json_obj, not_none)
    assert_that(json_obj, has_entries(json_find))


@then('a JSON field "{field}" should be "{value}"')
def step_impl(context, field, value):
    json_obj = None
    try:
        json_obj = json.loads(context.matched_line)
    except Exception as e:
        logging.error(
            "Unable to match JSON field \"{0:s}\" and value \"{1:s}\" on line \"{2:s}\". Exception: "
            "{3:s}".format(
                field,
                value,
                context.matched_line,
                str(e)
            )
        )
    assert_that(json_obj, not_none)
    assert_that(json_obj, has_entry(field, value))
