

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
    if format == None:
        syslog_message = message
        # According so RFC3164, one can send a plain message without any
        #headers, etc
    elif format == '3164':
        syslog_message = format_3164_message(message)
    elif format == '5424':
        syslog_message = format_5424_message(message)
    try:
        s.send(syslog_message.encode())
    except socket.error as e:
        logging.error(
            "Socket exception sending message: {0:s}".format(str(e))
        )
        return False
    return True


@When('sending "{message}"')
def step_impl(context, message):
    is_sent = send_syslog_message(message, o_socket=context.socket)
    assert_that(is_sent, equal_to(True))
    context.socket.close()

@then('"{message}" should be received and stored')
def step_impl(context, message):
    pass
