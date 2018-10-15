# docker-rsyslog

An rsyslog container intended to transfer syslog input into kafka with a JSON format (because rsyslog is way better than logstash syslog inputs).

## Features

rsyslog is fast, highly adaptable, but notoriously difficult to configure via config files. This image tries to pre-package some common use-cases that can be controlled via setting env vars. The objective is to avoid needing to supply configuration in rainerscript or legacy config syntaxes.

### Inputs

Accept multiple syslog inputs:

- Handle formats (RFC3164 and RFC5424).
  - Also accept structured logs (with `@cee` tag to indicate JSON paylod).
  - Deal with syslog output forwarded from some quirky non-standard systems like AIX.
- Accept multiple syslog transports (UDP, TCP or RELP).
- Accept multiple security options (TLS or not).
- Optionally append useful metadata with `rsyslog_support_metadata_formats=on` to add context about how a messge was recieved.

The table below lists pre-configured inputs:

| Port | Proto    | Use                              | Encryption | Authentication             |
| ---- | -------- | -------------------------------- | ---------- | -------------------------- |
| 514  | UDP      | Legacy syslog transport          | No         | No                         |
| 514  | TCP      | Plain TCP high-performance       | No         | No                         |
| 601  | TCP      | Plain TCP with offical IANA port | No         | No                         |
| 2514 | RELP     | Reliable Event Log Protocol      | No         | No                         |
| 6514 | TCP+TLS  | Secure TCP                       | Yes        | Sever, client configurable |
| 7514 | RELP+TLS | Secure RELP                      | Yes        | Server only                |
| 8514 | RELP+TLS | Secure RELP                      | Yes        | Server, client required    |

### Outputs

Some built-in use cases, e.g.:

* Split and output files to a volume.
* Produce JSON to a Kafka topic.

- Relay syslog RFC3164 or RFC5424 formats to other syslog servers (e.g. a SIEM product).
- Send JSON over TCP (e.g. to logstash).

### Formats

