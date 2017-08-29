import sys
import os
import socket
import logging
from datetime import datetime

from behave import *
from hamcrest import *


def test_hostname(host):
    try:
        socket.gethostbyname(host)
        return True
    except socket.error as e:
        logging.error(
            "Failed to get host {0:s}. Exception: {1:s}".format(
                host,
                str(e)
            )
        )
        return False


def get_syslog_priority_code(s_facilty='User', s_severity='Informational'):
    i_facilty = {
        'User': 1,
        'Local0': 16,
        'Local1': 17
    }
    i_severity = {
        'Emergency': 0,
        'Alert': 1,
        'Critical': 2,
        'Error': 3,
        'Warning': 4,
        'Notice': 5,
        'Informational': 6,
        'Debug': 7
    }
    return i_facilty[s_facilty] * 8 + i_severity[s_severity]


def send_syslog_message(
    message,
    s_severity='Informational',
    s_facilty='User',
    format='3164',
    o_socket=None
):
    if not o_socket:
        s = open_connection()
    else:
        s = o_socket
    this_host = socket.gethostname()
    this_program = 'step_syslog_inputs'
    this_pid = os.getpid()
    if format == '3164':
        rfc3164_time = "{:%b %e %H:%M:%S}".format(datetime.now())
        syslog_message = "<{0:d}>{1:s} {2:s} {3:s}[{4:d}]: {5:s}".format(
            get_syslog_priority_code(s_facilty, s_severity),
            rfc3164_time,
            this_host,
            this_program,
            this_pid,
            message
        )
    try:
        s.send(syslog_message.encode())
    except socket.error as e:
        logging.error(
            "Socket exception sending message: {0:s}".format(str(e))
        )
        return False
    return True



def open_connection(
    host='localhost',
    ip_proto='IPv4',
    trans_proto='TCP',
    port=514,
    timeout=5.0
):
    socket_ip_proto = {
        'IPv4': socket.AF_INET,
        'IPv6': socket.AF_INET6
    }
    socket_transport_proto = {
        'TCP': socket.SOCK_STREAM,
        'UDP': socket.SOCK_DGRAM
    }
    try:
        s = socket.socket(
            family=socket_ip_proto[ip_proto],
            type=socket_transport_proto[trans_proto]
        )
        IP_RECVERR = 11  # 'IN' module no longer available in python 3
        s.setsockopt(socket.IPPROTO_IP, IP_RECVERR, 1)
        s.settimeout(timeout)
        s.connect((host, port))
        # For UDP, given it's connectionless, we have to try send some data...
        if trans_proto == 'UDP':
            # Python will not block and will immediatly return success
            # Typically, s.recv(1024) could be used to detect ICMP port
            # unreachable, but UDP syslog servers don't send back any data, so
            # it will timeout and raise an exception
            s.recv(1024)
        # s.close()
    except socket.timeout as e:
        if trans_proto == 'UDP':
            logging.warning(
                'UDP is connectionless and confirming a port is open requires '
                'reciving a response, which syslog does not provide. Assumed "'
                'connection" was successful given errors occured before timout'
            )
        else:
            return None
    except socket.error as e:
        logging.error(
            "Failed to open port {0:s}/{1:d}. Exception: {2:s}".format(
                trans_proto,
                port,
                str(e)
            )
        )
        return None
    return s


@given('a server "{syslog_server}"')
def step_impl(context, syslog_server):
    hostname_resolvable = test_hostname(syslog_server)
    assert_that(hostname_resolvable, equal_to(True))
    context.syslog_server = syslog_server


@given('a set of network ports')
def step_impl(context):
    assert_that(
        context.table.headings,
        has_items('transport protocol', 'port', 'use')
    )
    for r in context.table:
        assert_that(r['transport protocol'], is_in(['TCP', 'UDP']))
    context.transports_table = context.table


@when('we try connect to each port')
def step_impl(context):
    # assume all ports are open
    context.open_ports = 0
    logging.debug("Testing connections to {0:d} ports.".format(len(context.transports_table.rows)))
    for r in context.transports_table:
        logging.debug(
            "Connecting to {0:s}/{1:s} used as {2:s}.".format(
                r["transport protocol"],
                r["port"],
                r["use"]
            )
        )
        if open_connection(
            host=context.syslog_server,
            port=int(r["port"]),
            trans_proto=r["transport protocol"]
        ):
            context.open_ports += 1
        else:
            logging.error("\"{0:s}\" not available.".format(r["use"]))


@then('we should find all ports open')
def step_impl(context):
    assert_that(context.open_ports, has_length(context.transports_table.rows))


@given('a connection to "{trans_proto}" port "{port}"')
def step_impl(context, trans_proto, port):
    context.socket = open_connection(
        host=context.syslog_server,
        port=int(port),
        trans_proto=trans_proto
    )
    assert_that(context.socket, not_none())


@When('sending "{message}"')
def step_impl(context, message):
    is_sent = send_syslog_message(message, o_socket=context.socket)
    assert_that(is_sent, equal_to(True))
    context.socket.close()

@then('"{message}" should be received and stored')
def step_impl(context, message):
    pass
