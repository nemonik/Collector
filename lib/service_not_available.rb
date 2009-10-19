#!/usr/local/bin/ruby19

#
# == Synopsis
#   A Runtime error used to denote the JODConvert service is not available.
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

class ServiceNotAvailable < RuntimeError
  def initialize(message)
    if message == nil
      super("Service is not available.")
    else
      super(message)
    end
  end
end
