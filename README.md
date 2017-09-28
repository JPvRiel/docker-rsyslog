# Overview

An RSyslog container able to:

- Accept multiple syslog input formats (RFC3164 and RFC5424).
- Accept multiple transports (UDP, TCP or RELP).
- Accept multiple security options (TLS or not).
- Optionally append useful metadata.
- Split and output files to a volume.
- Forward the messages to other systems for a few built-in use cases, either:

  - Downstream syslog servers expecting RFC3164 or RFC5424 (e.g. a SIEM product).
  - Downstream analytic tools that can handle JSON (e.g. logstash).
  - Kafka (e.g. data analytic platforms like Hadoop).

- Allow logging rule-set extension via volume mounts with user provided configuration files (e.g. for custom filters and outputs)

The container also supports advanced debug scenarios.

# Version

The convention is `<rsyslogd version>-<docker image release build number>`.

E.g. `8.29.0-3` means the output of `rsyslogd -v` shows `rsyslogd 8.16.0`, and it's the 3rd image released for that upstream version.

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

Run docker mounting volumes

```bash
docker container run --rm -it \
 -v syslog_log:/var/log/remote \
 -v syslog_work:/var/lib/rsyslog \
 -v syslog_tls:/etc/pki/rsyslog \
 --name syslog jpvriel/rsyslog:latest
```

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

