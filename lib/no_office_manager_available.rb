#!/usr/local/bin/ruby19

#
# == Synopsis
#   A Runtime error used to denote the JODConvert 3.x service is reporting
#   that an office manager was not available.
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

class NoOfficeManagerAvailable < RuntimeError
  def initialize(message = "No Office Manager is available.")
    super(message)
  end
end
