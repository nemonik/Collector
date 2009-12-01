#!/usr/local/bin/ruby19

#
# == Synopsis
#   A Runtime error used to denote that Tomcat is likely restarting.
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

class TomcatLikelyRestarting < RuntimeError
  def initialize(message = "Tomcat is likely restarting...")
    super(message)
  end
end
