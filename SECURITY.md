# Security

MDEdit opens a folder you choose and works only inside it. It runs in the macOS sandbox, makes one network request of its own (a once-a-day look at GitHub for a newer release, which Settings can switch off), and the optional local agent server (Settings ▸ Agents) is off until you turn it on, listens on the loopback address only, and needs a bearer token.

## Reporting a problem

Please report a vulnerability privately, not in a public issue: use **Security ▸ Report a vulnerability** on this repository's GitHub page. Say what you did, what you expected and what happened. A path that lets a note, an HTML template or an agent read or write outside the opened folder, run a program, or reach the network is the kind of thing that matters most; the rules are in the README under "Rules for changes".

Only the latest release is supported.
