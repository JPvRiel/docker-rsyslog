import os
import logging
import re

from behave import *
from hamcrest import *

@given('a log "{log_file}"')
def step_impl(context, log_file):
    assert_that(os.path.isfile(log_file), equal_to(True))
    context.log_file = log_file


@when('searching log lines for the pattern "{regex}"')
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


@then('a match should be found')
def step_impl(context):
    if not context.re_match:
        logging.error(
            "Cannot match regex pattern \"{0:s}\" in file \"{1:s}\"".format(
                context.re.pattern,
                context.log_file
            )
        )
    assert_that(context.re_match, not_none())
