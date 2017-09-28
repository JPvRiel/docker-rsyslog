Feature: Foward syslog messages

  In order to share syslog messages with other systems
  As a log collection service
  I want the service to forward messages

  Background: Syslog service is available
    Given a valid rsyslog configuration
      And a server "test_syslog_server"
      And an environment variable file "test_syslog_server.env"

  Scenario: Messages are relayed to kafka
    Given "rsyslog_omkafka_enabled" environment variable is "on"
      And "rsyslog_omkafka_broker" environment variable is set
      And "rsyslog_omkafka_topic" environment variable is set
    When sending the syslog message "Testing Kafka forwarding" in "RFC3164" format
    Then the kafka topic should have the the message within "30" seconds

  Scenario: Messages are forwarded to another server in syslog format
    Given "rsyslog_omfwd_syslog_enabled" environment variable is "on"
      And "rsyslog_omfwd_syslog_host" environment variable is set
      And "rsyslog_omfwd_syslog_port" environment variable is set
      And a file "/tmp/syslog_relay/nc.out"
    When sending the syslog message "Testing syslog forwarding" in "RFC3164" format
      And waiting "1" seconds
      And searching lines for the pattern "Testing syslog forwarding" over "5" seconds
    Then the pattern should be found

  @wip
  Scenario: Messages are forwarded to JSON format
    Given "rsyslog_omfwd_json_enabled" environment variable is "on"
      And "rsyslog_omfwd_json_host" environment variable is set
      And "rsyslog_omfwd_json_port" environment variable is set
      And a file "/tmp/json_relay/nc.out"
    When sending the syslog message "Testing JSON forwarding" in "RFC3164" format
      And waiting "1" seconds
      And searching lines for the pattern "Testing JSON forwarding" over "5" seconds
    Then the pattern should be found
