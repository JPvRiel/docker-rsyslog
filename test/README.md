# Extra testing notes

## Syslog test clients

The Ubuntu and CentOS Docker test images essentially run rsyslog with client config and use to send messages via the logger command to /dev/log and the rsyslog client listens to /dev/log via the imuxsock input, thereafter forwarding messages to 'test_syslog_server'.

CentsOS 7 client send via RELP without TLS

Ubuntu 16.04 client sends via RELP with TLS

By default, these test containers wait for a TERM signal and propagate that shut down rsyslog.

TODO: Queue feature testing between syslog client and server not done. Client queue config included as an example only for now.

## TLS Test cases

Uses a self-signed, which should be generated from the project repo's root directory

```bash
./util/self_signed_cert.sh test_syslog
```

The test container shares the same self-signed cert via symlinks to the self-signed certificate created as a default to allow simple client/sever authentication TLS test cases. Also does a recursive copy of `etc/pki/ca-trust...` anchors if need be.

### TLS with RELP

Requires rsyslogd >= 7.5

This won't be supported on older distributions.

- Earlier versions of CentOS 7 only shiped with rsyslogd 7.4.7.
- Ubuntu 16.04.3 ships with 8.16.0.

### Load testing

See [benchmark-syslog](https://github.com/JPvRiel/benchmark-syslog). It provides:

- `test_syslog.sh`, a bash script that can perform basic load testing against any environment that accepts plain TCP syslog or UDP.
- And a more complex benchmark suite to evaluate rsyslog options.
