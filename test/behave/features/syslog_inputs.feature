Feature: Accept syslog messages on various network transports

  In order to collect syslog messages from multiple systems
  As a log collection service
  I want the service to support various syslog transports (UDP, TCP, RELP) and security (TLS)

  Background: Syslog service is available
    Given a server "localhost"

  @skip
  Scenario: Check that syslog <port> are open
    Given a set of network ports:
        | transport protocol | port | use               |
        | UDP                | 514  | legacy UDP syslog |
        | TCP                | 514  | plain TCP syslog  |
        | TCP                | 2514 | RELP syslog       |
    When we try connect to each port
    Then we should find all ports open

  @skip
  Scenario: Check that secure ports support TLS without client authentication
    Given a set of network ports:
      | transport protocol | port | use                |
      | TCP                | 6514 | secure TCP syslog  |
      | TCP                | 7514 | secure RELP syslog |
      And a trusted "certificate authority" file
    When we try connect to each port
      And we try establish a secure connection
    Then we should find all ports open
      And all ports should establish a TLS session without client authentication

  @skip
  Scenario: Check that secure ports support TLS with client authentication
    Given a set of network ports:
      | transport protocol | port | use                                                  |
      | TCP                | 8514 | secure RELP syslog with strong client authentication |
      And a trusted "certificate authority" file
      And a "private key" file and "client certificate" file
    When we try connect to each port
      And we try establish a secure connection
    Then we should find all ports open
      And all ports should establish a TLS session requesting client authentication

  @wip
  Scenario Outline: Send syslog <message> to <transport protocol> port <port>
    Given a connection to "<transport protocol>" port "<port>"
    When sending "<message>"
    Then "<message>" should be received and stored

    Examples: Messages on insecure transports
      | transport protocol | port | message           |
      | UDP                | 514  | legacy UDP syslog |
      | TCP                | 514  | plain TCP syslog  |
