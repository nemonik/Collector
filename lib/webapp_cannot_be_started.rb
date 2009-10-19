#!/usr/local/bin/ruby19

#
# == Synopsis
#   A Runtime error used to denote that the Webapp could not be started.
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

class WebappCannotBeStarted < RuntimeError
  def initialize(message)
    if message == nil
      super("Webapp cannot be started.")
    else
      super(message)
    end
  end
end
