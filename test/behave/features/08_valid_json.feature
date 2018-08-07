Feature: JSON templates produce valid JSON objects

  Background: Syslog service is available
    Given a valid rsyslog configuration
      And a server "test_syslog_server"
      And an environment variable file "test_syslog_server.env"

  @slow @wip
  Scenario: All events forwarded via a JSON template should be valid JSON
    Given "rsyslog_omfwd_json_enabled" environment variable is "on"
      And "rsyslog_omfwd_json_host" environment variable is set
      And "rsyslog_omfwd_json_port" environment variable is set
      And a file "/tmp/json_relay/nc.out" exists
    When waiting "60" seconds
    Then all lines in a file "/tmp/json_relay/nc.out" should load as valid JSON
