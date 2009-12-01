#!/usr/local/bin/ruby19

#
# == Synopsis
#   A Runtime error used to denote that file compression type could not be
#   handled.
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

class UnhandledFormOfCompression< RuntimeError
  def initialize(message = "Compression type unhandled.")
    super(message)
  end
end