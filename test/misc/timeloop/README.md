# Test TZ timezone env var and time system call impact

Understand if and how `TZ` might affect rsyslog and compare C and C++ performance.

The key observation was glibc `localtime()` does suffer in a container, but rsyslog doesn't use it and is likely not impacted by reliance on `gettimeofday()` instead.

## Test

Compare using `TZ`:

```shell
$ docker run -it --rm -e TZ='Africa/Johannesburg' --name test_timeloop test_timeloop
...
Begin time loop func localtime() calls with with 1000000 itterations!
Ended the time loop

real	0m0.213s
user	0m0.213s
sys	0m0.000s
```

versus not setting it:

```shell
$ docker run -it --rm --name test_timeloop test_timeloop
Begin time loop func localtime() calls with with 1000000 itterations!
Ended the time loop

real	0m1.720s
user	0m0.244s
sys	0m1.475s
```

## timeloop usage

Test the impact of syst time calls, E.g.:

- `timeloop none 10000` : no time function called, just loop
- `timeloop localtime 10000` : C stdlib.h `locatime()`
- `timeloop gettimeofday 10000` : C POSIX sys/time.h `gettimeofday()`

## Background

[How setting the TZ environment variable avoids thousands of system calls][] suggests setting `TZ` might benfit system time call performance overhead.

> To avoid extra system calls on server processes where you won’t be updating the timezone (or can restart processes when you do) simply set the TZ environment variable

Im summary:

- `time()` is a vDSO system call that's optimised to avoid needing a kernel context switch from userspace.
  - `time()` returns the number of seconds since the Epoch, 1970-01-01 00:00:00 +0000 (UTC) and can save the value in a memory pointer.
- `localtime()` is a glibc function call that uses `time()` and outputs the time in the local time.
  - `localtime()` will repeatidly use a stat system call to check `/etc/localtime` if `TZ` is not set.
  - `stat` system calls are used when `TZ` is not set.
  - `stat` is not a vDSO call and causes a context switch.

Note, rsyslog `imudp` has an `TimeRequery` parameter as per the docs: [imudp module parameters][].

> This is a performance optimization. Getting the system time is very costly. With this setting, imudp can be instructed to obtain the precise time only once every n-times. This logic is only activated if messages come in at a very fast rate, so doing less frequent time calls should usually be acceptable.

...

> Note: the timeRequery is done based on executed system calls (not messages received). So when batch sizes are used, multiple messages are received with one system call. All of these messages always receive the same timestamp, as they are effectively received at the same time.

## Code examples

### C stdlib `time()` and `localtime()`

As per [How setting the TZ environment variable avoids thousands of system calls][], the core loop has this:

```c
time(&timep);
localtime(&timep);
```

### C++ timedate getCurrTime() used by rsyslog imudp

The rsyslog UDP module uses `datetime.getCurrTime()` in it's core loop. A variable, `iTimeRequery`, set via the `TimeRequery` module parameter, skips n loop iterations with modulous operator. See: [imudp module time function call][]:

```c++
if((runModConf->iTimeRequery == 0) || (iNbrTimeUsed++ % runModConf->iTimeRequery) == 0) {
    datetime.getCurrTime(&stTime, &ttGenTime, TIME_IN_LOCALTIME);
}
```

`"datetime.h"` is inlcuded for imudp source code and the [rsyslog `datetime.getCurrTime()` function] impliments the following for Linux:

```c++
gettimeofday(&tp, NULL);
```

[How setting the TZ environment variable avoids thousands of system calls]: https://blog.packagecloud.io/eng/2017/02/21/set-environment-variable-save-thousands-of-system-calls/
[imudp module parameters]: https://rsyslog.readthedocs.io/en/stable/configuration/modules/imudp.html#module-parameters
[imudp module time function call]: https://github.com/rsyslog/rsyslog/blob/0a1b740e94ddb2b8be3b77ca6f798dc49f026c95/plugins/imudp/imudp.c#L538
[rsyslog `datetime.getCurrTime()` function]: https://github.com/rsyslog/rsyslog/blob/0a1b740e94ddb2b8be3b77ca6f798dc49f026c95/runtime/datetime.c#L172
