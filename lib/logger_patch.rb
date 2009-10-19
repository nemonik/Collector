#!/usr/local/bin/ruby19
#
#  == Synopsis
#   A patch to the core Logger class to show the thread id per log message, and
#   turn ERROR messages red
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

require 'logger'
require 'term/ansicolor'

include Term::ANSIColor

class Logger

  alias original_add add

  def add(severity, message = nil, progname = nil, &block)
    progname = "thread #{Thread.current.object_id} : #{progname}"
    progname = progname.red if severity == ERROR
    progname = progname.yellow if severity == WARN

    original_add(severity, message, progname, &block)
  end
end
