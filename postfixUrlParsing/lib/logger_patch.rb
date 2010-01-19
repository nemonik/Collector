#!/usr/local/bin/ruby19
#
#  == Synopsis
#   A patch to the core Logger class to show the thread id per log message, and
#   turn ERROR messages red
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2010 The MITRE Corporation.  All Rights Reserved.
# License:: GNU GENERAL PUBLIC LICENSE

require 'logger'
require 'term/ansicolor'

include Term::ANSIColor

class Logger

  alias original_add add

  def add(severity, message = nil, progname = nil, &block)

    file_name = ''
    line = ''
    called_from = ''

    if (caller(3).kind_of?(Array))
      called_from = caller(3).first
    else
      called_from = caller[1]
    end

    if (/^(.+?):(\d+)(?::in `(.*)')?/ =~ called_from)
      file_name = File.basename(Regexp.last_match[1])
      line = Regexp.last_match[2].to_i
    end

    progname = "(#{file_name} - #{line}): #{progname}"
    progname = progname.red if severity == ERROR
    progname = progname.yellow if severity == WARN

    original_add(severity, message, progname, &block)
  end
end