Legacy formats/templates can easily be set via [pre-defined rsyslog template names](https://www.rsyslog.com/doc/v8-stable/configuration/templates.html) (i.e. `rsyslog_TraditionalForwardFormat` or `rsyslog_TraditionalFileFormat`). However several additional output templates can be set per output:

- RFC5424:
  - `TmplRFC5424` (same as `rsyslog_SyslogProtocol23Format`).
  - `TmplRFC5424Meta` which appends a extra structured data element fields with more info about how the message was received in a `syslog-relay` structured element.
- JSON output templates:
  - `TmplrsyslogJSON` is the full native rsyslog message object (might duplicate fields, but also useful to debug with).
  - `TmplJSON` is a JSON output option for a subset of common syslog fields and the parsed msg portion (the message after the syslog header pieces)
  - `TmplJSONRawMsg` includes the full raw message inlcuding orginal syslog headers - potentially useful as provenance / evidence on exactly how the message was transfered from a source
  - Optionally convert structured data in RFC5424 into a nested JSON object (or null if not present) with `rsyslog_mmpstrucdata=on`.
  - Optionally parse JSON message payloads with `rsyslog_mmjsonparse=on` (as a default, usually preceeded by `@cee` cookie).
    - Use `rsyslog_mmjsonparse_without_cee=on` to try parse messages as JSON without the cookie.
- A raw template `RawMsg` can be useful to bypass most rsyslog parsing and simply relay that data as is.
  - One might also then skip parsing with `parser="rsyslog.pmnull"` for a given ruleset.
  - Note that some network devices and solaris don't provide syslog header names so the original log source identity can end up being lost).
- Allow logging rule-set extension via volume mounts with user provided configuration files (e.g. for custom filters and outputs)

See the `ENV` instructions with `rsyslog_` environment name prefixes in the `Dockerfile` to review default settings and options further.

The container also supports advanced debug scenarios.

About a year since starting this project, upstream rsyslog has started publishing [official rsyslog impages](https://hub.docker.com/u/rsyslog/) which in future will likely be better maintained and hopefully cover similar use cases.

## Usage

### TL;DR

#### YOLO

The 'yolo' way

```bash
docker container run --rm -it --name syslog jpvriel/rsyslog:latest
```

__NB!__:

- _NOT for production!_ (volumes left dangling between container runs, data loss likely, and client problems validating self-signed certs)
- Default self-signed cert's private key isn't private, it's PUBLIC, since it's checked into the code repo for testing purposes.

#### `TZ` should be set

__NB!__: when rsyslog starts, `TZ` should be set so it can efficiently deal with log source timestamps that lack timezone info (RFC3164).

- The timezone within docker container is UTC, even if your host has this set otherwise.
- Newer versions of rsyslog check if `TZ` is set within a container. See [rsyslog assumes UTC if TZ env var is not set and misses using the actual system's localtime](https://github.com/rsyslog/rsyslog/issues/2054) is closed as of v8.33.

#### Minimally sane

Create named volumes beforehand:

```bash
docker volume create syslog_log
docker volume create syslog_work
docker volume create syslog_tls
```

Provide 3 files for TLS setup placed in the `syslog_tls` and mounted as a volume at `/etc/pki/rsyslog`:

- a `key.pem`,
- a signed certificate, `cert.pem`, and
- your own trusted CA, e.g. `ca.pem`
(file names can be modified via ENV vars at runtime if need be)

Run docker mounting volumes and ensuring `TZ` is set/passed

```bash
docker container run --rm -it \
 -v syslog_log:/var/log/remote \
 -v syslog_work:/var/lib/rsyslog \
 -v syslog_tls:/etc/pki/rsyslog \
 -e TZ='Africa/Johannesburg' \
 --name syslog jpvriel/rsyslog:latest
```

#### docker-compose

The usual `docker-compose up`.

Version dependency on compose file format v2.2 and docker engine 1.13.0+.

Note:
- Assumes `TZ` is set and passes this along (see above).
- Assumes or creates named volumes (`syslog_log`, `syslog_work`, `syslog_tls`).
- The volume name is forced (doesn't use the directory prefix). E.g. if run from a directory `docker-rsyslog`, then:

```
$ docker container inspect -f "{{range .Mounts}}{{.Destination}} = {{.Source}}{{println}}{{end}}" dockerrsyslog_syslog_1
/var/log/remote = /var/lib/docker/volumes/syslog_log/_data
/var/lib/rsyslog = /var/lib/docker/volumes/syslog_work/_data
/etc/pki/rsyslog = /var/lib/docker/volumes/syslog_tls/_data
```

### Signal handling and clean exit

As per `man rsyslogd`, the daemon process responds to various signals. The `entrypoint.sh` entry-point script has handlers to pass these along provided the container is stopped as follows:

```bash
docker container stop -t 300 syslog
```

Notice the example has 300 seconds (5 minutes grace) to allow rsyslog to stop gracefully.

If you DON'T see `INFO: rsyslog stopped normally`, then you know the container was stopped or got killed prematurely. The docker stop command first sends a TERM signal, but the default is to only wait 10 seconds and then KILL. rsyslog may need more time to sync data to disk or forward ouput. Therefore, tune the `--time` option for the stop command.

Stopping the container should allow the entry point script to execute `kill -SIGTERM $(cat /var/run/rsyslogd.pid)` so that rsyslog closes files and stops cleanly.

If you see `ERROR: Ungraceful exit...`, then most likely, the rsyslogd process died/aborted somehow.

### Environment variables

[test/test_syslog_server.env](test/test_syslog_server.env) as an example will provide ideas on some env vars you can set.

Reading the `ENV rsyslog_*` optons in the `Dockerfile` will provide a more exhustive list about what rsyslog configuration options are supported via environment variables.

#### How env vars get applied

The variable naming convention is roughly:

```
rsyslog_<module>_<settingSection>_<camelCaseSetting>
```

Excuse the mix of `snake_case` and `camelCase`. To understand how it applies, a quick example is `rsyslog_module_imtcp_streamDriver_authMode` which sets the option `streamDriver.authMode` in the imtcp module and golang text templates via `confd` get applied:

```rainerscript
module(
  load="imtcp"
  maxSessions="{{ getenv "rsyslog_module_imtcp_maxSessions" }}"
  streamDriver.name="gtls"
  streamDriver.mode="1"
    #This indicates TLS is enabled. 0 indicated disabled.
  streamDriver.authMode="{{ getenv "rsyslog_module_imtcp_streamDriver_authMode" }}"
  {{ if getenv "rsyslog_module_imtcp_streamDriver_authMode" | ne "anon" }}
  permittedPeer={{ getenv "rsyslog_tls_permittedPeer" }}
  {{ end }}
)
```

See [Are there naming conventions for variables in shell scripts?](https://unix.stackexchange.com/questions/42847/are-there-naming-conventions-for-variables-in-shell-scripts)

- `snake_case` works better for environment variables not set by the operating system.
- `CamelCase` helps undestand which rsyslog settings map into config when possible.

Some options are used to add or remove entire blocks of config, e.g. `rsyslog_omkafka_enabled='off'` will cause the entire omkafka block of rsyslog config to not be generated.

Other options are shared, e.g.

- `rsyslog_tls_permittedPeer` is provided to both the TCP TLS and RELP TLS input modules
- `rsyslog_om_action_queue_maxDiskSpace` is shared for all output action queues.

#### Limited config via env vars

`rsyslog` is a traditional UNIX-like application not written with micro-services and container architecture in mind. It has many complex configuration options and syntax not easily managed as environment variables or command switches.

Only a few common configuration scenarios are catered for as environment variables. See 'Optional config file volumes' to handle more complex cases.



#### docker-compose env_file gotchas

__NB!__: Watch out for rsyslog configuration with arrays and docker's `env_file` handling.

If the array is quoted as an environment variable, e.g. `a='["o1","o2"]'`, the docker passes along the environment variable with the literal quotes included (i.e. `'["o1","o2"]'` and not `["o1","o2"]`). The rsyslog configuration then fails to interpret the value as an array.

- rsyslog rainerscript has array objects, e.g, `["o1", "o2"]`, where `[` signifies the start of an array object.
- For rsyslog, `'["o1", "o2"]'` will be read by rainerscript as a string instead of an array.
- Using an `.env` file with square just brackets and unquoted seems to pass the array into rsyslog rainerscript without mangling it (via confd and golang text templates used in the background).
- For bash, `[` are `]` are special pattern character and `export a=["o1","o2"]; echo $a` results in `[o1,o2]` as output. Python also seems to end up interpreting the environment variables in this way.
- Docker / docker-compose has the nasty unexpected behaviour that quotes in the supplied `.env` file are not interpolated, but instead literally included! This breaks rsyslog config because `env_var='value'` in the `.env` file gets injected as `setting="'value'"` into rsyslog config instead of the expected `setting="value"`.

See:

- [Inconsistent env var parsing from docker-compose.yml](https://github.com/docker/compose/issues/2854)
- [strange interpretation/parsing of .env file](https://github.com/docker/compose/issues/3702)

More details about some env vars to setup the container at runtime are discussed in the "Optional Output Modules" section.

### Volumes and file mounts

The container will use the following for rsyslog's "working" directory and is needed to recreate a container without losing data from previous runs:

#### rsyslog TLS X509 certificate and private key

The container expects the following in order to use TLS/SSL:

- `/etc/pki/rsyslog/cert.pem`
- `/etc/pki/rsyslog/key.pem`

If not provided with valid files in those volumes, a default signed cert is used, but this will obviously work poorly for clients validating the server cert. It's only for testing.

- `/var/lib/rsyslog`

#### rsyslog output files

If enabling and using file output, a named volume is recommended for `/var/log/remote`. E.g, on my docker setup, the files get written out the hosts named docker volume storage at `/var/lib/docker/volumes/syslog_log/_data/<hostname>`. Instead of logging all events to a single file, this can be split further into `<hostname>/<filename based on facility or message content>`:

| Filename | Use | Filter |
| - | - | - |
| messages | | Everything not sent to facilities auth, authpriv and 13 |
| security | Operating system security messages | auth and authpriv facilities |
| audit | Linux kernel auditing? | facility 13 |
| firewall | Firewall execution actions | From Kernel facility and starting with keyworlds that common firewall messages use |
| console | Alert messages usually broadcast on the console | facility 14 |

The default traditional file output template applied is, but it can be modified to something better like `rsyslog_SyslogProtocol23Format` (RFC5424) or any other [built-in rsyslog templates](http://www.rsyslog.com/doc/v8-stable/configuration/templates.html#reserved-template-names) via the `rsyslog_omfile_template` env var.

#### Optional config files

For more advanced custom configuration, template config via env vars would be too tedious (given RainerScript and rsyslog options are so vast), so dedicated configuration file volumes can be used instead for custom filering or output in the folling sub-directories:

- `/etc/rsyslog.d/input/filters`
- `/etc/rsyslog.d/output/filters`
- `/etc/rsyslog.d/output/extra`

Placing a `*.conf` in the `input/filters` or `output/filters` sub-directory is included and applied globally to either (to all of) the inputs or outputs. Per-input, or per-output filters can also be included in additonal sub-directories named the same as the respective ruleset. E.g.
- `/etc/rsyslog.d/input/filters/remote_in_udp/*.conf` will _only_ apply to the `remote_in_udp` ruleset.
- `/etc/rsyslog.d/output/filters/fwd_syslog/*.conf` will _only_ apply to the `fwd_syslog` ruleset.

When including filters, the filters need to make use of conditional expressions to match and then discard the unwanted message with the `stop` keyword.

Example of a simple black-list (exclude) approach:

```rainerscript
if $fromhost-ip == '192.168.0.1' then { stop }
```

Example of a white-list approach:

```rainerscript
if (
  $syslogfacility == '4' or
  $syslogfacility == '10' or
  $syslogfacility == '13' or
  $syslogfacility == '14'
) then { continue } else { stop }
```

Including extra outputs is _Experimental (not tested)_

### Additional outputs

Pre-defined support for some common forwarding use cases:
- Kafka: `rsyslog_omkafka_enabled=on` and other options to be set.
  - JSON output, but template can be changed
- syslog forwarding / relay: `rsyslog_omfwd_syslog_enabled=on` and other options to be set.
  - RFC5424 output, but template can be changed
- JSON forwarding / relay over TCP: `rsyslog_omfwd_json_enabled=on` and other options to be set.
  - Useful for sending directly to logstash (no need for kafka)

And obviously, file output can be disabled with `rsyslog_omfile_enabled=off`.

Actual potential storage use for output action queues is affected by the shared setting `rsyslog_om_action_queue_maxDiskSpace`(in bytes):
$$
< maxDiskSpace > * <outputs>
$$

#### Kafka output

The Kafka output wraps the key config items for [omkafka](http://www.rsyslog.com/doc/master/configuration/modules/omkafka.html) so refer to rsyslog's documentation and look out for `rsyslog_omkafka` related `ENV` instructions in the `Dockerfile` to get a sense of options that can be set.

In terms of kafka security, only the `SASL/PLAIN` with the `SASL_SSL` security protocol has been tested. In theory, SASL with Kerberos might be possible, but requires the rsyslog container to have keytab files mounted, etc.

#### Extra input and/or output

_Beta : partially tested_

If an input or forwarding use case isn't covered as above, then:
1. Use `/etc/rsyslog.d/extra/` with your own config files
1. Add your own inputs and, if desired, intergrate them with pre-existing filters and output rulesets.
  1. Incorporate `$IncludeConfig /etc/rsyslog.d/input/filters/*.conf` into your own input processing ruleset to apply "global" input filters.
  1. Set your input module to use `ruleset="output"`, or if you first need to do your own custom adaptation (e.g. filters and enrichment) the use `call output` in your own own input processing ruleset. This approach will retainin the pre-bundled outputs and output filters.
1. Add your own oututs. If desired, intergrate them with pre-existing inputs, input filters and global output filters, via the `rsyslog_call_fwd_extra_rule` option:
  1. Set evn var `rsyslog_call_fwd_extra_rule=true` which enables `call fwd_extra` at the end of the master `output` ruleset grouping.
  2. If you enable the env var, but fail to define a ruleset called `fwd_extra` in your extra config, the rsyslog config will become  invalid.

More detail?

- See `test/etc/rsyslog.d/extra/91_extra_test.conf` for examples of adding custom extra config.
- See `50-ruleset.conf` template to understand more details about the pre-bundled rulesets that handle inputs and outpus.

E.g. to have a standalone setup that goes from some kafka input to a mongodb output without touching or being touched by the other "pre-canned" rulesets:

`/etc/rsyslog.d/extra/99_extra.conf`

```rainerscript
module(load="imkafka")
module(load="ommongodb")

input(
  type="imkafka"
  topic="mytopic"
  broker=["host1:9092","host2:9092","host3:9092"]
  consumergroup="default"
  ruleset="extra"
)

ruleset(name="extra" parser="rsyslog.rfc3164") {
  action(
    server="mymonddb"
    serverport=27017
    ...
  )
}
```

E.g. to create an extra input and plug it into the pre-canned output, use `call output` within your own input ruleset to call the standard output (implies global output filters apply):

`/etc/rsyslog.d/extra/49_input_extra.conf`

```rainerscript
module(load="imkafka")
input(
  type="imkafka"
  topic="mytopic"
  broker=["host1:9092","host2:9092","host3:9092"]
  consumergroup="default"
  ruleset="kafka_in_extra_topic"
)

# apply global input filters
ruleset(name="kafka_in_extra_topic" parser="rsyslog.rfc3164") {
  $IncludeConfig /etc/rsyslog.d/input/filters/*.conf
  call output
}
```

E.g. to create an extra output which intergates with the "pre-canned" pipeline that will already call `fwd_extra` at the end of the normal output ruleset (implies global output filters apply):

`/etc/rsyslog.d/extra/89_fwd_extra.conf`

```rainerscript
module(load="ommongodb")
ruleset(name="fwd_extra")
{
  action(
    server="mymonddb"
    serverport=27017
    ...
  )
}
```

### Template examples

For each pre-canned output, a template can be set. Some advanced templates have flags to enable/include them (i.e. `grep -E 'rsyslog_.*__template' Dockerfile` to get an idea of the options).

By default `rsyslog_support_metadata_formats` and `rsyslog_mmpstrucdata` options are off. They can help add meta-data and make structured data elements parsable as JSON. For JSON output, recommended combinations are:
- `TmplJSON` and `rsyslog_support_metadata_formats=off`, or
- `TmplJSONRawMsg` or `TmplRFC5424Meta` require `rsyslog_support_metadata_formats=on`, otherwise these templates won't work.

The table shows compatible template and options.

| Templates | Use | rsyslog_support_metadata_formats | rsyslog_mmpstrucdata |
| - | - | - | - |
| `TmplRFC5424` | RFC5424 (same as `rsyslog_SyslogProtocol23Format`) | NA, omitted | NA, not a JSON format |
| `TmplRFC5424Meta` | RFC5424 with extra structured meta-data element | Yes, prepended to SD-Elements | NA, not a JSON format |
| `TmplrsyslogJSON` | rsyslog's internal JSON representation | Yes, appears in `$!` root object | Yes, adds `rfc5424-sd` to `$!` |
| `TmplJSON` | Simplified smaller JSON message | No, omits fields for meta-data | Yes |
| `TmplJSONRawMsg` | More complete well structured JSON message | Yes, appears in `syslog-relay` object | Yes, replaces `structured-data` field with JSON object |

`rsyslog_support_metadata_formats` is also needed add logic that builds in some extra validation steps in order to output the meta-data with more accurate information about the origin of the message. rsyslog readily parses almost any valid text as a hostname with RFC3164, even when the message looks like it's ignoring the conventions and it's unlikely a valid hostname - as per this issue: [pmrfc3164 blindly swallows the first word of an invalid syslog header as the hostname](https://github.com/rsyslog/rsyslog/issues/1789).

Refer to `etc/confd/templates/60-output_format.conf.tmpl` and `https://github.com/JPvRiel/docker-rsyslog/blob/master/README_related.md#rsyslog-meta-data` for more details and motivation behind this feature.

The following template output examples are based on enabling these extra features:

```bash
rsyslog_support_metadata_formats=on
rsyslog_mmpstrucdata=on
```

#### TmplRFC5424Meta

Meta-data about message origin pre-pended to the structured data element list:

```
<14>1 2017-09-19T23:43:29+00:00 behave test - - [syslog-relay@16543 timegenerated="2017-10-24T00:43:55.323108+00:00" fromhost="dockerrsyslog_sut_run_1.dockerrsyslog_default" fromhost-ip="172.18.0.9" myhostname="test_syslog_server" inputname="imptcp" format="RFC5424" pri-valid="true" header-valid="true" tls="false" authenticated-client="false"][test@16543 key1="value1" key2="value2"] Well formed RFC5424 with structured data
```

#### TmplJSON

Message missing structured data (e.g. null `-` or RFC3164 message) with more minimal output. Takes hostname from rsyslog parser without any sanity checks.

```json
{
  "syslogfacility": 1,
  "syslogfacility-text": "user",
  "syslogseverity": 6,
  "syslogseverity-text": "info",
  "timestamp": "2017-09-19T23:43:29+00:00",
  "hostname": "behave",
  "app-name": "test",
  "procid": "99999",
  "msgid": "-",
  "structured-data": null,
  "msg": "Well formed RFC5424 with PID and no structured data"
}
```

#### TmplJSONRawMsg

Message with RFC5424 structured data and custom meta-data about message origin. Some basic sanity checks performed to avoid outputting bogus hostnames from malformed RFC3164 messages. `structured-data` is converted to a JSON object.

```json
{
  "syslogfacility": 1,
  "syslogfacility-text": "user",
  "syslogseverity": 6,
  "syslogseverity-text": "info",
  "timestamp": "2017-09-19T23:43:29+00:00",
  "hostname": "behave",
  "app-name": "test",
  "procid": "-",
  "msgid": "-",
  "structured-data": {
    "test@16543": {
      "key1": "value1",
      "key2": "value2"
    }
  },
  "rawmsg": "<14>1 2017-09-19T23:43:29+00:00 behave test - - [test@16543 key1=\"value1\" key2=\"value2\"] Well formed RFC5424 with structured data",
  "syslog-relay": {
    "timegenerated": "2017-10-24T00:00:10.561635+00:00",
    "fromhost": "dockerrsyslog_sut_run_1.dockerrsyslog_default",
    "fromhost-ip": "172.18.0.9",
    "myhostname": "test_syslog_server",
    "inputname": "imptcp",
    "format": "RFC5424",
    "pri-valid": true,
    "header-valid": true,
    "tls": false,
    "authenticated-client": false
  }
}
```

#### TmplRSyslogJSON

Message with RFC5424 structured data and using the native rsyslog `%jsonmesg%` output

```json
{
  "msg": "Well formed RFC5424 with structured data",
  "rawmsg": "<14>1 2017-09-19T23:43:29+00:00 behave test - - [test@16543 key1=\"value1\" key2=\"value2\"] Well formed RFC5424 with structured data",
  "timereported": "2017-09-19T23:43:29+00:00",
  "hostname": "behave",
  "syslogtag": "test",
  "inputname": "imptcp",
  "fromhost": "gateway",
  "fromhost-ip": "172.17.0.1",
  "pri": "14",
  "syslogfacility": "1",
  "syslogseverity": "6",
  "timegenerated": "2017-10-23T22:50:12.997829+00:00",
  "programname": "test",
  "protocol-version": "1",
  "structured-data": "[test@16543 key1=\"value1\" key2=\"value2\"]",
  "app-name": "test",
  "procid": "-",
  "msgid": "-",
  "uuid": null,
  "$!": {
    "rfc5424-sd": {
      "test@16543": {
        "key1": "value1",
        "key2": "value2"
      }
    }
  }
}
```

### rsyslog processing stats (impstats)

As per [formats
Tutorial: Sending impstats Metrics to Elasticsearch Using Rulesets and Queues](https://www.rsyslog.com/tutorial-sending-impstats-metrics-to-elasticsearch-using-rulesets-and-queues/), it can be useful to track how many messages rsyslog processes. Also:
-  [details of impstats module fields made in elasticsearch](https://github.com/rsyslog/rsyslog/issues/1796) helps ask for clarification about various stats produced.
- [rsyslog statistic counter](https://www.rsyslog.com/doc/master/configuration/rsyslog_statistic_counter.html) details some meaning for stats and which modules support stats.
- `omkafka` supports impstats since version 8.35.

By default, in `Dockerfile`, various stats env vars set the following:
- `rsyslog_module_impstats_interval='60'` causes stats to be produced ever minute
- `rsyslog_module_impstats_resetCounters='on'` resets many counters, but at the cost of some accuracy (see doc for `impstats`)
- `rsyslog_module_impstats_format='cee'` is the format set (instead of the legacy key value pair format used)
- `rsyslog_impstats_ruleset='syslog_stats'` sets the ruleset to send the stats output to, wherby stats are sent via normal syslog and the call to `output` will cause stats to be output/forwarded to all configured output modules. This can be changed to a single select 'pre-bundled' output ruleset if it was already enabled (e.g. `out_file`, `fwd_kafka`, `fwd_syslog` or `fwd_json`), or otherwise, a custom independant output can be defined via the extra config mechanism.

## Version

The convention is `<rsyslogd version>-<docker image release build number>`.

E.g. `8.29.0-3` means the output of `rsyslogd -v` shows `rsyslogd 8.29.0`, and it's the 3rd image released for that upstream version.

## Build

### Makefile build

The Makefile depends on `docker-compose` being installed.

If your user has docker socket permissions, e.g.:

```bash
make build
```

Else if you don't live dangerously ;-), and need to elevate privilege, e.g.:

```bash
sudo -E make build
```

Where `-E` helps pass on `http_proxy` env vars, etc.

The build argument `DISABLE_YUM_MIRROR=true` can help if you have a caching proxy (e.g. squid) and don't want the mirror selection process in yum to break proxy caching. However, if default mirrors are down, then build fails.

Changes to `build.env` should invalidate the build cache. Docker build caching for a given version and release number.

Note however, that `make build` focuses on the Dockerfile for the rsyslog server and doesn't trigger rebuilds of other test container dependencies (such as python behave, kafka, etc)

To force a full rebuild using pull and no cache

```
sudo -E make rebuild
```

### Manual build examples

The tagging convention followed is to match the `rsyslog_VERSION` to the version of rsyslogd the container is based on and add a release number thereafter. This is manually set to reflect the upstream stable RPM release. E.g. `export rsyslog_VERSION=8.33.1`

Build command example:

```bash
docker build -t jpvriel/rsyslog:${rsyslog_VERSION}-1 -t jpvriel/rsyslog:latest .
```

Building from behind a caching proxy (assuming proxy env vars are appropriately set) when you don't want yum mirror plug-ins to invalidate your proxy cache:

```bash
sudo -E docker build --build-arg DISABLE_YUM_MIRROR=true --build-arg http_proxy=$http_proxy --build-arg https_proxy=$https_proxy --build-arg no_proxy=$no_proxy -t jpvriel/rsyslog:${rsyslog_VERSION}-1 -t jpvriel/rsyslog:latest .
```

### Pre-bundled X509 test certificate and private key

Note, a pre-bundled self-signed cert and ca is used for test purposes. It is expected in the following places:

- key: `/usr/local/etc/pki/test/test_syslog_server.key.pem`
- cert: `/usr/local/etc/pki/test/test_syslog_server.cert.pem`

The default certs are generated via `./util/certs.sh` to work for the `sut` test suite.

To embed an internal/extra org CA, add more files to `etc/pki/ca-trust/source/anchors` and rebuild.

### Embed own CA certs for TLS

Note, there is a runtime `rsyslog_global_ca_file` env var to set the CA for rsyslog.

However, should you need to embed a CA for other reasons (e.g. building via a corporate TLS intercepting proxy), you embed your own CA at build time by placing your own CA certificates in `etc/pki/ca-trust/source/anchors`.

## Testing

### System under test (SUT)

Follows docker convention to use an `sut` service to test. Depends on several other containers like `zookeeper` and `kafka` images in order to test component intergeneration (e.g. `omkafka`).

#### Makefile test

Similar to build, e.g.:

```bash
sudo -E make test
```

If the test fails, make aborts and the test containers are not cleaned up which allows investigating the failure. If successful, the test environment is torn down. Also, `make test_clean` is run before testing to ensure a previous failed test run doesn't interfere.

To find a quick recap of which tests failed after lengthy and verbose python behave output, `xmlint` and `highlight` can process the JUnit test file output:

```bash
xmllint --xpath '//failure' test/behave/reports/TESTS-*.xml  | highlight --out-format=ansi --syntax xml
```

#### Manual test invocation

The "system under test" suite was written with python behave.

To build just the `sut` service:

```bash
docker-compose -f docker-compose.test.yml build sut
```

Reminder, use `--build-arg http_proxy` etc if you have to do this via a proxy.

Run the full test suite to regression test:

```bash
docker-compose -f docker-compose.test.yml run sut
```

If you're extending, run just `@wip` pieces to focus on new features:

```bash
docker-compose -f docker-compose.test.yml run sut behave -w behave/features
```

To see interplay between other test container dependencies and the syslog server container:

```bash
docker-compose -f docker-compose.test.yml up
```

The above will have a lot of output... An alternative is to look at `docker logs <service name>`

Cleanup:

```bash
docker-compose -f docker-compose.test.yml down -v
```

__NB!__: failing to cleanup causes stale volumes and test components which search those volumes could operate off stale test values! Always clean between tests.

### Building test dependencies

`sudo -E make test` should automatically pull and build everything needed via [docker-compose.test.yml](docker-compose.test.yml).

Test services can be built directly with `sudo -E make build_test`, or or force a full rebuild with `sudo -E make rebuild_test`.

As an example, the CentOS test client can be built in isolation:

```bash
docker-compose -f docker-compose.test.yml build --build-arg DISABLE_YUM_MIRROR=true --build-arg http_proxy --build-arg https_proxy --build-arg no_proxy test_syslog_client_centos7
```

There's also an ubuntu syslog test client, zookeepr, kafka and other images used to provide system testing.

## Debug and additional validation steps

### Configuration validation

Configuration passing mistakes and issues are all too common with rsyslog.

An explicit check can be done by using `-N1`. And a special python script assembles and outputs the full rsyslog configuration if you use `-E`. For example:

```bash
docker container run --rm -it \
 -v syslog_log:/var/log/remote \
 -v syslog_work:/var/lib/rsyslog \
 -v syslog_tls:/etc/pki/rsyslog \
 -e rsyslog_omfile_enabled=true \
 --name syslog jpvriel/rsyslog:latest -E
```

`-E` is interpreted by entrypoint shell script. To the python script within a running container, use:

```
docker container exec --name syslog rsyslog_config_expand.py
```

Output will have `##` comment tags to help highlight and show when `$IncludeConfig` directives are expanded to produce a flattened config output with line number prefixes:

```
12: $IncludeConfig /etc/rsyslog.d/*.conf
##< start of include directive: $IncludeConfig /etc/rsyslog.d/*.conf
##^ expanding file: /etc/rsyslog.d/30-globals.conf
 1: # Collect stats
 2: module(load="impstats" interval="60")
...
##> end of expand directive: $IncludeConfig /etc/rsyslog.d/*.conf
```

This helps track back to the exact line number of config that rsyslogd had a problem with, which is otherwise non-trivial due to the use of the confd and golang text template pre-processing needed to map environment variables into the config files.

#### Inspect configuration while testing

The `sut` (system under test) service will warn about invalid config, but hides the detailed error output. To more clearly see the issue, try:

```bash
docker run -it --rm --name rsyslogtest --env-file test/test_syslog_server.env jpvriel/rsyslog rsyslogd -N1
```

Similarly, to expand the config used for testing:

```bash
docker-compose -f docker-compose.test.yml exec test_syslog_server rsyslog_config_expand.py
```

Or if need be, inspect the output of test_syslog_server in the volume, e.g.

And to save time testing config issues, it's possible to just run the test_syslog_server service instead of the full SUT.

```bash
docker-compose -f docker-compose.test.yml run test_syslog_server_config
docker cp docker-rsyslog_test_syslog_server_config_run_1:/tmp/config_check test/config_check
```

### Checking for file output

One basic ways to see if the rsyslog container works is to run it with file output enabled and written out to a named volume.

Assuming a suitable volume is created, e.g. `docker volume create syslog_log`, run the container with the volume and `-e rsyslog_omfile_enabled=true`.

```bash
docker container run --rm -it \
 -v syslog_log:/var/log/remote \
 -v syslog_work:/var/lib/rsyslog \
 -v syslog_tls:/etc/pki/rsyslog \
 -e rsyslog_omfile_enabled=true \
 --name syslog jpvriel/rsyslog:latest
```

Get the container IP, e.g:

```bash
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' syslog
172.17.0.3
```

Use `logger` or an alternate program to send a test message, e.g. via UDP:

```bash
logger -d -n 172.17.0.3 'Test UDP message'
```

Check the output file:

```bash
sudo tail /var/lib/docker/volumes/syslog_log/_data/udp/5424/$(hostname)/messages | grep --color -E 'Test UDP message|$'
```

### Advanced debugging

One may want to debug the entry point script `entrypoint.sh`, `rsyslogd`, or both.

rsyslog depends on a command line flag `-d` or the `rsyslog_DEBUG` environment variables being set in order to debug. See [rsyslog Debug Support](http://www.rsyslog.com/doc/master/troubleshooting/debug.html).

Enabling debug has performance implications and is probably NOT appropriate for production. Debug flags for rsyslogd does not affect entrypoint script debugging. To make the entrypoint script be verbose about shell commands run, use `ENTRYPOINT_DEBUG=true`.

```bash
docker container run --rm -it \
 -v syslog_log:/var/log/remote \
 -v syslog_work:/var/lib/rsyslog \
 -v syslog_tls:/etc/pki/rsyslog \
 --name syslog jpvriel/rsyslog:latest rsyslogd -d
```

Alternatively, to run with rsyslogd debug enabled but silent until signaled (via `SIGUSR1`), add `-e rsyslog_DEBUG=DebugOnDemand`.

To trigger debug output, send the container a signal (which `entrypoint.sh` entrypoint passes on to rsyslogd)

```bash
docker container kill --signal=SIGUSR1 syslog
```

Sometimes you may need to debug within the container, e.g. when it doesn't even make it past configuration.

Override the entrypoint or use exec on a running container.

E.g. override entrypoint:

```bash
docker container run --rm -it \
 -v syslog_log:/var/log/remote \
 -v syslog_work:/var/lib/rsyslog \
 -v syslog_tls:/etc/pki/rsyslog \
 --name syslog --entrypoint /bin/bash jpvriel/rsyslog:latest
```

Then run the init script manually to see if there are problems:

```bash
ENTRYPOINT_DEBUG=true /usr/local/bin/entrypoint.sh
```

E.g. or exec on an already running container:

```bash
docker container exec -it syslog /bin/bash
```

Via the test suite and `make test`, the rsyslog server container can fail to start properly and exits before much opportunity to debug issues. A way to try debug after the fact is to create an image from it, run the image and override the entrypoint.

```bash
docker commit dockerrsyslog_test_syslog_server_config_1 dockerrsyslog_test_syslog_server_config_1_debug
docker container run --rm -it \
 --env-file test/test_syslog_server.env \
 -v "$(pwd)/test/etc/rsyslog.d/output/filters/:/etc/rsyslog.d/output/filters/" \
 -v dockerrsyslog_syslog_log:/var/log/remote \
 --name debug_test_syslog \
 --entrypoint /bin/bash \
 dockerrsyslog_test_syslog_server_config_1_debug
```

Once in the container, do debugging, e.g.:
- Inspect all rsyslog env vars with `env | grep rsyslog_` (note use of `--env-file` when running).
- Filter env vars to a list of what's enabled or disabled: `env | grep -E "=(on)|(off)"`
- Check config `rsyslogd -N1`
- See how the env vars and config templates expaned out into config: `/usr/local/bin/rsyslog_config_expand.py`
- Run the entrypoint `/usr/local/bin/entrypoint.sh`
- Iterativly disable or change options that may be causing the issue, e.g. `export rsyslog_input_filtering_enabled=off` and rerun the entrypoint script.

For example, the error `rsyslogd: optimizer error: we see a NOP, how come? [v8.33.1 try http://www.rsyslog.com/e/2175 ]` was hard to debug (due to no config line referenced by the error message). By following the above debug approach and toggling `rsyslog_output_filtering_enabled` between on and off, as well as enabling and disabling included filter config files, I was able to discover that the `continue` keyword conflicted with the rainerscript optimiser checking code.

Then cleanup the debug image:

```bash
docker image rm dockerrsyslog_test_syslog_server_config_1_debug
```

### Debugging WIP test scenarios

When you just run `sut` via compose, the output from other containers is hard to see.

Some advice here is:

- Set `rsyslog_DEBUG: 'Debug'` for the `test_syslog_server` in `docker-compose.test.yml`.
- Execute `docker-compose -f docker-compose.test.yml run sut behave -w behave/features`.
- Run `docker logs dockerrsyslog_test_syslog_server_` to see the debug output.
- Use `docker-compose -f docker-compose.test.yml down` and `docker system prune --filter 'dangling=true'` between test runs to ensure you don't end up searching on log files within volume data for previous test runs...

You may need to adapt according to how dockerd logging is configured.

For behave failures, the following can help:
- To avoid a work in progress scenario tagged with the `@wip` fixture, use `--tags=-wip`, e.g. `docker-compose -f docker-compose.test.yml run sut behave behave/features --tags=-wip`.
- Use `--exclude PATTERN` with the behave command to skip problematic feature files.

### Sanity check kafka

Kafka configuration via docker with TLS and SASL security options is fairly complex. Docker compose will create a user defined docker network, and zookeeper/kafka can be accessed within that network via their docker hostname (docker network alias). It can help to use the kafka console producer and consumers within containers and the same docker network to sanity check the kafka test dependencies. The SASL_SSL protocol is run on port 9092, but a PLAINTEXT protocol run on port 9091 can help sanity check basic function without being encumbered by security config parameters.

Run kafka test broker

```bash
docker-compose -f docker-compose.test.yml up -d test_kafka
```

Tail the output for the broker

```bash
docker logs -f docker-rsyslog_test_kafka_1
```

#### Checking with PLAINTEXT protocol

Assuming a topic has already been setup, run console producer on the insecure port

```bash
docker run -it --rm --net=docker-rsyslog_default wurstmeister/kafka /opt/kafka/bin/kafka-console-producer.sh --broker-list test_kafka:9091 --batch-size 1 --topic test_syslog
```

Run console consumer on the insecure port

```bash
docker run -it --rm --net=docker-rsyslog_default wurstmeister/kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server test_kafka:9091 --topic test_syslog --from-beginning
```

And then type messages in the producer checking if they are echoed in the consumer.

#### Checking with SASL_SSL protocol

TLS and SASL config needs to be provided to the container. This can be done by bind mounting files with the correct properties/config, e.g.in the properties file:

```
ssl.truststore.location=/tmp/test_ca.jks
ssl.truststore.password=changeit
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="test" password="test-secret"
```

Alternatively, specify the settings via `--consumer-property`, e.g.:

```bash
docker run -it --rm --net=docker-rsyslog_default -v "$PWD/test/tls_x509/certs/test_ca.jks":/tmp/test_ca.jks:ro wurstmeister/kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server test_kafka:9091 --consumer-property ssl.truststore.location=/tmp/test_ca.jks ssl.truststore.password=changeit security.protocol=SASL_SSL sasl.mechanism=PLAIN sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="test" password="test-secret"';' --topic test --from-beginning
```

And as before, checking if messages are echoed in the consumer.

#### Checking kafka from the host (not stuck in another container)

Instead of running with the kafka container, you can try your own kafka install or lib on your docker host, but it's complicated by two things:
- kafka is picky and requires you to use an advertised hostname when connecting? I.e. can't just connect using an IP?
- Docker networking has it's own isolated and embeded DNS resolver not exposed to your host, so your host can't (by default) use conatiner dns aliases

While you can find the kafka IP as follows, connections to kafka by IP don't work well:

```bash
docker container inspect --format '{{ range .NetworkSettings.Networks }}{{ .IPAddress }}{{ end }}' docker-rsyslog_test_kafka_1
```

#### Useful docker inspect format tricks

If you want to double check a proper env var was set for the rsyslog or kafka container:

```bash
docker container inspect --format '{{ range .Config.Env }}{{ println . }}{{ end }}' docker-rsyslog_test_kafka_1
```

If you want to poke at ports and servies for each container, it would help to know the network range and IPs:

```bash
docker network inspect --format '{{ range .Containers }}{{ .Name }} = {{.IPv4Address}}{{ println }}{{ end }}' docker-rsyslog_default
```

## Known limitations

### TLS/SSL config

rsyslog appears to use GNU TLS and TLS libraries in ways which don't readily allow TLS client authentication to be optionally set. Recent versions of rsyslog are beginning to add openssl support, but it was still "beta" at the time of testing.

For `imtcp`, TLS settings apply globally to all inputs via a stream driver conifg.

For `imrelp`:

- TLS settings can apply per input.
- While there's no documented setting for optional TLS client authentication, it is possible to have two listeners on two different ports, one not requesting client certs, and a 2nd requiring client certificates.

[#1738](https://github.com/rsyslog/rsyslog/issues/1738) provides an overview of TLS issues.

#### Finding TLS errors

For example, you'd likely encounter the following error because RELP GNU TLS / `gtls` forces asking for a client certificate.

Check docker log output for imrelp module messages:

```bash
docker container logs docker-rsyslog_test_syslog_server_1 2>&1 | grep imrelp
```

TLS errors might be found:

```
rsyslogd: imrelp[7514]: authentication error 'peer did not provide a certificate', peer is '' [v8.38.0 try http://www.rsyslog.com/e/2353 ]
rsyslogd: imrelp[7514]: error 'TLS handshake failed [gnutls error -43: Error in the certificate.]', object  'lstn 7514: conn to clt 172.23.0.9/docker-rsyslog_sut_run_1.docker-rsyslog_default' - input may not work as intended [v8.38.0 try http://www.rsyslog.com/e/2353 ]
```

### JSON formats

As per the offical [CEE](http://cee.mitre.org/) site, CEE sponsership was halted and not that many systems adopted CEE. rsyslog accepts JSON formatted messages is they are preceeded with an `@cee` cookie, but in testing, this doesn't appear to work well if the message also has RFC5424 structured data preceeding the cookie.

As per issue [#2827](https://github.com/rsyslog/rsyslog/issues/2827), rsyslog didn't have a simple way to set or manage non-string based JSON types such as booleans, numbers or null, which adds to the complexity of 'hand-crafted' output templates.

### Legacy formats

RFC3164 and the legacy file output format of many Linux distro's and *nixes does not include the year, sub-second accuracy, timezone, etc. Since it's still somewhat common to expect files in this format, the file output rsyslog_omfile_template defaults to `rsyslog_TraditionalFileFormat`. This can help with other logging agents that anticipate these old formats and cannot handle the newer formats.

The other forwarding/relay outputs default to using more modern RFC5424 or JSON formats.

rsyslog can accept and convert RFC3164 legacy input, but with some conversion caveats, such as guessing the timezone of the client matches that of the server, and lazy messages without conventional syslog headers are poorly assumed to map into host and process name fields.

### Non-printable characters

rsyslog has a safe default of escaping non-printable characters, which, unfortunatly includes tab characters. Some products expect and use tab characters to delimit fields, so while rsyslog escapes tabs as `#11` by default, I decided to change this behaviour and allow tabs. Set the env var `rsyslog_global_parser_escapeControlCharacterTab="on"` to revert to default behaviour of espacing tabs.

### Complexity with golang confd templates, rainerscript, and syslog templates

While the approach taken attempted to expose/simply running an rsyslog container by just setting a couple of environment variables, a lot of underlying complexity (and maintainer burden) occurs because:
- Confd and golang text templates dynamically change the rsyslog configuration files, so configuration errors reported by rsyslogd are hard to track back (hence the `-E` option for the container to see the expanded rsyslog configuration result with line numbers)
- rsyslog rainerscript syntax for assinging values to variables does not appear to support boolean true or false types, nor does it support a null type. As a resulty, trying to populate JSON template output with such types requires literal strings represent and be explicitly output as such without using native built-in json output templating, otherwise, rsyslogd will quote the JSON values as "true", "false" or "null" (which is not intended). This makes creating the desired JSON templates a verbose excercise of hand picking various elements with such types. Instead, coercing types downstream (e.g. via logstash or elasticsearch index templates) might be a simpler solution that allows for simpler rsyslog templates.

## Status

Note, recently (~Jan 2018) the rsyslog project has started to work on an official container and added better environment viable support that could make the confd templaing uncessary, so some refactoring and merging efforts into upstream should be looked into.

Done:
- Multiple inputs
- File output
- Using confd to template config via env vars
- Add metadata to a message about peer connection (helps with provenance) - avoid spoofed syslog messages, or bad info from poorly configured clients.
- Structured data as JSON fields (mmstructdata, with null case)
- Gracefull entrypoint script exit and debugging by passing signals to rsyslogd.
- Kafka and syslog forwarding (with SASL_SSL protocol)
- JSON input (with limitations)
- JSON output
- Filtering

Not yet done:
- Use mmfields module to handle LEEF and CEF extraction to JSON?
- Re-factor test suite
  - Simplify and depend on less containers one async support in behave allows better network test cases (using tmpfs shared volumes is the current work-arround)
  - Watch out for pre-existing files in volumes from prior runs (testing via Makefile avoids this pitfall)
- More rsyslog -> kafka optimisation, which would first require a benchmark test suite
- expose enhancments in env config like
  - `imptcp` socket backlog setting
  - confirm `impstats` counters for `omkafka`
- performance tuning as per https://rsyslog.readthedocs.io/en/stable/examples/high_performance.html started with input thread settings. However, ruleset and action output queues settings haven't been optimised or exposed with settings
  - `dequeueBatchSize`
  - `workerThreads`
  - multiple input rulesets all call a single ruleset that then calls multiple output rulesets
    - the central output ruleset might need more worker threads
  - Other docs
    - https://rsyslog.readthedocs.io/en/stable/concepts/queues.html
      > By default, rulesets do not have their own queue.

      And

      > Please note that when a ruleset uses its own queue, processing of the ruleset happens asynchronously to the rest of processing. As such, any modifications made to the message object (e.g. message or local variables that are set) or discarding of the message object have no effect outside that ruleset. So if you want to modify the message object inside the ruleset, you cannot define a queue for it.
    - https://rsyslog.readthedocs.io/en/stable/concepts/multi_ruleset.html
- performance tunning hooks for the main queue and the other output action queues as per https://www.rsyslog.com/performance-tuning-elasticsearch/ example.

Maybe someday:
- Re-factor docker entrypoint based on https://github.com/camptocamp/docker-rsyslog-bin example and https://www.camptocamp.com/en/actualite/flexible-docker-entrypoints-scripts/
- support and process events via snmptrapd?
- hasing template for checks on integrity, e.g. `fmhash`?
- Filter/send rsyslog performance metrics to stdout (omstdout) - is this needed?
- All syslog output to omstdout (would we even need this?)
- More test cases
  - Unit test for stopping and starting the server container to check that persistent queues in /var/lib/rsyslog function as intended
  - Older and other syslog demons as clients, e.g. from centos6, syslog-ng, etc
