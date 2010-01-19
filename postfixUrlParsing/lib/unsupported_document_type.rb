#!/usr/local/bin/ruby19

#
# == Synopsis
#   A Runtime error used to denote the JODConvert 3.x service does not
#   support the type of document sent for conversion.
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2010 The MITRE Corporation.  All Rights Reserved.
# License:: GNU GENERAL PUBLIC LICENSE

class UnsupportedDocumentType < RuntimeError
  def initialize(message = "Unsupported document type.")
    super(message)
  end
end
