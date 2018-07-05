Feature: Accept syslog messages in various formats

  In order to process syslog messages from multiple systems
  As a log collection service
  I want the service to handle valid formats according RFC3164 and RFC5424
    And I want poorly formatted messages that fail to meet syslog conventions to have null fields

  Background: Syslog service is available
    Given a valid rsyslog configuration
      And a server "test_syslog_server"
      And an environment variable file "test_syslog_server.env"

  @slow
  Scenario Outline: Messages are received from syslog clients
    Given a file "<file>" exists
    When searching lines for the pattern "<regex>" over "30" seconds
    Then the pattern should be found

    Examples:
      | file | regex |
      | /var/log/remote/test_syslog_client_centos7 | CentOS Linux 7.* was running rsyslogd.* |
      | /var/log/remote/test_syslog_client_ubuntu1604 | Ubuntu 16\.04.* was running rsyslogd.* |

  # - Positive testing well formed message samples

  @slow
  Scenario Outline: Well formed messages mapped into JSON fields
  Given a protocol "TCP" and port "514"
    And "rsyslog_omfwd_json_template" environment variable is "TmplJSONRawMeta"
    And a file "/tmp/json_relay/nc.out" exists
  When connecting
    And sending the raw message "<message>"
    And waiting "1" seconds
    And searching lines for the pattern "<regex>" over "30" seconds
  Then a connection should be complete
    And the pattern should be found
    And a JSON entry should contain "<json>"

  Examples:
    | message | regex | json |
    | <14>Sep 19 23:43:29 behave test[99999]: Well formed RFC3164 with PID | .*?Well formed RFC3164 with PID.* | { "hostname": "behave", "app-name": "test", "procid" : "99999" } |
    | <14>Sep 19 23:43:29 behave test: Well formed RFC3164 without PID | .*?Well formed RFC3164 without PID.* | { "hostname": "behave", "app-name": "test", "procid" : "-" } |
    | <14>Sep 19 23:43:29 behave Well formed RFC3164 without application name  | .*?Well formed RFC3164 without application name.* | { "hostname": "behave", "app-name": "-" } |
    | <14>1 2017-09-19T23:43:29+00:00 behave test 99999 - Well formed RFC5424 with PID | .*Well formed RFC5424 with PID.* | { "hostname": "behave", "app-name": "test", "procid" : "99999" } |
    | <14>1 2017-09-19T23:43:29+00:00 behave test - - [test@16543 key1="value1" key2="value2"] Well formed RFC5424 with structured data | .*Well formed RFC5424 with structured data.* | { "structured-data": { "test@16543": { "key1": "value1", "key2": "value2" } } } |


  @slow
  Scenario Outline: Parser chain should compensate for common non-standard messages
  Given a protocol "TCP" and port "514"
    And "rsyslog_omfwd_json_template" environment variable is "TmplJSONRawMeta"
    And "rsyslog_parser" environment variable is "["rsyslog.rfc5424", "rsyslog.aixforwardedfrom", "custom.rfc3164"]"
    And a file "/tmp/json_relay/nc.out" exists
  When connecting
    And sending the raw message "<message>"
    And waiting "1" seconds
    And searching lines for the pattern "<regex>" over "30" seconds
  Then a connection should be complete
    And the pattern should be found
    And a JSON entry should contain "<json>"

  Examples:
    | message | regex | json |
    | <38>Sep 19 23:43:29 Message forwarded from claimedhostname: procnamewithoutid: AIX extraneous forwarded from message without process ID | .*?AIX extraneous forwarded from message without process ID.* | { "hostname": "claimedhostname", "app-name": "procnamewithoutid", "procid" : "-" } |
    | <38>Sep 19 23:43:29 Message forwarded from claimedhostname: procnamewithid[99]: AIX extraneous forwarded from message with process ID | .*?AIX extraneous forwarded from message with process ID.* | { "hostname": "claimedhostname", "app-name": "procnamewithid", "procid" : "99" } |


  # - Negative testing with RFC3164 "malformed" message samples

  @slow
  Scenario Outline: Malformed RFC3164 messages do not create bogus field values
    Given a protocol "TCP" and port "514"
      And "rsyslog_omfwd_json_template" environment variable is "TmplJSONRawMeta"
      And a file "/tmp/json_relay/nc.out" exists
    When connecting
      And sending the raw message "<message>"
      And waiting "1" seconds
      And searching lines for the pattern "<regex>" over "30" seconds
    Then a connection should be complete
      And the pattern should be found
      And a JSON jmespath "<path>" field should be "<value>"

  Examples:
    | message | regex | path  | value |
    | Sep 19 23:43:29 lies Poor form RFC3164 with no priority | .*?RFC3164 with no priority.* | hostname | lies |
    | <17>Poor form RFC3164 with no syslog header - avoid bogus hostname  | .*?RFC3164 with no syslog header.* | "syslog-relay"."header-valid" | false |
    | Poor form RFC3164 with no syslog header or priority - avoid bogus hostname  | .*?RFC3164 with no syslog header or priority.* | "syslog-relay"."pri-valid" | false |
