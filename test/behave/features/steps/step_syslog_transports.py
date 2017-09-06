import sys
import os
import socket
import ssl
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
                host,
                str(e)
            )
        )
        hostname_resolvable = False
    assert_that(hostname_resolvable, equal_to(True))
    context.server_name = server_name


@given('a protocol "{trans_proto}" and port "{port}"')
def step_impl(context, trans_proto, port):
    context.trans_proto = trans_proto
    context.port = int(port)


@when('connecting')
def step_impl(context):
    socket_ip_proto = {
        'IPv4': socket.AF_INET,
        'IPv6': socket.AF_INET6
    }
    socket_transport_proto = {
        'TCP': socket.SOCK_STREAM,
        'UDP': socket.SOCK_DGRAM
    }
    context.socket = None
    context.connected = None
    try:
        context.socket = socket.socket(
            family=socket_ip_proto['IPv4'],
            type=socket_transport_proto[context.trans_proto]
        )
        IP_RECVERR = 11  # 'IN' module no longer available in python 3
        context.socket.setsockopt(socket.IPPROTO_IP, IP_RECVERR, 1)
        context.socket.settimeout(5.0)
        context.socket.connect((context.server_name, context.port))
        if context.trans_proto == 'UDP':
            # For UDP, given it's connectionless, we have to try send some data.
            # Python will not block and will immediatly return success
            # Typically, s.recv(1024) could be used to detect ICMP port
            # unreachable, but UDP syslog servers don't send back any data, so
            # it will timeout and raise an exception
            context.socket.send(b"UDP Connection Test\n")
            context.socket.recv(1024)
        context.connected = True
    except socket.error as e:
        if isinstance(e, socket.timeout) and context.trans_proto == 'UDP':
            logging.warning(
                'UDP is connectionless and port cannot be confirmed as open. '
                'Assumed "open" given no errors occured before '
                '{:.2f}s timeout'.format(context.socket.gettimeout())
            )
            context.connected = True
        else:
            logging.error(
                "Failed to open port {0:s}/{1:d}. Exception: {2:s}".format(
                    context.trans_proto,
                    context.port,
                    str(e)
                )
            )
            context.connected = False


@then('a connection should be established')
def step_impl(context):
    assert_that(context.socket, not_none())
    assert_that(context.connected, equal_to(True))
    try:
        context.socket.close()
        context.connected = False
    except Exception as e:
        logging.error(
            "Failed to close port {0:s}/{1:d}. Exception: {2:s}".format(
                context.trans_proto,
                context.port,
                str(e)
            )
        )


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


@when('connecting with TLS')
def step_impl(context):
    # Potential confusions:
    # - a test step has context and so does a TLS connection
    # - TLS is the succesor to SSL, but libs often called ssl due to legacy
    context.socket_tls = None
    context.connected_tls = None
    try:
        tls_context = ssl.create_default_context()
            # default enables cert validation with system CA files
            # default enables hostname checking
        tls_context.load_verify_locations(context.ca_file)
        if 'key_file' in context and 'cert_file' in context:
            tls_context.load_cert_chain(
                certfile = context.cert_file,
                keyfile = context.key_file
            )
        context.socket_tls = tls_context.wrap_socket(
            socket.socket(),
            server_hostname = context.server_name
        )
        context.socket_tls.connect((context.server_name, context.port))
        context.connected_tls = True
    except Exception as e:
        if isinstance(e, ssl.CertificateError):
            logging.error(
                "Certificate error. Exception: "
                "{0:s}".format(str(e))
            )
        elif isinstance(e, ssl.SSLError):
            logging.error("SSL error. Library: {0:s}. Reason: {1:s}. "
                "Exception: {2:s}".format(
                    str(e.library),
                    str(e.reason),
                    str(e)
                )
            )
        elif isinstance(e, socket.error):
            logging.error("Failed to open connection on port {0:d}."
                "Exception: {1:s}".format(
                    context.port,
                    str(e)
                )
            )
        else:
            logging.error("Exception: {0:s}".format(str(e)))
        context.connected_tls = False


@then('a TLS session should be established')
def step_impl(context):
    assert_that(context.socket_tls, not_none())
    assert_that(context.connected_tls, equal_to(True))
    try:
        context.socket_tls.unwrap()
        context.socket_tls.close()
        context.connected_tls = False
    except Exception as e:
        logging.error(
            "Failed to close TLS connection on port {0:d}. Exception: "
            "{1:s}".format(
                context.port,
                str(e)
            )
        )
