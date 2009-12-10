#!/bin/sh

# A simple shell-script to kill zombie workers.

kill -9 `ps aux | grep "url_parsing_srvc.rb" | awk '{print $2}'`