Feature: Foward syslog messages

  In order to share syslog messages with other systems
  As a log collection service
  I want the service to forward messages

  Background: Syslog service is available
    Given a valid rsyslog configuration
      And a server "test_syslog_server"
      And an environment variable file "test_syslog_server.env"

  @slow
  Scenario: Messages are relayed to kafka
    Given "rsyslog_omkafka_enabled" environment variable is "on"
      And "rsyslog_omkafka_broker" environment variable is set
      And "rsyslog_omkafka_topic" environment variable is set
      And "rsyslog_omkafka_confParam" environment variable is set
      And a "tls_x509/certs/test_ca.cert.pem" certificate authority file
      #And a "tls_x509/certs/behave.cert.pem" certificate file
      #And a "tls_x509/private/behave.key.pem" private key file
    When sending the syslog message "Testing Kafka forwarding" in "RFC3164" format
    Then the env configured kafka topic should have the the message within "60" seconds

  @slow
  Scenario: Messages are forwarded to another server in syslog format
    Given "rsyslog_omfwd_syslog_enabled" environment variable is "on"
      And "rsyslog_omfwd_syslog_host" environment variable is set
      And "rsyslog_omfwd_syslog_port" environment variable is set
      And a file "/tmp/syslog_relay/nc.out" exists
    When sending the syslog message "Testing syslog forwarding" in "RFC3164" format
      And waiting "1" seconds
      And searching lines for the pattern "Testing syslog forwarding" over "60" seconds
    Then the pattern should be found

  @slow @root
  Scenario: Messages are forwarded to another server using UDP and spoofing the orginal source IP
    Given "rsyslog_omudpspoof_syslog_enabled" environment variable is "on"
      And "rsyslog_omudpspoof_syslog_host" environment variable is set
      And "rsyslog_omudpspoof_syslog_port" environment variable is set
      And a file "/tmp/syslog_relay_udp_spoof/nc.out" exists
    When sending the syslog message "Testing syslog UDP source spoofing" in "RFC3164" format
      And waiting "1" seconds
      And searching lines for the pattern "Testing syslog UDP source spoofing" over "60" seconds
    Then the pattern should be found

  @slow
  Scenario: Messages are forwarded to JSON format
    Given "rsyslog_omfwd_json_enabled" environment variable is "on"
      And "rsyslog_omfwd_json_host" environment variable is set
      And "rsyslog_omfwd_json_port" environment variable is set
      And a file "/tmp/json_relay/nc.out" exists
    When sending the syslog message "Testing JSON forwarding" in "RFC3164" format
      And waiting "1" seconds
      And searching lines for the pattern "Testing JSON forwarding" over "60" seconds
    Then the pattern should be found
