#!/bin/sh

# Simple shell-based wrapper for the POSTFIX URL Daemon filter. Invoked as
# follows:
#
# /path/to/script -f sender recipients...

trap "rm -f in.$$" 0 1 2 3 15
cd /var/spool/mail/filter && cat >in.$$
/usr/sbin/sendmail.postfix -G -i "$@" <in.$$
/usr/bin/nc -w 30 localhost 8081 <in.$$

exit $?