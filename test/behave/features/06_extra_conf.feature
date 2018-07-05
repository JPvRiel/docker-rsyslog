Feature: Accommodate extra custom configuration

  In order to allow adapting to unforeseen inputs or outputs
  As a log collection service
  I want the service to be able to include custom extra configuration files
    And to be able to work independently
    And to be able to add custom inputs able to integrate with existing outputs
    And to be able to add custom outputs able to integrate with existing inputs

  Background: Syslog service is available
    Given a valid rsyslog configuration
      And a server "test_syslog_server"
      And an environment variable file "test_syslog_server.env"
      And a "tls_x509/certs/test_ca.cert.pem" certificate authority file


  @slow @wip
  Scenario: Extra independent input and outputs can be added
    When producing the kafka message "extra misc message input via kafka" to the topic "extra_syslog" at broker(s) "test_kafka:9092"
      And a file "/var/log/remote/extra_kafka_input.log" exists by "60" second timeout
      And searching lines for the pattern ".*extra misc message input via kafka.*" over "60" seconds
    Then the pattern should be found


  @slow @wip
  Scenario: Extra integrated output can be added
    Given "rsyslog_call_fwd_extra_rule" environment variable is "on"
    When sending the syslog message "testing extra integrated output" in "RFC3164" format
      And a file "/var/log/remote/all_raw.log" exists by "60" second timeout
      And searching lines for the pattern ".*testing extra integrated output.*" over "60" seconds
    Then the pattern should be found
