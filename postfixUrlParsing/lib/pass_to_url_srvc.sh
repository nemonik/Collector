#!/bin/sh

# Simple shell-script to pass emails off to be filtered. Invoked as
# follows:
#
# /path/to/script -f sender recipients...

trap "mv /var/spool/mail/filter/in.$$ /var/spool/mail/filter/mail_incoming/." 0 1 2 3 15

cd /var/spool/mail/filter/ && cat >in.$$
/usr/sbin/sendmail.postfix -G -i "$@" <in.$$

exit $?