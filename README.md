# Overview

An RSyslog container able to:

- Accept multiple syslog input formats (RFC3164 and RFC5424).
- Accept multiple transports (UDP, TCP or RELP).
- Accept multiple security options (TLS or not).
- Optionally append useful metadata with `rsyslog_support_metadata_formats=on`.
- Split and output files to a volume.

Forward the messages to other systems for a few built-in use cases, either:

- Downstream syslog servers expecting RFC3164 or RFC5424 (e.g. a SIEM product).
- Downstream analytic tools that can handle JSON (e.g. logstash).
- Kafka (e.g. data analytic platforms like Hadoop).

Legacy formats/templates can easily be set (i.e. `RSYSLOG_TraditionalForwardFormat` or `RSYSLOG_TraditionalFileFormat`). However several additional output templates can be set per output:

- RFC5424
  - `TmplRFC5424`
  - `TmplRFC5424Meta` which appends a extra structured data field with more info about how the message was received
- JSON output templates
  - `TmplRSyslogJSON` is the native rsyslog message object
  - `TmplJSON` is a streamlined option
  - `TmplJSONRawMeta` includes meta-data about how the message was received and the raw message
- Optionally convert structured data in RFC5424 into a nested JSON object (or null if not present) with `rsyslog_mmpstrucdata=on`

- Allow logging rule-set extension via volume mounts with user provided configuration files (e.g. for custom filters and outputs)

See the `ENV` instructions with `rsyslog_` environment name prefixes in the `Dockerfile` to review default settings and options further.

The container also supports advanced debug scenarios.

# Version

The convention is `<rsyslogd version>-<docker image release build number>`.

E.g. `8.29.0-3` means the output of `rsyslogd -v` shows `rsyslogd 8.29.0`, and it's the 3rd image released for that upstream version.

# Usage

## TL;DR

### The YOLO way (NOT for production!)

The 'yolo' way (volumes left dangling between container runs, data loss likely, and client problems validating self-signed certs)

```bash
docker container run --rm -it --name syslog jpvriel/rsyslog:latest
```

_NB!_ The default self-signed cert's private key isn't private, it's PUBLIC, since it's checked into the code repo for testing purposes.

### Minimally sane way

The minimally sane way

Create named volumes beforehand

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
 -e TZ \
 --name syslog jpvriel/rsyslog:latest
