# Overview

An RSyslog container able to:

- Accept multiple syslog input formats (RFC3164 and RFC5424).
- Accept multiple transports (UDP, TCP or RELP).
- Accept multiple security options (TLS or not).
- Optionally append useful metadata.
- File output to a volume.
- Forward the messages to other systems, either:

  - Downstream syslog servers (e.g. traditional/legacy SIEM).
  - Kafka (e.g. data analytic platforms like Hadoop).

The container also supports advanced debug scenarios.

# Usage

## Runtime

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
docker volume create syslog_spool
docker volume create syslog_tls
```

Provide 3 files for TLS setup placed in the `syslog_tls` and mounted as a volume at `/etc/pki/tls/rsyslog`:

- a `key.pem`,
- a signed certificate, `cert.pem`, and
- your own trusted CA, e.g. `ca.pem`
(file names can be modified via ENV vars at runtime if need be)

Run docker mounting volumes

```bash
docker container run --rm -it \
 -v syslog_log:/var/log/remote \
 -v syslog_spool:/var/spool/rsyslog \
 -v syslog_tls:/etc/pki/tls/rsyslog \
 --name syslog jpvriel/rsyslog:latest
```

### Compose way

TODO

## Gracefully stopping the container (and rsyslog process)

As per `man rsyslogd`, the daemon process responds to various signals. The `rsyslog.sh` entry-point script has handlers to pass these along provided the container is stopped as follows:

```bash
docker container stop -t 300 syslog
```

Notice the example has 300 seconds (5 minutes grace) to allow rsyslog to stop gracefully.

If you DON'T see `INFO: rsyslog stopped normally`, then you know the container was stopped or got killed prematurely. The docker stop command first sends a TERM signal, but the default is to only wait 10 seconds and then KILL. Rsyslog may need more time to sync data to disk or forward ouput. Therefore, tune the `--time` option for the stop command.

Stopping the container should allow the entry point script to execute `kill -SIGTERM $(cat /var/run/rsyslogd.pid)` so that rsyslog closes files and stops cleanly.

If you see `ERROR: Ungraceful exit...`, then most likely, the rsyslogd process died/aborted somehow.

## Managing Rsyslog Configuration Options Dynamically

See the `ENV` options in the Dockerfile defined with `rsyslog_*` which need to be set according to your own use case.

Note, `rsyslog` is a traditional UNIX-like application not written with micro-services and container architecture in mind. It has many complex configuration options and syntax not easily managed as environment variables or command switches.

## Volumes and files the container requires

The container expects the following in order to use TLS/SSL:

- `/etc/pki/rsyslog/cert.pem`
- `/etc/pki/rsyslog/key.pem`

If not provided with valid files in those volumes, a default signed cert is used, but this will obviously work poorly for clients validating the server cert.

The container will use the following for RSyslog to operate gracefully (recreate a container without losing data)
- `/var/spool/rsyslog`

If enabling and using file output, a named volume is recommended for `/var/log/remote`. E.g, on my docker setup, the files get written out the hosts docker volume storage like this `/var/lib/docker/volumes/syslog_log/_data/tcp_secure/rfc5424/<hostname>`. Sub folders help distinguish and split the syslog collection methods (UDP vs TCP vs secure or not, etc).

### Optional config file volumes

For more advanced custom configuration, template config via env vars would be too tedious (given RainerScript and rsyslog options are so vast), so dedicated configuration file volumes can be used instead for custom filering or output in the folling sub-folders:

- `/etc/rsyslog.d/filter`
- `/etc/rsyslog.d/output/extra`

## Build

A pre-requisit is to create your own self-signed cert for default/test purposes expected in the following places:

- key: `etc/pki/tls/private/default_self_signed.key.pem`
- cert: `etc/pki/tls/certs/default_self_signed.cert.pem`

As a convenience, run the following form the base repo folder (in bash):

```bash
./util/self_signed_cert.sh test_syslog
```

To embed an internal/extra org CA, add more files to `etc/pki/ca-trust/source/anchors` and rebuild

Build command example

```bash
docker build -t jpvriel/rsyslog:0.0.8 -t jpvriel/rsyslog:latest .
```

Building from behind a proxy (assuming proxy env vars are appropriately set)

```bash
sudo -E docker build --build-arg http_proxy=$http_proxy --build-arg https_proxy=$https_proxy --build-arg no_proxy=$no_proxy -t jpvriel/rsyslog:0.0.8 -t jpvriel/rsyslog:latest .
```

## Debug and validation steps

### Checking for file output

One basic ways to see if the rsyslog container works is to run it with file output enabled  and written out to a named volume.

Assuming a suitable volume is created, e.g. `docker volume create syslog_log`, run the container with the volume and `-e rsyslog_omfile_enabled=true`.

```bash
docker container run --rm -it \
 -v syslog_log:/var/log/remote \
 -v syslog_spool:/var/spool/rsyslog \
 -v syslog_tls:/etc/pki/tls/rsyslog \
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
 -v syslog_spool:/var/spool/rsyslog \
 -v syslog_tls:/etc/pki/tls/rsyslog \
 --name syslog jpvriel/rsyslog:latest rsyslogd -d
```

Alternatively, to run with rsyslogd debug enabled but silent until signaled (via `SIGUSR1`)

```
docker container run --rm -it \
 -v syslog_log:/var/log/remote \
 -v syslog_spool:/var/spool/rsyslog \
 -v syslog_tls:/etc/pki/tls/rsyslog \
 --name syslog jpvriel/rsyslog:latest
```

Set env to `DEBUG=true` if working on problems with the `rsyslog.sh` entrypoint script. This will also set `RSYSLOG_DEBUG=DebugOnDemand` so that `SIGUSR1` signals can toggle rsyslogd debugging as need be. E.g.

```
docker container run --rm -it \
 -v syslog_log:/var/log/remote \
 -v syslog_spool:/var/spool/rsyslog \
 -v syslog_tls:/etc/pki/tls/rsyslog \
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
 -v syslog_spool:/var/spool/rsyslog \
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

## RFC3164 legacy format ouptut not supported

While RFC3164 is the native output format of many Linux distro's and *nixes, it's a poor logging format (no year, sub-second accuracy, timezone, etc). Therefore not supported as output. The config defaults to using more modern RFC5424 or JSON formats.

Note however, rsyslog can still accept and convert RFC3164 legacy input, but with some conversion caveats, such as guessing the timezone of the client matches that of the server.

# Status

Done:

- Multiple inputs
- File output
- Using confd to template config via env vars
- First attempt to add metadata to a message about peer connection (helps with provenance) - avoid spoofed syslog messages, or bad info from poorly configured clients.
- Gracefull entrypoint script exit and debugging by passing signals to rsyslogd.

Not yet done:

- Kafka and syslog forwarding. Kafka output considerations incomplete.
- Build test suites (try use python behave framework).
- JSON output
