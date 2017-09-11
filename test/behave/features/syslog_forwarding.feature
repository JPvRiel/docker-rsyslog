Feature: Foward syslog messages

  In order to share syslog messages with other systems
  As a log collection service
  I want the service to forward messages

  Background: Syslog service is available
    Given a server "test_syslog_server"

  @skip
  Scenario: Messages are forwarded to another syslog server
    Given "rsyslog_omfwd_syslog_enabled" environment variable is "true"
      And "rsyslog_omfwd_syslog_host" environment variable is set
      And "rsyslog_omfwd_syslog_port" environment variable is set
    When sending the message "Testing syslog forwarding"
    Then the remote syslog server should have received the message within "5" seconds

  @wip
  Scenario: Messages are forwarded to kafka
    Given "rsyslog_omkafka_enabled" environment variable is "true"
      And "rsyslog_omkafka_broker" environment variable is set
      And "rsyslog_omkafka_port" environment variable is set
      And "rsyslog_omkafka_topic" environment variable is set
    When sending the message "Testing kafka forwarding"
    Then the kafka topic should have received the message within "5" seconds

  @skip
  Scenario: Messages are forwarded to logstash
    Given "rsyslog_omfwd_json_enabled" environment variable is "true"
      And "rsyslog_omfwd_json_host" environment variable is set
      And "rsyslog_omfwd_json_port" environment variable is set
    When sending the message "Testing logstash forwarding"
    Then the logstash instance should have received the message within "5" seconds
