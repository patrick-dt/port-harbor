# Security

Port Harbor runs entirely locally. It does not send telemetry or talk to a network. Stop and Restart signal processes on this Mac using hardcoded `/bin/kill` after checking the PID still matches the expected command.

Report vulnerabilities privately via [GitHub Security Advisories](https://github.com/patrick-dt/port-harbor/security/advisories/new). Please do not open a public issue for a report that could be used to stop or relaunch the wrong process.
