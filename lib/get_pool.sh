#!/bin/sh

# A simple shell-based wrapper to Uniox nc command to display URL daemon worker
# pool running states.

/usr/bin/nc -w 30 localhost 8081 << EOF
get pool
EOF