As per `man rsyslogd`, the daemon process responds to various signals. The `rsyslog.sh` entry-point script has handlers to pass these along provided the container is stopped as follows:

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
  - [Inconsistent env var parsing from docker-compose.yml](https://github.com/docker/compose/issues/2854)
  - [strange interpretation/parsing of .env file](https://github.com/docker/compose/issues/3702)

## Volumes and files the container requires

The container will use the following for rsyslog's "working" directory and is needed to recreate a container without losing data from previous runs:

### Volume for rsyslog TLS X509 certificate and private key

The container expects the following in order to use TLS/SSL:

- `/etc/pki/rsyslog/cert.pem`
- `/etc/pki/rsyslog/key.pem`

If not provided with valid files in those volumes, a default signed cert is used, but this will obviously work poorly for clients validating the server cert. It's only for testing.

- `/var/lib/rsyslog`

### Volume for rsyslog output files

If enabling and using file output, a named volume is recommended for `/var/log/remote`. E.g, on my docker setup, the files get written out the hosts docker volume storage at `/var/lib/docker/volumes/syslog_log/_data/<transport>/<hostname>` where sub-directories help distinguish and split the syslog collection methods (UDP vs TCP vs secure or not, etc) and hosts. `<transport>` can be `udp`, `tcp`, `tcp_secure`, `relp` and `relp_secure`. The files within each directory are split further into:

| Filename | Use | Filter |
| - | - | - |
| messages | | Everything not sent to facilities auth, authpriv and 13 |
| security | Operating system security messages | auth and authpriv facilities |
| audit | Linux kernel auditing? | facility 13 |
| firewall | Firewall execution actions | From Kernel facility and starting with keyworlds that common firewall messages use |
| console | Alert messages usually broadcast on the console | facility 14 |

The default traditional file output template applied is, but it can be modified to something better like `RSYSLOG_SyslogProtocol23Format` (RFC5424) via the `rsyslog_omfile_template` env var.

### Optional config file volumes

For more advanced custom configuration, template config via env vars would be too tedious (given RainerScript and rsyslog options are so vast), so dedicated configuration file volumes can be used instead for custom filering or output in the folling sub-folders:

- `/etc/rsyslog.d/filter`
- `/etc/rsyslog.d/output/extra`

## Optional Output Modules

Pre-defined support for some common forwarding use cases:
- kafka
- syslog forwarding / relay
- JSON forwarding / relay

### Kafka Output

### Extra Output Modules

If a forwarding use case isn't covered as above, then
1. Set `rsyslog_forward_extra_enabled=true`
1. Use `/etc/rsyslog.d/output/extra` with your own config file which must specify `rsyslog_forward_extra` (See `50-ruleset.conf` that expects to call this ruleset).

E.g. `/etc/rsyslog.d/output/extra/mongo.conf`

```
module(load="ommongodb")
ruleset(name="forward_kafka")
{
  action(
    server="mymonddb"
    serverport=27017
    ...
  )
}
```

# Build

Match the `rsyslog_version` to the version of rsyslogd the container is based on.

Build command example

```bash
docker build -t jpvriel/rsyslog:$rsyslog_version -t jpvriel/rsyslog:latest .
```

Building from behind a caching proxy (assuming proxy env vars are appropriately set) when you don't want yum mirror plug-ins to invalidate your proxy cache:

```bash
sudo -E docker build --build-arg DISABLE_YUM_MIRROR=true --build-arg http_proxy=$http_proxy --build-arg https_proxy=$https_proxy --build-arg no_proxy=$no_proxy -t jpvriel/rsyslog:$rsyslog_version -t jpvriel/rsyslog:latest .
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

## SUT test suite

The "system under test" suite was written with python behave.

To build just the `sut` service:

```
docker-compose -f docker-compose.test.yml build sut
```

Use `--build-arg http_proxy=$http_proxy` etc if you have to do this via a corporate proxy.

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

cleanup

```
docker-compose -f docker-compose.test.yml down
docker-compose -f docker-compose.test.yml rm
```

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

### Checking for file output

One basic ways to see if the rsyslog container works is to run it with file output enabled  and written out to a named volume.

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

### Advanced debugging

One may want to debug the entry point script `rsyslog.sh`, `rsyslogd`, or both.

RSyslog depends on a command line flag `-d` or the `RSYSLOG_DEBUG` environment variables being set in order to debug. Enabling debug has performance implications and is probably NOT appropriate for production.

Set debug flag for rsyslogd (does not affect entrypoint script debugging):

```bash
docker container run --rm -it \
 -v syslog_log:/var/log/remote \
 -v syslog_work:/var/lib/rsyslog \
 -v syslog_tls:/etc/pki/rsyslog \
 --name syslog jpvriel/rsyslog:latest rsyslogd -d
```

Alternatively, to run with rsyslogd debug enabled but silent until signaled (via `SIGUSR1`)

```
docker container run --rm -it \
 -v syslog_log:/var/log/remote \
 -v syslog_work:/var/lib/rsyslog \
 -v syslog_tls:/etc/pki/rsyslog \
 --name syslog jpvriel/rsyslog:latest
```

Set env to `DEBUG=true` if working on problems with the `rsyslog.sh` entrypoint script. This will also set `RSYSLOG_DEBUG=DebugOnDemand` so that `SIGUSR1` signals can toggle rsyslogd debugging as need be. E.g.

```
docker container run --rm -it \
 -v syslog_log:/var/log/remote \
 -v syslog_work:/var/lib/rsyslog \
 -v syslog_tls:/etc/pki/rsyslog \
 -e DEBUG=true \
 --name syslog jpvriel/rsyslog:latest
```

Then send the container a signal (which `rsyslog.sh` entrypoint passes on to rsyslogd)

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
DEBUG=true /usr/local/bin/rsyslog.sh
```

E.g. or exec on an already running container

```
docker container exec -it syslog /bin/bash
```

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
- First attempt to add metadata to a message about peer connection (helps with provenance) - avoid spoofed syslog messages, or bad info from poorly configured clients.
- Gracefull entrypoint script exit and debugging by passing signals to rsyslogd.
- Kafka and syslog forwarding.
- JSON output

Not yet done:
- More test scenarios (only basics done thus far). No negative testing.
- Optimised config, e.g. see: [How TrueCar Uses Kafka for High Volume Logging Part 2](https://www.drivenbycode.com/how-truecar-uses-kafka-for-high-volume-logging-part-2/)

```
$PreserveFQDN on
$MaxMessageSize 64k
```

Maybe someday:
- Filter/send rsyslog performance metrics to stdout (omstdout)
- All syslog output to omstdout (would we even need this?)
- More test cases
  - Unit test for stopping and starting the server container to check that persistent queues in /var/lib/rsyslog function as intended
  - Older and other syslog demons as clients, e.g. from centos6, syslog-ng, etc
