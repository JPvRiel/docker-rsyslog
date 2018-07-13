### Expected behavior

mmjsonparse should work after both RFC5424 and RFC3164 messages headers. Docs state useRawMsg="off" is the default so I'd expect JSON processing to begin after any legitimate syslog headers.

If `cookie=""` is set, I'd hope mmjsonparse fails early (i.e. if within a short number of characters, a valid JSON structure isn't detected, abort and set parse result to `FAIL`).

### Actual behavior

While Docs don't explicilty state all the features, both RFC5424 and RFC3164 messages over network transports work as expected, event with structured data elements preceeding the JSON.

What isn't clear is the potential performance overhead and if mmjsonparse fails fast when not finding any valid JSON structure if the `@cee` cookie is not in use. How far down the message does it search for JSON?

### Steps to reproduce the behavior

Given a sample `test_mmjsonparse_cee.conf` and `test_samples.log`.

Via bash, run:

```
while IFS='' read -r rawmsg || [[ -n "$rawmsg" ]]; do echo $rawmsg >> /dev/udp/127.0.0.1/10514; done < test.log
```

2 messages fail, the rest parse:

```
# wc -l /tmp/*.json
    4 /tmp/rsyslog_cee_json_ok.json
    2 /tmp/rsyslog_json_fail.json
    7 /tmp/rsyslog_json_ok.json
   13 total
```

The failures are correct:

```
{
  "msg": "Well formed RFC3164 which is not a JSON message",
  "cee_json_parse": "FAIL",
  "json_parse": "FAIL"
}
{
  "msg": "Well formed RFC5424 which is not a JSON message",
  "cee_json_parse": "FAIL",
  "json_parse": "FAIL"
}
```

The raw CEE message

```
jq '.["$!"]' /tmp/rsyslog_cee_json_ok.json
{
  "json": "Well formed RFC3164 with process tag which is a JSON cee message",
  "cee_json_parse": "OK"
}
{
  "json": "Well formed RFC5424 without structured data followed by a JSON message with a cee cookie",
  "cee_json_parse": "OK"
}
{
  "json": "Well formed RFC5424 without structured data followed by a JSON message with a cee cookie that has no preceding space",
  "cee_json_parse": "OK"
}
{
  "json": "Well formed RFC5424 with structured data followed by a JSON message with cee cookie",
  "cee_json_parse": "OK"
}
```

The raw plain JSON messages (msg gets populated because first attempt with `@cee` cookie fails)
```
# jq '.["$!"]' /tmp/rsyslog_json_ok.json
{
  "msg": "{ \"json\": \"JSON with cee cookie and no header\"}",
  "cee_json_parse": "FAIL",
  "json": "JSON with cee cookie and no header",
  "json_parse": "OK"
}
{
  "msg": "{ \"json\": \"plain JSON with no header\" }",
  "cee_json_parse": "FAIL",
  "json": "plain JSON with no header",
  "json_parse": "OK"
}
{
  "msg": "{ \"json\": \"Well formed RFC3164 without process tag which is a JSON cee message\" }",
  "cee_json_parse": "FAIL",
  "json": "Well formed RFC3164 without process tag which is a JSON cee message",
  "json_parse": "OK"
}
{
  "msg": "{ \"json\": \"Well formed RFC5424 without structured data followed by a JSON message with a cee cookie as the process name\" }",
  "cee_json_parse": "FAIL",
  "json": "Well formed RFC5424 without structured data followed by a JSON message with a cee cookie as the process name",
  "json_parse": "OK"
}
{
  "msg": "{ \"json\": \"Well formed RFC5424 without structured data followed by a JSON message without a cee cookie\" }",
  "cee_json_parse": "FAIL",
  "json": "Well formed RFC5424 without structured data followed by a JSON message without a cee cookie",
  "json_parse": "OK"
}
{
  "msg": "{ \"json\": { \"nested\": \"Well formed RFC5424 without structured data followed by a nested JSON message without a cee cookie\" } }",
  "cee_json_parse": "FAIL",
  "json": {
    "nested": "Well formed RFC5424 without structured data followed by a nested JSON message without a cee cookie"
  },
  "json_parse": "OK"
}
{
  "msg": "{ \"json\": \"Well formed RFC5424 with structured data followed by a JSON message without cee cookie\" }",
  "cee_json_parse": "FAIL",
  "json": "Well formed RFC5424 with structured data followed by a JSON message without cee cookie",
  "json_parse": "OK"
}
```

### Environment
- rsyslog version: 8.36
- platform: centos 7.5