```

_NB!_ when rsyslog starts, it depends on `TZ` to be set to properly and efficiently deal with log source timestamps that lack timezone info. It'll then be able to assume and use localtime for templates that output timestamps that include time zone information.

### Compose way

The usual `docker-compose up`. Note, assumes or creates named volumes (`syslog_log`, `syslog_work`, `syslog_tls`).

Note, the volume name is forced (doesn't use the directory prefix). E.g. if run from a directory `docker-rsyslog`, then:

```
$ docker container inspect -f "{{range .Mounts}}{{.Destination}} = {{.Source}}{{println}}{{end}}" dockerrsyslog_syslog_1
/var/log/remote = /var/lib/docker/volumes/syslog_log/_data
/var/lib/rsyslog = /var/lib/docker/volumes/syslog_work/_data
/etc/pki/rsyslog = /var/lib/docker/volumes/syslog_tls/_data
```

## Checking if the container (and rsyslog process) stopped gracefully

As per `man rsyslogd`, the daemon process responds to various signals. The `entrypoint.sh` entry-point script has handlers to pass these along provided the container is stopped as follows:

```bash
docker container stop -t 300 syslog
```

Notice the example has 300 seconds (5 minutes grace) to allow rsyslog to stop gracefully.

If you DON'T see `INFO: rsyslog stopped normally`, then you know the container was stopped or got killed prematurely. The docker stop command first sends a TERM signal, but the default is to only wait 10 seconds and then KILL. Rsyslog may need more time to sync data to disk or forward ouput. Therefore, tune the `--time` option for the stop command.

Stopping the container should allow the entry point script to execute `kill -SIGTERM $(cat /var/run/rsyslogd.pid)` so that rsyslog closes files and stops cleanly.

If you see `ERROR: Ungraceful exit...`, then most likely, the rsyslogd process died/aborted somehow.

## Environment variables that manage and wrap rsyslog configuration

Reading the `ENV rsyslog_*` optons in the `Dockerfile` should make it obvious about what rsyslog configuration options are supported via environment variables.

`rsyslog` is a traditional UNIX-like application not written with micro-services and container architecture in mind. It has many complex configuration options and syntax not easily managed as environment variables or command switches. Only a few common configuration scenarios are catered for as environment variables. See 'Optional config file volumes' to handle more complex cases.

_NB!_: Watch out for rsyslog configuration with arrays and docker's `env_file` handling

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

## Volumes and files the container requires

The container will use the following for rsyslog's "working" directory and is needed to recreate a container without losing data from previous runs:

### Volume for rsyslog TLS X509 certificate and private key

The container expects the following in order to use TLS/SSL:

- `/etc/pki/rsyslog/cert.pem`
- `/etc/pki/rsyslog/key.pem`

If not provided with valid files in those volumes, a default signed cert is used, but this will obviously work poorly for clients validating the server cert. It's only for testing.

- `/var/lib/rsyslog`

### Volume for rsyslog output files

If enabling and using file output, a named volume is recommended for `/var/log/remote`. E.g, on my docker setup, the files get written out the hosts named docker volume storage at `/var/lib/docker/volumes/syslog_log/_data/<hostname>`. Instead of logging all events to a single file, this can be split further into `<hostname>/<filename based on facility or message content>`:

| Filename | Use | Filter |
| - | - | - |
| messages | | Everything not sent to facilities auth, authpriv and 13 |
| security | Operating system security messages | auth and authpriv facilities |
| audit | Linux kernel auditing? | facility 13 |
| firewall | Firewall execution actions | From Kernel facility and starting with keyworlds that common firewall messages use |
| console | Alert messages usually broadcast on the console | facility 14 |

The default traditional file output template applied is, but it can be modified to something better like `RSYSLOG_SyslogProtocol23Format` (RFC5424) or any other [built-in rsyslog templates](http://www.rsyslog.com/doc/v8-stable/configuration/templates.html#reserved-template-names) via the `rsyslog_omfile_template` env var.

### Optional config file volumes

For more advanced custom configuration, template config via env vars would be too tedious (given RainerScript and rsyslog options are so vast), so dedicated configuration file volumes can be used instead for custom filering or output in the folling sub-directories:

- `/etc/rsyslog.d/input/filters`
- `/etc/rsyslog.d/output/filters`
- `/etc/rsyslog.d/output/extra`

Placing a `*.conf` in the `input/filters` or `output/filters` sub-directory is included and applied globally to either (to all of) the inputs or outputs. Per-input, or per-output filters can also be included in additonal sub-directories named the same as the respective ruleset. E.g.
- `/etc/rsyslog.d/input/filters/remote_in_udp/*.conf` will _only_ apply to the `remote_in_udp` ruleset.
- `/etc/rsyslog.d/output/filters/fwd_syslog/*.conf` will _only_ apply to the `fwd_syslog` ruleset.

When including filters, the filters need to make use of conditional expressions to match and then discard the unwanted message with the `stop` keyword.

Example of a simple black-list (exclude) approach:

```
if $fromhost-ip == '192.168.0.1' then { stop }
```

Example of a white-list approach:

```
if (
  $syslogfacility == '4' or
  $syslogfacility == '10' or
  $syslogfacility == '13' or
  $syslogfacility == '14'
) then { continue } else { stop }
```

Including extra outputs is _Experimental (not tested)_

## Optional Output Modules

Pre-defined support for some common forwarding use cases:
- Kafka (JSON output, can be changed)
- syslog forwarding / relay (RFC5424 output, can be changed)
- JSON forwarding / relay (A few pre-canned JSON templates supplied)

### Kafka Output

The Kafka output wraps the key config items for [omkafka](http://www.rsyslog.com/doc/master/configuration/modules/omkafka.html) so refer to RSyslog's documentation and look out for `rsyslog_omkafka` related `ENV` instructions in the `Dockerfile` to get a sense of options that can be set.

### Extra Output Modules

_Experimental : not tested_

If a forwarding use case isn't covered as above, then:
1. Set `rsyslog_forward_extra_enabled=true`
1. Use `/etc/rsyslog.d/output/extra` with your own config file which must specify `rsyslog_forward_extra` (See `50-ruleset.conf` that expects to call this ruleset).

E.g. `/etc/rsyslog.d/output/extra/mongo.conf`

```
module(load="ommongodb")
ruleset(name="forward_ommongodb")
{
  action(
    server="mymonddb"
    serverport=27017
    ...
  )
}
```

## Template examples

For each pre-canned output, a template can be set (i.e. `grep -E 'rsyslog_.*__template' Dockerfile` to get an idea of default templates used).

By default `rsyslog_support_metadata_formats` and `rsyslog_mmpstrucdata` options are off. They can help add meta-data and make structured data elements parsable as JSON. For JSON output, recommended combinations are:
- `TmplJSON` and `rsyslog_support_metadata_formats=off`, or
- `TmplJSONRawMeta` or `TmplRFC5424Meta` require `rsyslog_support_metadata_formats=on`, otherwise these templates won't work.

The table shows compatible template and options.

| Templates | Use | rsyslog_support_metadata_formats | rsyslog_mmpstrucdata |
| - | - | - | - |
| `TmplRFC5424` | RFC5424 (same as `RSYSLOG_SyslogProtocol23Format`) | NA, omitted | NA, not a JSON format |
| `TmplRFC5424Meta` | RFC5424 with extra structured meta-data element | Yes, prepended to SD-Elements | NA, not a JSON format |
| `TmplRSyslogJSON` | RSyslog's internal JSON representation | Yes, appears in `$!` root object | Yes, adds `rfc5424-sd` to `$!` |
| `TmplJSON` | Simplified smaller JSON message | No, omits fields for meta-data | Yes |
| `TmplJSONRawMeta` | More complete well structured JSON message | Yes, appears in `syslog-relay` object | Yes, replaces `structured-data` field with JSON object |

`rsyslog_support_metadata_formats` is also needed add logic that builds in some extra validation steps in order to output the meta-data with more accurate information about the origin of the message. RSyslog readily parses almost any valid text as a hostname with RFC3164, even when the message looks like it's ignoring the conventions and it's unlikely a valid hostname - as per this issue: [pmrfc3164 blindly swallows the first word of an invalid syslog header as the hostname](https://github.com/rsyslog/rsyslog/issues/1789).

Refer to `etc/confd/templates/60-output_format.conf.tmpl` and `https://github.com/JPvRiel/docker-rsyslog/blob/master/README_related.md#rsyslog-meta-data` for more details and motivation behind this feature.

The following template output examples are based on enabling these extra features:

```
rsyslog_support_metadata_formats=on
rsyslog_mmpstrucdata=on
```

### TmplRFC5424Meta

Meta-data about message origin pre-pended to the structured data element list:

```
<14>1 2017-09-19T23:43:29+00:00 behave test - - [syslog-relay@16543 timegenerated="2017-10-24T00:43:55.323108+00:00" fromhost="dockerrsyslog_sut_run_1.dockerrsyslog_default" fromhost-ip="172.18.0.9" myhostname="test_syslog_server" inputname="imptcp" format="RFC5424" pri-valid="true" header-valid="true" tls="false" authenticated-client="false"][test@16543 key1="value1" key2="value2"] Well formed RFC5424 with structured data
```

### TmplJSON

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

### TmplJSONRawMeta

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

### TmplRSyslogJSON

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

# Build

## Makefile Build

If your user has docker socket permissions, e.g.:

```
make build
```

Else if you need to elevate privilege, e.g.:

```
sudo -E make build
```

Where `-E` helps pass on `http_proxy` env vars, etc.

The build argument `DISABLE_YUM_MIRROR=true` can help if you have a caching proxy (e.g. squid) and don't want the mirror selection process in yum to break proxy caching. However, if default mirrors are down, then build fails.

Changes to `build.env` should invalidate the build cache. Docker build caching for a given version and release number.

## Manual Build Examples

The tagging convention followed is to match the `RSYSLOG_VERSION` to the version of rsyslogd the container is based on and add a release number thereafter. This is manually set to reflect the upstream stable RPM release. E.g. `export RSYSLOG_VERSION=8.30.0`

Build command example:

```bash
docker build -t jpvriel/rsyslog:${RSYSLOG_VERSION}-1 -t jpvriel/rsyslog:latest .
```

Building from behind a caching proxy (assuming proxy env vars are appropriately set) when you don't want yum mirror plug-ins to invalidate your proxy cache:

```bash
sudo -E docker build --build-arg DISABLE_YUM_MIRROR=true --build-arg http_proxy=$http_proxy --build-arg https_proxy=$https_proxy --build-arg no_proxy=$no_proxy -t jpvriel/rsyslog:${RSYSLOG_VERSION}-1 -t jpvriel/rsyslog:latest .
```

## Pre-bundled X509 test certificate and private key

Note, a pre-bundled self-signed cert and ca is used for test purposes. It is expected in the following places:

- key: `/usr/local/etc/pki/test/test_syslog_server.key.pem`
- cert: `/usr/local/etc/pki/test/test_syslog_server.cert.pem`

The default certs are generated via `./util/certs.sh` to work for the `sut` test suite.

To embed an internal/extra org CA, add more files to `etc/pki/ca-trust/source/anchors` and rebuild.

## Embed own CA certs for TLS

Note, there is a runtime `rsyslog_global_ca_file` env var to set the CA for rsyslog.

However, should you need to embed a CA for other reasons (e.g. building via a corporate TLS intercepting proxy), you embed your own CA at build time by placing your own CA certificates in `etc/pki/ca-trust/source/anchors`.

## System Under Test (SUT)

Follows docker convention to use an `sut` service to test. Depends on several other containers like `zookeeper` and `kafka` images in order to test component intergeneration (e.g. `omkafka`).

### Makefile Test

Similar to build, e.g.:

```
sudo -E make test
```

If the test fails, make aborts and the test containers are not cleaned up which allows investigating the failure. If successful, the test environment is torn down. Also, `make test_clean` is run before testing to ensure a previous failed test run doesn't interfere.

### Manually Invoking Tests

The "system under test" suite was written with python behave.

To build just the `sut` service:

```
docker-compose -f docker-compose.test.yml build sut
```

Reminder, use `--build-arg http_proxy` etc if you have to do this via a proxy.

Run the full test suite to regression test:

```
docker-compose -f docker-compose.test.yml run sut
```

If you're extending, run just `@wip` pieces to focus on new features:

```
docker-compose -f docker-compose.test.yml run sut behave -w behave/features
```

To see interplay between other test container dependencies and the syslog server container:

```
docker-compose -f docker-compose.test.yml up
```

The above will have a lot of output... An alternative is to look at `docker logs <service name>`

Cleanup:

```
docker-compose -f docker-compose.test.yml down -v
```

_N.B.!_: failing to cleanup causes stale volumes and test components which search those volumes could operate off stale test values! Always clean between tests.

### Building test dependencies

Assuming a corporate proxy and wanting to avoid yum mirror list breaking upstream proxy caching, centos test client:

```
docker-compose -f docker-compose.test.yml build --build-arg DISABLE_YUM_MIRROR=true --build-arg http_proxy=$http_proxy --build-arg https_proxy=$https_proxy --build-arg no_proxy=$no_proxy test_syslog_client_centos7
```

Ubuntu test client:

```
docker-compose -f docker-compose.test.yml build --build-arg http_proxy=$http_proxy --build-arg https_proxy=$https_proxy --build-arg no_proxy=$no_proxy test_syslog_client_ubuntu1604
```

There are also standard logstash, kafka and zookeeper images needed for testing.

# Debug and additional validation steps

## Configuration validation

Configuration passing mistakes and issues are all too common with rsyslog.

The entry-point script always validates config by default (Implicit config check). An explicit check can be done by using `-N1`. And a special python script assembles and outputs the full rsyslog configuration if you use `-E`. For example:

```
docker container run --rm -it \
 -v syslog_log:/var/log/remote \
 -v syslog_work:/var/lib/rsyslog \
 -v syslog_tls:/etc/pki/rsyslog \
 -e rsyslog_omfile_enabled=true \
 --name syslog jpvriel/rsyslog:latest -E
```

Output will have `##` comment tags to help highlight and show when `$IncludeConfig` directives are expanded to produce a flattened config output with line number prefixes:

```
12: $IncludeConfig /etc/rsyslog.d/*.conf
##< start of include directive: $IncludeConfig /etc/rsyslog.d/*.conf
##^ expanding file: /etc/rsyslog.d/30-globals.conf
 1: # Collect stats
 2: module(load="impstats" interval="300" log.syslog="on")
...
##> end of expand directive: $IncludeConfig /etc/rsyslog.d/*.conf
```

This helps track back to the exact line number of config that rsyslogd had a problem with, which is otherwise non-trivial due to the use of the confd and golang text template pre-processing needed to map environment variables into the config files.

## Checking for file output

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

```
logger -d -n 172.17.0.3 'Test UDP message'
```

Check the output file

```
$ sudo tail /var/lib/docker/volumes/syslog_log/_data/udp/5424/$(hostname)/messages | grep --color -E 'Test UDP message|$'
```

## Advanced debugging

One may want to debug the entry point script `entrypoint.sh`, `rsyslogd`, or both.

RSyslog depends on a command line flag `-d` or the `RSYSLOG_DEBUG` environment variables being set in order to debug. See [Rsyslog Debug Support](http://www.rsyslog.com/doc/master/troubleshooting/debug.html).

Enabling debug has performance implications and is probably NOT appropriate for production. Debug flags for rsyslogd does not affect entrypoint script debugging. To make the entrypoint script be verbose about shell commands run, use `ENTRYPOINT_DEBUG=true`.

```bash
docker container run --rm -it \
 -v syslog_log:/var/log/remote \
 -v syslog_work:/var/lib/rsyslog \
 -v syslog_tls:/etc/pki/rsyslog \
 --name syslog jpvriel/rsyslog:latest rsyslogd -d
```

Alternatively, to run with rsyslogd debug enabled but silent until signaled (via `SIGUSR1`), add `-e RSYSLOG_DEBUG=DebugOnDemand`.

To trigger debug output, send the container a signal (which `entrypoint.sh` entrypoint passes on to rsyslogd)

```
docker container kill --signal=SIGUSR1 syslog
```

Sometimes you may need to debug within the container, e.g. when it doesn't even make it past configuration.

Override the entrypoint or use exec on a running container.

E.g. override entrypoint:

```
docker container run --rm -it \
 -v syslog_log:/var/log/remote \
 -v syslog_work:/var/lib/rsyslog \
 -v syslog_tls:/etc/pki/rsyslog \
 --name syslog --entrypoint /bin/bash jpvriel/rsyslog:latest
```

Then run the init script manually to see if there are problems:

```
ENTRYPOINT_DEBUG=true /usr/local/bin/entrypoint.sh
```

E.g. or exec on an already running container

```
docker container exec -it syslog /bin/bash
```

## Debugging a work in progress (WIP) test case

When you just run `sut` via compose, the output from other containers is hard to see.

Some advice here is:

- Set `RSYSLOG_DEBUG: 'Debug'` for the `test_syslog_server` in `docker-compose.test.yml`.
- Execute `docker-compose -f docker-compose.test.yml run sut behave -w behave/features`.
- Run `docker logs dockerrsyslog_test_syslog_server_` to see the debug output.
- Use `docker-compose -f docker-compose.test.yml down` and `docker system prune --filter 'dangling=true'` between test runs to ensure you don't end up searching on log files within volume data for previous test runs...

You may need to adapt according to how dockerd logging is configured.

# Known limitations

## TLS/SSL config

RSyslog appears to use GNU TLS and TLS libraries in ways which don't readily allow TLS client authentication to be optionally set.

For `imtcp`:

- TLS settings apply globally to all inputs.
- Use `imptcp` (a different TCP input module) as a workaround for insecure TCP input.

For `imrelp`:

- TLS settings can apply per input.
- While there's no documented setting for optional TLS client authentication, it is possible to have two listeners on two different ports, one allowing anonymous clients, and a 2nd requiring client certificates

## Legacy formats

RFC3164 and the legacy file output format of many Linux distro's and *nixes does not include the year, sub-second accuracy, timezone, etc. Since it's still somewhat common to expect files in this format, the file output rsyslog_omfile_template defaults to `RSYSLOG_TraditionalFileFormat`. This can help with other logging agents that anticipate these old formats and cannot handle the newer formats.

The other forwarding/relay outputs default to using more modern RFC5424 or JSON formats.

rsyslog can accept and convert RFC3164 legacy input, but with some conversion caveats, such as guessing the timezone of the client matches that of the server, and lazy messages without conventional syslog headers are poorly assumed to map into host and process name fields.

# Status

Done:
- Multiple inputs
- File output
- Using confd to template config via env vars
- Add metadata to a message about peer connection (helps with provenance) - avoid spoofed syslog messages, or bad info from poorly configured clients.
- Structured data as JSON fields (mmstructdata, with null case)
- Gracefull entrypoint script exit and debugging by passing signals to rsyslogd.
- Kafka and syslog forwarding.
- JSON output
- Filtering

Not yet done:
- Re-factor test suite
  - Simplify and depend on less containers one async support in behave allows better network test cases (using tmpfs shared volumes is the current work-arround)
  - Watch out for pre-existing files in volumes from prior runs (testing via Makefile avoids this pitfall)
- More rsyslog -> kafka optimisation, e.g. see: [How TrueCar Uses Kafka for High Volume Logging Part 2](https://www.drivenbycode.com/how-truecar-uses-kafka-for-high-volume-logging-part-2/)

Maybe someday:
- Filter/send rsyslog performance metrics to stdout (omstdout)
- All syslog output to omstdout (would we even need this?)
- More test cases
  - Unit test for stopping and starting the server container to check that persistent queues in /var/lib/rsyslog function as intended
  - Older and other syslog demons as clients, e.g. from centos6, syslog-ng, etc
