#!/bin/sh

# A simple shell-based wrapper to Unix nc command to display URL daemon
# connections.

/usr/bin/nc -w 30 localhost 8081 << EOF
get connections
EOF