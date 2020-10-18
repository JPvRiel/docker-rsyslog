# Extra testing notes

## Retrospectively explore the `sut` container post exit

When a test fails, the `sut` container will exit with a non-zero return code leaving all other containers (test dependencies still running).

To inspect the state of an exited `sut` (python behave) container, commit the stopped container and run a shell within it mounting all the previous volumes it would have gotten via docker compose:

```bash
sudo docker commit docker-rsyslog_sut_run_1 debug/behave
sudo docker run -it --rm \
  -v "$(pwd)/test:/tmp/test" \
  -v docker-rsyslog_syslog_log:/var/log/remote:ro \
  -v docker-rsyslog_syslog_metrics:/var/log/impstats:ro \
  -v docker-rsyslog_syslog_relay:/tmp/syslog_relay:ro \
  -v docker-rsyslog_syslog_relay_udp_spoof:/tmp/syslog_relay_udp_spoof:ro \
  -v docker-rsyslog_json_relay:/tmp/json_relay:ro \
  debug/behave bash
```

Cleanup debug image:

```bash
sudo docker image rm debug/behave
```

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

### Relay testing

Sometimes it might be unclear why events are not being received by a syslog relay.

To inspect the state of a relay container, it's possible to `docker exec` and run a shell in the container. However, the shell within a base container is often very limited and lacks useful utilities a host OS might have like `netstat` or `lsof`. Instead, enter the containers process namespace from the host OS.

E.g. to run the host OS netstat command within the container's namespace:

```bash
pid=$(sudo docker inspect -f '{{.State.Pid}}' docker-rsyslog_test_syslog_relay_udp_spoof_1)
sudo nsenter -t $pid -a netstat -ln
```

E.g. to tail the output in the file:

```bash
sudo nsenter -t $pid -a tail /tmp/syslog_relay_udp_spoof/nc.out
```
