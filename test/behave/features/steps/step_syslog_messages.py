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


@when('sending the raw message "{message}"')
def step_impl(context, message):
    context.sending_format = 'raw'
    context.message = message
    context.message_sent = None
    try:
        logging.info(
            'Sending message "{0:s}" to {1:s}:{2:d} in {3:s} format'.format(
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
            'Unable to send the message "{}" to "{}". Exception:\n{}'.format(
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
            'Cannot compile regex pattern "{}". Exception:\n{}'.format(
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
        f = open(context.log_file, encoding='utf-8', mode='r')
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
            'Unable to search "{}" file for pattern "{}". Exception:\n{}'
            ''.format(
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
            'Couldn\'t match regex pattern "{}" in file "{}"'.format(
                context.re.pattern,
                context.log_file
            )
        )
    assert_that(context.re_match, not_none())


@then('the pattern should NOT be found')
def step_impl(context):
    if context.re_match:
        logging.error(
            'Should NOT have matched regex pattern "{}" in file "{}"'.format(
                context.re.pattern,
                context.log_file
            )
        )
    assert_that(context.re_match, none())


@then('a JSON entry should contain "{json_element}"')
def step_impl(context, json_element):
    json_obj = None
    try:
        json_obj = json.loads(context.matched_line)
        json_find = json.loads(json_element)
    except Exception as e:
        logging.error(
            'Unable to load JSON element \'{}\' for line \'{}\'. Exception:\n{}'
            ''.format(
                json_element,
                context.matched_line,
                str(e)
            )
        )
        raise e
    assert_that(json_obj, not_none)
    assert_that(json_obj, has_entries(json_find))
    # hamcrest cannot handle nested dict objects, but niether does the python
    # built-in comparitor
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
            'Unable to load JSON element \'{}\' for line \'{}\'. Exception:\n{}'
            ''.format(
                json_element,
                context.matched_line,
                str(e)
            )
        )
    assert_that(json_obj, not_none)
    try:
        match = jmespath.search(path, json_obj)
    except Exception as e:
        logging.error(
            'Unable to use jmespath "{}" to search JSON object "{}. '
            'Exception:\n{}'.format(
                path,
                context.matched_line,
                str(e)
            )
        )
        raise e
    # handle cases where value may be a number or boolean, but also allow for forcing literal
    if value == "true":
        implicit_value = True
    elif value == "'true'":
        implicit_value = 'true'
    elif value == "false":
        implicit_value = False
    elif value == "'false'":
        implicit_value = 'false'
    elif value.isdecimal():
        # caution, doesn't handle negative numbers or fractions
        implicit_value = int(value)
    else:
        implicit_value = value
    assert_that(match, equal_to(implicit_value))


@then('a JSON jmespath "{path}" field should match the "{regex_within_json_field}" pattern')
def step_impl(context, path, regex_within_json_field):
    json_obj = None
    try:
        json_obj = json.loads(context.matched_line)
    except Exception as e:
        logging.error(
            'Unable to load JSON element \'{}\' for line \'{}\'. Exception:\n{}'
            ''.format(
                json_element,
                context.matched_line,
                str(e)
            )
        )
    assert_that(json_obj, not_none)
    try:
        match = jmespath.search(path, json_obj)
    except Exception as e:
        logging.error(
            'Unable to use jmespath "{}" to search JSON object "{}. '
            'Exception:\n{}'.format(
                path,
                context.matched_line,
                str(e)
            )
        )
        raise e
    assert_that(str(match), matches_regexp(regex_within_json_field))


@then('all lines in a file "{file}" should load as valid JSON')
def step_impl(context, file):
    context.all_valid_json = None
    context.log_file = file
    current_line = 0
    try:
        f = open(context.log_file, encoding='utf-8', mode='r')
        for l in f:
            current_line += 1
            if len(l) > 0:
                json.loads(l)
        f.close()
        context.all_valid_json = True
    except Exception as e:
        context.all_valid_json = False
        logging.error(
            'Unable to parse JSON "{}" file on line "{}". Exception:\n{}'
            ''.format(
                context.log_file,
                current_line,
                str(e)
            )
        )
        raise e
    assert_that(context.all_valid_json, equal_to(True))
