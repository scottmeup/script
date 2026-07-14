# autobrr IRC anti-flap watchdog

## Complete recursive project tree

```text
autobrr-irc-anti-flap/
├── README.md
├── autobrr-irc-anti-flap.env.example
├── autobrr-irc-anti-flap.service
├── autobrr-irc-anti-flap.sh
└── test-autobrr-irc-anti-flap.sh
```

## Primary goal and invariants

The primary goal is to prevent autobrr IRC connection flapping while maximizing uptime outside periods caused by an actual stop.

The implementation enforces these invariants:

1. The watchdog never starts autobrr unless it has observed autobrr stopped, created a full cooldown from that observation, and that cooldown has expired.
2. The watchdog never stops autobrr until the current run has reached the initialized state and a configured stop condition has been observed repeatedly.
3. A manual start during cooldown is left running. The watchdog does not stop it merely because the old cooldown remains recorded.
4. Every subsequent stop—manual or watchdog-initiated—replaces any earlier deadline with a new full `COOLDOWN_SECONDS` measured from that stop.
5. If autobrr is still stopped at expiry, the watchdog starts it. If it is already running, no start is attempted.

## Project-wide input-processing-output flow

The systemd unit starts the persistent shell script. The script sources the dotenv file, obtains a singleton lock, restores state, and verifies that the configured Docker container exists. Each poll inspects Docker state.

For a running container, the script requests readiness and IRC state. Initialization latches only when readiness is `OK`, the IRC endpoint returns valid JSON, at least one enabled network exists, and at least one enabled network is connected. Before that latch, the script cannot stop the container. After initialization, repeated readiness failures or an aggregate enabled-network failure can stop it.

For a stopped container, the script identifies the running-to-stopped transition using persistent `LAST_RUNNING`. It creates a deadline equal to stop-observation time plus the full cooldown. It leaves the container stopped before the deadline and starts it at or after the deadline. A later stop always creates a new complete cooldown.

State is written atomically so service restarts retain initialization, previous running state, debounce counters, and cooldown deadline. Logs go to journald.

## Why the log endpoint is not an automatic trigger

The implementation intentionally uses readiness and `/api/irc`, not `/api/logs/files/autobrr.log`, for stop decisions. The IRC API represents current configured-network state and distinguishes records by network ID. Logs are historical, may rotate, contain expected startup transitions, and use server hostnames that can be shared by multiple configured networks. Your sample has two P2P-Network records using the same server, while one is disabled. Correlating log transitions back to the correct enabled record would be less reliable than using current API state.

Logs remain valuable for diagnosis, but omitting them from automatic stop logic reduces false stops and therefore reduces flapping.

## Health classification

An enabled network is classified as bad when:

- it is not connected; or
- it is not healthy; or
- it has enabled channels but none of those enabled channels is both `monitoring: true` and `state: "Monitoring"`.

The third rule is deliberately network-level. A network with several enabled channels is not classified as bad merely because one channel has a problem while another enabled channel remains monitored.

Both aggregate thresholds must be met:

```text
BAD_NETWORKS >= BAD_NETWORK_MINIMUM
and
BAD_NETWORKS / ENABLED_NETWORKS >= BAD_NETWORK_PERCENT
```

With the sample response, five networks are enabled. The disabled P2P-Network record is excluded. The enabled P2P-Network with the `+k` channel error counts as one bad network, while the other four shown enabled records are connected and monitoring. With the defaults `BAD_NETWORK_MINIMUM=2` and `BAD_NETWORK_PERCENT=50`, this does not trigger a stop. For five enabled networks, at least three must be bad to meet the 50% threshold.

## Initialization definition

For one container run, initialization is complete when all are true in one poll:

- Docker reports the container running;
- readiness returns exactly `OK` within `HTTP_TIMEOUT_SECONDS`;
- `/api/irc` returns a valid JSON array;
- at least one IRC network is enabled;
- at least one enabled IRC network is connected.

Once latched, readiness can subsequently become a stop signal. The initialization latch resets whenever a stop is observed or the watchdog starts the container.

## Stop conditions and debounce

After initialization, either condition can qualify:

- readiness does not return `OK` in time; or
- the IRC API is available and both bad-network thresholds are met.

