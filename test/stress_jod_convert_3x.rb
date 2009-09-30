#!/usr/local/bin/ruby19

# == Synopsis
#   A script to stress the JODConvert 3.x OOo service.
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

$LOAD_PATH << File.expand_path('../lib')  # hack for now, to pick up my Compression module

require 'jodconvert_3_x'
require 'utility'
require 'logger_patch'
require 'guid'
require 'unsupported_document_type'
require 'tomcat_cannot_be_started'
require 'conversion_error'

class StressJODConvert3x
  include Utility

  attr_accessor :tmp_folder
  attr_accessor :urls_filename
  attr_accessor :urls
  attr_accessor :url_iterator
  attr_accessor :search_terms
  attr_accessor :search_term_iterator
  attr_accessor :snooze

  def initialize(urls_filename = File.expand_path('~/urls.txt'), tmp_folder = '/tmp', snooze = 5)

    @log = Logger.new(STDOUT)
    @log.level = Logger::DEBUG #DEBUG INFO ERROR
    @log.datetime_format = "%H:%M:%S"

    @urls_filename = urls_filename
    @tmp_folder = tmp_folder

    @urls = []
    @url_iterator = 0

    @search_terms = []
    @search_term_iterator = 0

    @snooze = snooze

    initialize_urls(true, 2000)

    @manager = JODConvert_3_x.instance
    @manager.ask_for(:restart)

    @log.debug("initialized...")

  end

  def run

    document_count = 0

    while (true)

      @log.debug("Requesting the creation of document #{document_count += 1}")

      file_name = generate_random_type_document(@tmp_folder)

      File.delete(file_name) if file_name.kind_of?(String) && File.exists?(file_name)

      @log.debug("deleted #{file_name}")
      @log.debug("sleeping for #{snooze}-seconds")

      sleep snooze
    end
    
  rescue Exception => e
    @log.error("Something bad happended on document #{document_count}...")
    @log.error("#{e.class}: #{e.message}")
    @log.error("#{e.backtrace.join("\n")}")
    #SystemExit.new(1)
    Kernel.exit(1)
  end
end

# single threaded stress
#stress = StressJODConvert3x.new(File.expand_path('~/urls.txt'), '/tmp', 0.00)
#
#stress.run


## multi-threaded stress
threads = []
20.times { |i|
  threads << Thread.new(i) {
    stress = StressJODConvert3x.new(File.expand_path('~/urls.txt'), '/tmp', 0.00)
    stress.run
  }
}

threads.each {|t| t.join }
