Feature: Accept syslog network connections for various syslog transports

  In order to collect syslog messages from multiple systems
  As a log collection service
  I want the service to allow network connections to various syslog transports: UDP, TCP, RELP and with TLS

  Background: Syslog service is available
    Given a valid rsyslog configuration
      And a server "test_syslog_server"

  # Positive testing

  Scenario Outline: Accept <transport protocol> connections on <port> for <use>
    Given a protocol "<transport protocol>" and port "<port>"
    When connecting
    Then a connection should be complete

    Examples: Insecure transports
      | transport protocol | port | use                                    |
      | UDP                | 514  | legacy UDP syslog (IANA official port) |
      | TCP                | 514  | plain TCP syslog                       |
      | TCP                | 601  | plain TCP syslog (IANA official port)  |
      | TCP                | 2514 | RELP syslog                            |

  Scenario Outline: Establish TLS sessions without client authentication
    Given a protocol "<transport protocol>" and port "<port>"
      And a "tls_x509/certs/test_ca.cert.pem" certificate authority file
    When connecting with TLS
    Then a TLS session should be complete

    Examples: Secure transports without client authentication
      | transport protocol | port | use                |
      | TCP                | 6514 | secure TCP syslog  |
      #| TCP                | 7514 | secure RELP syslog |
      # Unfortunately, RELP TLS without client authentication doesn't seem possible
      # https://github.com/rsyslog/rsyslog/issues/435

  Scenario Outline: Establish TLS sessions with client authentication
    Given a protocol "<transport protocol>" and port "<port>"
      And a "tls_x509/certs/test_ca.cert.pem" certificate authority file
      And a "tls_x509/certs/behave.cert.pem" certificate file
      And a "tls_x509/private/behave.key.pem" private key file
    When connecting with TLS
    Then a TLS session should be complete

    Examples: Secure transports with client authentication
      | transport protocol | port | use                                           |
      | TCP                | 8514 | secure RELP syslog with client authentication |

  # Negative testing: TODO, e.g. client cert wrong...
