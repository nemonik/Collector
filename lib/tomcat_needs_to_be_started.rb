#!/usr/local/bin/ruby19

#
# == Synopsis
#   A Runtime error used to denote that Tomcat needs to be restarted.
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

class TomcatNeedsToBeStarted < RuntimeError
  def initialize(message)
    if message == nil
      super("Tomcat needs to be restarted.")
    else
      super(message)
    end
  end
end
