# Notes, related work and references

## Upstream RSyslog repo with latest stable

[RHEL-CentOS RSyslog RPMs](http://www.rsyslog.com/rhelcentos-rpms/)

## Forwarding formats and RSyslog templates

When forwarding via syslog, RFC5424 is obviously the most sensible format to relay in. RFC3164 is not a proper standard and made poor choices with regard to the time-stamp convention. While "Mmm dd hh:mm:ss" is human readable, it lacks the year, sub-second accuracy and timezone info.

When forwarding to kafka, format choices are more complex:

- Forward in RFC5424 format and assume downstream system will parse and transform?
- Forward in JSON format?

  - Use RSyslog's own `template_StdJSONFmt` or the `jsonmesg` property?
  - Try replicate lumberjack/logstash default output JSON format based on the syslog input plug-ins for logstash? See:
    - [How to ship JSON logs via Rsyslog](https://techpunch.co.uk/development/how-to-shop-json-logs-via-rsyslog)
    - [Using rsyslog to send pre-formatted JSON to logstash](https://untergeek.com/2012/10/11/using-rsyslog-to-send-pre-formatted-json-to-logstash/)

The current choice is leaving the message in RFC5424 text format as the payload. TODO: If mapped to JSON, a full `raw` payload type field could be preserved in case downstream systems already expect raw syslog. Future work could consider more efficient encoded binary formats like [AVRO](http://avro.apache.org/).

## Rsyslog omkafka

<http://www.rsyslog.com/doc/master/configuration/modules/omkafka.html>

## Rsyslog into kafka and logstash

- <https://sematext.com/blog/2015/10/06/recipe-rsyslog-apache-kafka-logstash/>
- <https://www.drivenbycode.com/how-truecar-uses-kafka-for-high-volume-logging-part-2/>

## Rsyslog meta-data

As a use-case for provenance, the message's origin IP, DNS reverse lookup, and time received filed would be useful meta-data. Unfortunately, this doesn't seem to be well standardised, and in addition, it's not clearly documented if rsyslog has a property for the source system's client certificate.

Adding meta-data to every message can also increase per-message size with highly redundant data - e.g. an extra 200 bytes of structured data elements added to each message. This additional overhead can be justified if per message provenance is important. In addition, compression can help compensate.

### RFC5424 and structured data elements to add meta-data about an origin

Syslog RFC5424 allows for structured data elements (none or many). The standard already defines meta-data that can be added (Section 7 of RFC5424). Below is a quick summary of standard structured data elements:

origin:

- ip
- software
- swVersion

meta:

- sequenceId
- sysUpTime
- language

The 'origin' and 'meta' standard structured data elements don't cover the intended provenance use case fully. Both are client/log source/origin provided. E.g. the `ip` filed for origin can occur multiple times for all IP interfaces a given host had, but in a provenance use case, we want the server to note the IP the collector/syslog server received the message from.

See "6.3.5\. Examples" in the standard as a good point to jump into it. Basically, via an example:

Given no appropriate standard, a custom structured data element `rsyslog_relay@16543` can be pre-pended to include the following meta-data about how the log event was received:

| rsyslog property | Splunk CIM | Use |
| - | - | - |
| `inputname` | `app` | rsyslog input module used, e.g. imudp, imptcp, imtcp, imrelp, etc |
| `fromhost` | `src` | Source DNS or IP if reverse DNS lookup fails for the connected syslog client |
| `fromhost-ip ` | `src_ip` | Source IP of the connected syslog client |
| `$myhostname` | `dest` | Server instance processing the message |
| `timegenerated` | message_received_time | When the message was received |
| `protocol-version` | ?? | 1 if input conformed to RFC5424, or 0 if input was guessed to be RFC3164 |
| custom variable: $!tls | ?? | true/false flag for SSL/TLS |
| custom variable: $!authenticated_client | ?? | if client authentication was applied, i.e. the 'authMode' applied for SSL/TLS - limited to true/false |

When rsyslog doesn't have a property available, we can generate it with our own custom variables.

If rsyslog supported extracting properties from the input's TLS/SSL library, the authentication information such as the following could be included (but is not, given there are no such documented features in RSyslog):

- ssl_issuer_common_name:
- ssl_subject_common_name:
- ssl_serial:

Knowing which format the source message was in is complicated because rsyslog by default applies multiple parsers in a chain so that it can accept both RFC3164 and RFC5424 messages. [Syslog Parsing](http://rsyslog.readthedocs.io/en/latest/whitepapers/syslog_parsing.html) and [Message Parser](http://rsyslog.readthedocs.io/en/latest/concepts/messageparser.html) has more details. In summary, legacy syslog (3164) was never properly standardised. Any printable string is acceptable according to RFC3164, which is not an IETF standard, but just an informational document. So if there were a 'format' field to indicate the source type of message before attempting to store as RFC5424 with meta-data added, there are a number of scenarios for the format value that could be useful to try add as meta-data:

- rfc3164_unconventional
- rfc3164
- rfc5424
- rfc5424_malformed

'unconventional' indicates that something didn't respect the conventions laid out by section 5 of RFC3164.

_NB_: 'rfc5424_malformed' may not be possible given that if 5424 parsing fails, rsyslog next applies the 3164 parser, which accepts _any_ printable string. Given a 3164 message priority (e.g. `<177>`) doesn't have a version, and a 5424 message priority does (e.g. `<177>1`), it's possible to check RFC5424 conformance, except for a highly rare edge case of an unconventional 3164 message of "1 <some text>".

More specific parser should go earlier in the parser chain, and the default parser chain set is `rsyslog.rfc5424` and then `rsyslog.rfc3164`. Parser chains are applied after input modules.

Options of interest for the parsing:

- `force.tagEndingByColon`: deafult is off, but this can help avoid the case where a badly formated RFC3164 message doesn't tag properly and RSyslog incorrectly pulls out something that was not intended as a tag
- `remove.msgFirstSpace`

However, there inst any documented obvious property to indicate which parser was used. A workaround is using the `protocol-version` property.

The above helps establish a server perspective and view of the provenance/origin of a message. However, since syslog messages can be relayed, the information above is not complete provenance, just information about the peer.

TODO: Dealing with syslog relay scenarios is a future concern. Perpending more structured data elements for each relay won't work given "the same SD-ID MUST NOT exist more than once in a message" (as per the RFC), so it's not that simple. Structured data element fields can be duplicated, so perhaps by adding the sever (dest) name as a field helps and a known sequence of the same fields (structured data parameters) repeated and appended per relay could better establish a full chain of provenance. This might entail using the mmpstrucdata module to check for an existing data element at increased overhead...

Note further, templates are not affected by if-statements or config nesting.

If the structured data element follows Splunk CIM field names, the template string would be as follows:

```
[received@16543 message_received_time=\"%timegenerated:::date-rfc3339%\" src=\"%fromhost%\" src_ip=\"%fromhost-ip%\" dest=\"%$myhostname%\" app=\"rsyslog_%inputname%\" ssl=\"%$!tls%\" authenticated_client=\"%$!authenticated_client%\"]
```

However, elsewhere within the message from the client, information about the event might supersede fields such as src and dest.

If the structured data element follows rsyslogs default property names, the template string would be as follows:

```
[received@16543 timegenerated=\"%timegenerated:::date-rfc3339%\" fromhost=\"%fromhost%\" fromhost-ip=\"%fromhost-ip%\" myhostname=\"%$myhostname%\" inputname=\"%inputname%\" tls=\"%$!tls%\" authenticated_client=\"%$!authenticated_client%\"]
```


#### RFC3164 (legacy) converted to RFC5424 with meta-data pre-pended to structured data

RSyslog template string (see [Rsyslog examples](http://www.rsyslog.com/doc/rsyslog_conf_examples.html))
```
"<%PRI%>%TIMESTAMP% %HOSTNAME% %syslogtag%%msg%"
```

Example source RFC3164 message (obviously without meta-data) via UDP

```
<177>Jul 14 12:52:12 05766jpvanriel-vm test: FINDME using UDP from 127.0.0.1 to 127.0.0.1:514
```

After, with meta-data added

```
<177>1 2015-07-14T12:52:12 experience test - - - [received@16543 message_received_time="2017-07-18 12:52:13.116658983+02:00" src="experience.standardbank.co.za"
src_ip="196.8.110.47" dest="plogcs1p.standardbank.co.za" app="rsyslog_imudp" syslog_version="0" ssl="false"] FINDME using UDP from 127.0.0.1 to 127.0.0.1:514
```

#### RFC5424 (modern) converted with meta-data appended to structured data

RFC5424 message with an existing structured data element, but no meta-data added yet

```
<177>1 2015-07-14T12:52:12.916345047+02:00 05766jpvanriel-vm test - - - [testsd@16543 test_msg="RELP client with TLS"] FINDME using RELP from 127.0.0.1 to 127.0.0.1:514
```

After, RFC5424 message with meta-data prepended to the structured elements

```
<177>1 2015-07-14T12:52:12 test - - - [received@16543 message_received_time="2017-07-18 12:52:13.116658983+02:00" src="experience.standardbank.co.za"
src_ip="196.8.110.47" dest="plogcs1p.standardbank.co.za" app="rsyslog_imrelp" syslog_version="0" ssl="true" authentication_client="true"][testsd@16543 test_msg="RELP client with TLS"] FINDME using RELP from 127.0.0.1 to 127.0.0.1:514
```

Other interesting pre-defined structure data elements (IDs) are 'timeQuality', but the source needs to try populate this. To duplicate time quality data in every message would be overly redundant?

RSyslog allows for referencing properties. See [rsyslog Properties](http://www.rsyslog.com/doc/v8-stable/configuration/properties.html). Properties of interest are:

- Protocol version (only applicable to RFC5424)

  - protocol-version 1 (no obvious splunk CIM fieldname)

- Time when log was received

  - date-rfc3339
  - timegenerated (message_received_time)

- Log source/sender:

  - fromhost (src)
  - fromhost-ip (src_ip)

input module name

- inputname (app)

Splunk CIM is useful for field naming conventions when we add metadata. The [Protocols that map to Splunk CIM](https://docs.splunk.com/Documentation/StreamApp/7.1.1/DeployStreamApp/WhichprotocolsmaptoCIM) has a fuller listing of the Splunk CIM namespace accross multiple catagories ('Protocols').

## Realted docker examples

### RSyslog images

Changes needed for RHEL 7 default rsyslog config to be able to run in a container:
- http://www.projectatomic.io/blog/2014/09/running-syslog-within-a-docker-container/

On docker hub:

- 'rsyslog': <https://hub.docker.com/search/?isAutomated=0&isOfficial=0&page=1&pullCount=0&q=rsyslog&starCount=1>

Well matched examples for our use-case (specifically wanting to output to kafka)

- <https://github.com/tcnksm-sample/omkafka>
- <https://github.com/sergeevii123/joker.logs/blob/master/docker-rsyslog-kafka.yml>
- <https://github.com/djenriquez/rsyslog-omkafka>

Some of the above images are lightweight and expect a DIY config supplied by the user, e.g.:
- Don't define expected data volumes for rsyslog queues
- Don't have pre-defined inputs for various protocols like RELP and TLS options

Other examples (but no github source)

- <https://hub.docker.com/r/teamidefix/rsyslog-kafka-boshrelease-pipeline/>
- <https://hub.docker.com/r/teamidefix/rsyslog-modules-pipeline/>
- <https://hub.docker.com/r/birdben/rsyslog-kafka/>
- <http://www.simulmedia.com/blog/2016/02/19/centralized-docker-logging-with-rsyslog/>
- <http://www.projectatomic.io/blog/2014/09/running-syslog-within-a-docker-container/>

Almost suitable example for our use-case, but uses a lesser know/tested go syslog implementation:

- <https://hub.docker.com/r/elodina/syslog-kafka/>
- <https://github.com/elodina/syslog-kafka>

Other interesting examples

- <https://hub.docker.com/r/rafpe/docker-haproxy-rsyslog/>
- <https://hub.docker.com/r/voxxit/rsyslog/>
- <https://bosh.io/d/github.com/cloudfoundry/syslog-release>

Docker specific (not related to syslog/bypass, use kafka directly)

- <https://github.com/moby/moby/issues/21271>

## Container config methods

### Configuration file templates inside of a container

As per [Environment Variable Templating](http://steveadams.io/2016/08/18/Environment-Variable-Templates.html), it's a good idea to help legacy apps become container and micro-service friendlier by 'templating' configuration files. Some tools (in order of github popularity) to help with this are:

- [Confd](https://github.com/kelseyhightower/confd), uses Golang text/templates and TOML config files
- [dockerize](https://github.com/jwilder/dockerize), uses Golang text/templates
- [Tiller](https://github.com/markround/tiller), a ruby gem which presumably uses `ERB` and can support reading environment variables

Confd:

- <https://www.slideshare.net/m_richardson/bootstrapping-containers-with-confd>
- <http://www.mricho.com/confd-and-docker-separating-config-and-code-for-containers/>
- <https://theagileadmin.com/2015/11/12/templating-config-files-in-docker-containers/>

While rsyslog does have a `getenv` function built into it's config, it's usage seems limited.

See [Re: set config values from env var](https://lists.gt.net/rsyslog/users/21128#21128)

> no.
>
> there are ways to assign variables to be equal to environemnt variables with the set command, but those cannot be used for most config options.

In any even, something like confd has more flexibly for deployments that might use distributed config management and orchestration tools like etcd, zookeeper, etc.
