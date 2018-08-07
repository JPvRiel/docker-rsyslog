Feature: rsyslog outputs message stats

  In order to understand messaging volumes processed
  As a log collection service
  I want rsyslog to output stats in an easy to parse JSON format
    And I want to be able to calculate the number of messages processed via various inputs, rule-sets and actions

  Background: Syslog service is available
    Given a valid rsyslog configuration
      And a server "test_syslog_server"
      And an environment variable file "test_syslog_server.env"
      # Implicit env var settings in default container config/Dockerfile
      #And "rsyslog_module_impstats_interval" environment variable is "60"
      #And "rsyslog_module_impstats_resetcounters" environment variable is "on"
      #And "rsyslog_module_impstats_format" environment variable is "cee"
      #And "rsyslog_impstats_ruleset" environment variable is "syslog_stats"

  @slow @wip
  Scenario Outline: JSON stats are emitted per action
    Given a protocol "TCP" and port "514"
      And "rsyslog_omfwd_json_template" environment variable is "TmplJSONRawMsg"
      And a file "/tmp/json_relay/nc.out" exists
    When searching lines for the pattern "<message_regex>" over "65" seconds
    Then the pattern should be found
      And a JSON jmespath "<jmespath>" field should match the "<json_field_regex>" pattern

    Examples:
      | message_regex | jmespath | json_field_regex |
      | .*?rsyslogd-pstats.*?_sender_stat.* | messages | [0-9]+ |
