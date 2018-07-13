import os
import time

from behave import *
from hamcrest import *

@given('a file "{log_file}" exists')
def step_impl(context, log_file):
    assert_that(os.path.isfile(log_file) or os.stat.S_ISFIFO(os.stat(log_file).st_mode), equal_to(True))
    context.log_file = log_file


@when('a file "{log_file}" exists by "{timeout}" second timeout')
def step_impl(context, log_file, timeout):
    context.log_file = None
    exists_timeout = time.time() + float(timeout)
    while not os.path.exists(log_file):
        time.sleep(1)
        if time.time() > exists_timeout:
            break
    assert_that(os.path.isfile(log_file) or os.stat.S_ISFIFO(os.stat(log_file).st_mode), equal_to(True))
    context.log_file = log_file


@when('waiting "{timeout}" seconds')
def step_impl(context, timeout):
    time.sleep(float(timeout))


@given('"{env_var}" environment variable is "{value}"')
def step_impl(context, env_var, value):
    assert_that(os.environ, has_item(env_var))
    assert_that(os.environ[env_var], equal_to(value))
    context.env[env_var] = os.environ[env_var]


@given('"{env_var}" environment variable is set')
def step_impl(context, env_var):
    assert_that(os.environ, has_item(env_var))
    context.env[env_var] = os.environ[env_var]


@given('a "{ca_file}" certificate authority file')
def step_impl(context, ca_file):
    assert_that(os.path.isfile(ca_file), equal_to(True))
    context.ca_file = ca_file


@given('a "{cert_file}" certificate file')
def step_impl(context, cert_file):
    assert_that(os.path.isfile(cert_file), equal_to(True))
    context.cert_file = cert_file


@given('a "{key_file}" private key file')
def step_impl(context, key_file):
    assert_that(os.path.isfile(key_file), equal_to(True))
    context.key_file = key_file
