# rsyslog performance testing

## netcat

netcat was used for basic dummy testing

Limitations noticed:

- `-u` for UDP mode as a server doesn't seem to handle packages from multiple clients
- `-q 1` for UDP mode is needed, otherwise client does not exit by itself

## Refrences

- [Tutorial: sending impstats metrics to elasticsearch using rulesets and queues](https://www.rsyslog.com/tutorial-sending-impstats-metrics-to-elasticsearch-using-rulesets-and-queues)
- [rsyslog high performance config example](https://www.rsyslog.com/doc/v8-stable/examples/high_performance.html)
- [iperf](https://github.com/esnet/iperf)
- [uperf github site](https://github.com/uperf/uperf) and [uperf.org](http://uperf.org/)