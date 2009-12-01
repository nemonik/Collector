#!/usr/local/bin/ruby19

#
# == Synopsis
#   A Runtime error used to denote that Tomcat could not be started.
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

class TomcatCannotBeStarted < RuntimeError
  def initialize(message = "Tomcat cannot be started.")
      super(message)
  end
end
