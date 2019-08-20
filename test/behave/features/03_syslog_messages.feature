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
    When searching lines for the pattern "<regex>" over "60" seconds
    Then the pattern should be found

    Examples:
      | file | regex |
      | /var/log/remote/test_syslog_client_centos7 | CentOS Linux 7.* was running rsyslogd.* |
      | /var/log/remote/test_syslog_client_ubuntu1604 | Ubuntu 16\.04.* was running rsyslogd.* |


  # - Positive testing well formed message samples

  @slow
  Scenario Outline: Well formed messages mapped into JSON fields
    Given a protocol "TCP" and port "514"
      And "rsyslog_omfwd_json_template" environment variable is "TmplJSONRawMsg"
      And a file "/tmp/json_relay/nc.out" exists
    When connecting
      And sending the raw message "<message>"
      And waiting "1" seconds
      And searching lines for the pattern "<regex>" over "60" seconds
    Then a connection should be complete
      And the pattern should be found
      And a JSON entry should contain "<json>"

    Examples:
      | message | regex | json |
      | <14>Sep 19 23:43:29 behave test[99999]: Well formed RFC3164 with PID | .*?Well formed RFC3164 with PID.* | { "hostname": "behave", "app-name": "test", "procid" : "99999" } |
      | <14>Sep 19 23:43:29 behave test: Well formed RFC3164 without PID | .*?Well formed RFC3164 without PID.* | { "hostname": "behave", "app-name": "test", "procid" : "-" } |
      | <14>Sep 19 23:43:29 behave Well formed RFC3164 without application name  | .*?Well formed RFC3164 without application name.* | { "hostname": "behave", "app-name": "-" } |
      | <14>1 2017-09-19T23:43:29+00:00 behave test 99999 - - Well formed RFC5424 with PID | .*Well formed RFC5424 with PID.* | { "hostname": "behave", "app-name": "test", "procid" : "99999" } |
      | <14>1 2017-09-21T23:43:29.402+02:00 behave hub.docker.com/proj/image:0.1.0/container_name/4b6045272e31 - - - test tag "{{.ImageName}}/{{.Name}}/{{.ID}}" docker engine example | .*test tag.*docker engine example.* | { "app-name": "hub.docker.com/proj/image:0.1.0/container_name/4b6045272e31" } |
      | <14>1 2017-09-19T23:43:29+00:00 behave test 99999 - [test@16543 key1="value1" key2="value2"] Well formed RFC5424 with structured data | .*Well formed RFC5424 with structured data.* | { "rfc5424-sd": { "test@16543": { "key1": "value1", "key2": "value2" } } } |


  @slow
    Scenario Outline: Parse JSON messages when they occur
    Given a protocol "TCP" and port "514"
      And "rsyslog_omfwd_json_template" environment variable is "TmplJSONRawMsg"
      And a file "/tmp/json_relay/nc.out" exists
    When connecting
      And sending the raw message "<message>"
      And waiting "1" seconds
      And searching lines for the pattern "<regex>" over "60" seconds
    Then a connection should be complete
      And the pattern should be found
      And a JSON entry should contain "<json>"

    Examples:
      | message | regex | json |
      | @cee: { "json": "1 JSON with cee cookie and no syslog header"} | .*?@cee:.*?1 JSON with cee cookie and no syslog header.* | { "json": "1 JSON with cee cookie and no syslog header" } |
      | { "json": "2 plain JSON with no syslog header" } | .*?2 plain JSON with no syslog header.* | { "json": "2 plain JSON with no syslog header" } |
      | <14>Sep 19 23:43:29 behave test[4]: @cee: { "json": "4 Well formed RFC3164 which is a JSON message" } | .*?@cee:.*?4 Well formed RFC3164 which is a JSON message.* | { "json": "4 Well formed RFC3164 which is a JSON message" } |
      | <14>1 2017-09-19T23:43:29+00:00 behave test 6 - - @cee: { "json": "6 Well formed RFC5424 without structured data followed by a JSON message with a cee cookie" } | .*?@cee:.*?6 Well formed RFC5424 without structured data followed by a JSON message with a cee cookie.* | { "json": "6 Well formed RFC5424 without structured data followed by a JSON message with a cee cookie" } |
      | <14>1 2017-09-19T23:43:29+00:00 behave test 7 - - { "json": "7 Well formed RFC5424 without structured data followed by a JSON message without a cee cookie" } | .*?7 Well formed RFC5424 without structured data followed by a JSON message without a cee cookie.* | { "json": "7 Well formed RFC5424 without structured data followed by a JSON message without a cee cookie" } |
      | <14>1 2017-09-19T23:43:29+00:00 behave test 8 - - { "json": { "nested": "8 Well formed RFC5424 without structured data followed by a nested JSON message without a cee cookie" } } | .*?8 Well formed RFC5424 without structured data followed by a nested JSON message without a cee cookie.* | { "json": { "nested": "8 Well formed RFC5424 without structured data followed by a nested JSON message without a cee cookie" } } |
      | <14>1 2017-09-19T23:43:29+00:00 behave @cee 9 - - { "json": "9 Well formed RFC5424 without structured data followed by a JSON message with a cee cookie as the process name" } | .*?@cee.*?9 Well formed RFC5424 without structured data followed by a JSON message with a cee cookie as the process name.* | { "json": "9 Well formed RFC5424 without structured data followed by a JSON message with a cee cookie as the process name" } |
      | <14>1 2017-09-19T23:43:29+00:00 behave test 10 - [test@16543 random="some value"] @cee: { "json": "10 Well formed RFC5424 with structured data followed by a JSON message with cee cookie" } | .*?@cee:.*?10 Well formed RFC5424 with structured data followed by a JSON message with cee cookie.* | { "json": "10 Well formed RFC5424 with structured data followed by a JSON message with cee cookie" } |
      | <14>1 2017-09-19T23:43:29+00:00 behave test 11 - [test@16543 random="some other value"] { "json": "11 Well formed RFC5424 with structured data followed by a JSON message without cee cookie" } | .*?11 Well formed RFC5424 with structured data followed by a JSON message without cee cookie.* | { "json": "11 Well formed RFC5424 with structured data followed by a JSON message without cee cookie" } |


  @slow
  Scenario Outline: Parser chain should compensate for common non-standard messages
    Given a protocol "TCP" and port "514"
      And "rsyslog_omfwd_json_template" environment variable is "TmplJSONRawMsg"
      And "rsyslog_parser" environment variable is "["rsyslog.rfc5424", "rsyslog.aixforwardedfrom", "custom.rfc3164"]"
      And a file "/tmp/json_relay/nc.out" exists
    When connecting
      And sending the raw message "<message>"
      And waiting "1" seconds
      And searching lines for the pattern "<regex>" over "60" seconds
    Then a connection should be complete
      And the pattern should be found
      And a JSON entry should contain "<json>"

    Examples:
      | message | regex | json |
      | <38>Sep 19 23:43:29 Message forwarded from claimedhostname: procnamewithoutid: AIX extraneous forwarded from message without process ID | .*?AIX extraneous forwarded from message without process ID.* | { "hostname": "claimedhostname", "app-name": "procnamewithoutid", "procid" : "-" } |
      | <38>Sep 19 23:43:29 Message forwarded from claimedhostname: procnamewithid[99]: AIX extraneous forwarded from message with process ID | .*?AIX extraneous forwarded from message with process ID.* | { "hostname": "claimedhostname", "app-name": "procnamewithid", "procid" : "99" } |


  # - Negative testing with "malformed" message samples

  @slow
  Scenario Outline: Malformed messages do not create bogus field values
    Given a protocol "TCP" and port "514"
      And "rsyslog_omfwd_json_template" environment variable is "TmplJSONRawMsg"
      And a file "/tmp/json_relay/nc.out" exists
    When connecting
      And sending the raw message "<message>"
      And waiting "1" seconds
      And searching lines for the pattern "<regex>" over "60" seconds
    Then a connection should be complete
      And the pattern should be found
      And a JSON jmespath "<path>" field should be "<value>"

  Examples:
    | message | regex | path  | value |
    | Sep 19 23:43:29 lies Poor form RFC3164 with no priority | .*?RFC3164 with no priority.* | hostname | lies |
    | <17>Poor form RFC3164 with no syslog header - avoid bogus hostname  | .*?RFC3164 with no syslog header.* | "syslog-relay"."header-valid" | false |
    | Poor form RFC3164 with no syslog header or priority - avoid bogus hostname  | .*?RFC3164 with no syslog header or priority.* | "syslog-relay"."pri-valid" | false |
    | <14>1 2017-09-21 23:43:29 behave test 99999 - incorrect non-IS08601 timestamp with extra space | .*incorrect non-IS08601 timestamp with extra space.* | "syslog-relay"."header-valid" | false |
    | <14>1 2017-09-21T23:43:29.402+02:00 behave test 99999 - [bogus structured-data element] misc text after incorrect structured data element | .*bogus structured-data element.* | "rfc5424-sd" | null |


  @slow
  Scenario Outline: Don't parse messages which are not JSON
    Given a protocol "TCP" and port "514"
      And "rsyslog_omfwd_json_template" environment variable is "TmplJSONRawMsg"
      And a file "/tmp/json_relay/nc.out" exists
    When connecting
      And sending the raw message "<message>"
      And waiting "1" seconds
      And searching lines for the pattern "<regex>" over "60" seconds
    Then a connection should be complete
      And the pattern should be found
      And a JSON jmespath "<path>" field should be "<value>"

    Examples:
      | message | regex | path  | value |
      | <14>Sep 19 23:43:29 behave test[3]: 3 Well formed RFC3164 which is not a JSON message | .*?3 Well formed RFC3164 which is not a JSON message.* | "syslog-relay"."json-msg-parsed" | false |
      | <14>1 2017-09-19T23:43:29+00:00 behave test 5 - - 5 Well formed RFC5424 which is not a JSON message | .*?5 Well formed RFC5424 which is not a JSON message.* | "syslog-relay"."json-msg-parsed" | false |
