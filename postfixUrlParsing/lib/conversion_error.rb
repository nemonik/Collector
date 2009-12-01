#!/usr/local/bin/ruby19

#
# == Synopsis
#   A Runtime error used to denote the JODConvert service is reporting
#   that it could not convert the document to the type specified.
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

class ConversionError < RuntimeError

end
