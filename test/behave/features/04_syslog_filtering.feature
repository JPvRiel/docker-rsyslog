Feature: Filter messages

  In order to process syslog messages from multiple systems
  As a log collection service
  I want the service to be able to filter messages
    And to be able to filter early during inputs
    And to be able to filter later during outputs
    And to be able to apply filters to a particular input or output
    And to be able to apply filters globally to either all inputs or all outputs

  Background: Syslog service is available
    Given a valid rsyslog configuration
      And a server "test_syslog_server"
      And an environment variable file "test_syslog_server.env"


  @slow
  Scenario Outline: Message output can be filtered globally
    Given a file "/tmp/syslog_relay/nc.out" exists
    When sending the syslog message "<message>" in "RFC3164" format
     And searching lines for the pattern "<regex>" over "30" seconds
    Then the pattern should be found

    Examples:
      | message | regex |
      | Global test white-list filter allows all | .* Global test white-list filter allows all.* |


  @slow
  Scenario Outline: Message output can be filtered per output
    Given a file "/tmp/syslog_relay/nc.out" exists
    When sending the syslog message "<message>" in "RFC3164" format
     And searching lines for the pattern "<regex>" over "30" seconds
    Then the pattern should NOT be found

    Examples:
      | message | regex |
      | foobar test blacklist filter this message out for syslog relay | .*foobar test blacklist filter this message out for syslog relay.* |