The condition must occur `FAILURE_CONFIRMATIONS` times within `FAILURE_WINDOW_SECONDS`. A healthy observation clears the sequence. An unavailable or malformed IRC endpoint alone is not treated as proof that multiple IRC networks are bad; readiness failure can still qualify independently.

## Stop and cooldown examples

### Watchdog stop

```text
10:00:00 confirmed initialized failure
10:00:00 watchdog stops autobrr
10:00:00 cooldown deadline becomes 10:05:00
10:05:00 watchdog starts autobrr if it remains stopped
```

### Manual start during cooldown, followed by a new stop

```text
10:00:00 watchdog stops autobrr; deadline is 10:05:00
10:02:00 user starts autobrr; watchdog leaves it running
10:03:00 autobrr becomes initialized
10:04:00 confirmed stop condition occurs, or the user stops autobrr
10:04:00 new cooldown deadline becomes 10:09:00
10:09:00 watchdog starts autobrr if it remains stopped
```

The earlier 10:05 deadline is replaced by the full cooldown from the new stop.

### Watchdog starts while autobrr is already stopped

The exact historical stop time is unknowable. The watchdog conservatively treats the first observation as the stop time and waits one full cooldown before starting autobrr. This preserves the rule that it never starts without an expired cooldown.

## Per-file documentation

### `autobrr-irc-anti-flap.sh`

Role, direct inputs, direct outputs, side effects, top-level variables, every function, and project flow are documented in the header. It sources the env file, controls the configured Docker container, writes persistent state, and is invoked by the service.

### `autobrr-irc-anti-flap.env.example`

The header documents the dotenv structure and every entry as a separate input, including type, constraints, consumer, and security requirement. It produces exported shell variables when sourced and has no independent side effects.

### `autobrr-irc-anti-flap.service`

The header documents ordering inputs, execution inputs, output handling, filesystem side effects, hardening, and cross-file flow. It supervises the watchdog but does not directly control autobrr.

### `test-autobrr-irc-anti-flap.sh`

The header documents test inputs, output, functions, side effects, and cross-file dependency. It performs Bash syntax checks, source-policy checks, and model scenarios without calling Docker or systemd.

### `README.md`

This file provides the complete tree, project-wide flow, design rules, operational behavior, per-file documentation, installation, testing, observation, maintenance, and rollback. It is not consumed at runtime and has no side effects.

## Installation

Dependencies:

```bash
sudo apt-get install curl jq
```

Prepare configuration:

```bash
cp autobrr-irc-anti-flap.env.example autobrr-irc-anti-flap.env
editor autobrr-irc-anti-flap.env
chmod 0600 autobrr-irc-anti-flap.env
```

Run tests:

```bash
./test-autobrr-irc-anti-flap.sh
```

Install after separately disabling the old controller:

```bash
sudo install -d -m 0700 /var/lib/autobrr-irc-anti-flap
sudo install -m 0750 autobrr-irc-anti-flap.sh /usr/local/sbin/autobrr-irc-anti-flap.sh
sudo install -m 0600 autobrr-irc-anti-flap.env /etc/autobrr-irc-anti-flap.env
sudo install -m 0644 autobrr-irc-anti-flap.service /etc/systemd/system/autobrr-irc-anti-flap.service
sudo systemctl daemon-reload
sudo systemctl enable --now autobrr-irc-anti-flap.service
```

## Observation

```bash
systemctl status autobrr-irc-anti-flap.service
journalctl -u autobrr-irc-anti-flap.service -f
sudo cat /var/lib/autobrr-irc-anti-flap/state.env
```

## Maintenance warning

Because every observed stop creates a cooldown and the watchdog starts autobrr after expiry, stop the watchdog service first if autobrr must remain down for maintenance:

```bash
sudo systemctl stop autobrr-irc-anti-flap.service
sudo docker stop autobrr
```

After maintenance:

```bash
sudo docker start autobrr
sudo systemctl start autobrr-irc-anti-flap.service
```

## Rollback

```bash
sudo systemctl disable --now autobrr-irc-anti-flap.service
```

Re-enable the previous implementation separately if required. This project does not alter or remove legacy files.
