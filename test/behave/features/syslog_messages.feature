Feature: Accept syslog messages in various formats

  In order to process syslog messages from multiple systems
  As a log collection service
  I want the service to handle formats according RFC3164 and RFC5424
    And I want filter out badly formatted messages that fail to meet syslog conventions

  Background: Syslog service is available
    Given a server "test_syslog_server"

  @wip
  Scenario Outline: Messages are received from syslog clients
    Given a log "<file>"
    When searching log lines for the pattern "<regex>"
    Then a match should be found

    Examples:
      | file                                                                       | regex                                   |
      | /var/log/remote/relp/rfc5424/test_syslog_client_centos7/messages           | CentOS Linux 7.* was running rsyslogd.* |
      | /var/log/remote/relp_secure/rfc5424/test_syslog_client_ubuntu1604/messages | Ubuntu 16\.04.* was running rsyslogd.*  |

  # TODO
  # - Positive testing with RFC3164 and RFC5424 well formed message samples
  # - Negative testing with RFC3164 and RFC5424 malformed message samples
