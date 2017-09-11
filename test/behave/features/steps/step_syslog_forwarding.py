import os
import logging
import re

from behave import *
from hamcrest import *


@given('"{env_var}" environment variable is "{value}"')
def step_impl(context, env_var, value):
    assert_that(os.environ, has_item(env_var))
    assert_that(os.environ[env_var], equal_to(value))
    context.env[env_var] = os.environ[env_var]


@given('"{env_var}" environment variable is set')
def step_impl(context, env_var):
    assert_that(os.environ, has_item(env_var))
    context.env[env_var] = os.environ[env_var]


@when('sending the message "{message}"')
def step_impl(context, message):
    pass


@then('the kafka topic should have received the message within "{timeout}" seconds')
def step_impl(context, timeout):
    pass
