#!/bin/sh

# A simple shell-based wrapper to Uniox nc command to shutdown the URL daemon.

/usr/bin/nc -w 30 localhost 8081 << EOF
shutdown
EOF