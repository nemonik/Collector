#!/bin/sh

# A simple shell-based wrapper to Unix nc command to display the count of
# URLs sent to the AMQP queue to be processed.  

/usr/bin/nc -w 30 localhost 8081 << EOF
set count $@
EOF