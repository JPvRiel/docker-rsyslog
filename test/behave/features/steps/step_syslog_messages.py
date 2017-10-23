import os
import stat
import fcntl
import time
import logging
import re
import json
import jmespath

from behave import *
from hamcrest import *


@given('a file "{log_file}"')
def step_impl(context, log_file):
    assert_that(os.path.isfile(log_file) or stat.S_ISFIFO(os.stat(log_file).st_mode), equal_to(True))
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
        raise e
    assert_that(context.message_sent, equal_to(True))


@when('searching lines for the pattern "{regex}" over "{timeout}" seconds')
def step_impl(context, regex, timeout):
    context.re_match = None
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
        raise e
    assert_that(context.re, not_none())
    search_complete = False
    try:
        time_start = time.time()
        time_end = time_start + float(timeout)
        f = open(context.log_file, 'r')
        # set non-blocking in case of reading a fifo
        #fd = f.fileno()
        #fl = fcntl.fcntl(fd, fcntl.F_GETFL)
        #fcntl.fcntl(fd, fcntl.F_SETFL, fl | os.O_NONBLOCK)
        #fl = fcntl.fcntl(fd, fcntl.F_GETFL)
        #if not fl & os.O_NONBLOCK:
        #    raise Exception('O_NONBLOCK flag not set')
        while time.time() < time_end and not search_complete:
            data = f.read()
            if len(data) != 0:
                for line in data.splitlines():
                    context.re_match = context.re.search(line)
                    if context.re_match:
                        context.matched_line = context.re_match.group(0)
                        search_complete = True
                        break
            time.sleep(0.5)
        f.close()
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
        raise e
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
            "Unable to load JSON element \"{0:s}\" on line \"{1:s}\". Exception: "
            "{2:s}".format(
                json_element,
                context.matched_line,
                str(e)
            )
        )
        raise e
    assert_that(json_obj, not_none)
    assert_that(json_obj, has_entries(json_find))
    # hamcrest cannot handle nested dict objects, but niether does the python built-in comparitor
    #json_sub_match = json_find.items() <= json_obj.items()
    #if not json_sub_match:
    #    logging.error(
    #            "Unable to match JSON element. Assertion failure:\n"
    #            "  Subset  : {0:s}\n"
    #            "  Superset: {1:s}\n"
    #            "".format(
    #                json.dumps(json_find)
    #                json.dumps(json_obj)
    #            )
    #        )
    #assert_that(json_sub_match, equal_to(True))


@then('a JSON jmespath "{path}" field should be "{value}"')
def step_impl(context, path, value):
    json_obj = None
    try:
        json_obj = json.loads(context.matched_line)
    except Exception as e:
        logging.error(
            "Unable to load JSON element \"{0:s}\" on line \"{1:s}\". Exception: "
            "{2:s}".format(
                json_element,
                context.matched_line,
                str(e)
            )
        )
    assert_that(json_obj, not_none)
    try:
        match = jmespath.search(path, json_obj)
    except:
        logging.error(
            "Unable to use jmespath \"{0:s}\" to search JSON object \"{1:s}\". Exception: "
            "{2:s}".format(
                path,
                context.matched_line,
                str(e)
            )
        )
        raise e
    # hanle cases where value may be a number or boolean
    if value == "true":
        implicit_value = True
    elif value == "false":
        implicit_value = False
    elif value.isdecimal():
        # caution, doesn't handle negative numbers or fractions
        implicit_value = int(value)
    else:
        implicit_value = value
    assert_that(match, equal_to(implicit_value))
