#!/usr/local/bin/ruby19

#
#  == Synopsis
#   A unit test for JODConvert 3.x web service
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

$LOAD_PATH << File.expand_path('../lib')  # hack for now, to pick up my Compression module

require "test/unit"
require 'ooo_conversion_srvc_client'
require 'conversion_error'
require 'logger'
require 'lorem'
require 'thread'
require 'term/ansicolor'
require 'uri'
require 'net/http'
require 'stringio'
require 'open-uri'
require 'guid'
require 'mime/types'
require 'rmail'
require 'net/smtp'
require 'fileutils'
require 'compression'
require 'mime'
require 'utility'

class Tests < Test::Unit::TestCase
  include Term::ANSIColor, Utility, Compression, Mime

  LOG = Logger.new(STDOUT)
  LOG.level = Logger::DEBUG #DEBUG INFO ERROR
  LOG.datetime_format = "%H:%M:%S"

  attr_accessor :urls_filename
  attr_accessor :samples_folder
  attr_accessor :ignore
  attr_accessor :search_terms
  attr_accessor :search_term_iterator
  attr_accessor :urls
  attr_accessor :url_iterator
  attr_accessor :doc_types

  def setup

    @ooo_conversion_srvc_client = OOoConversionSrvcClient

    @urls_filename = File.expand_path('~/urls.txt')
    @samples_folder = File.expand_path('~/samples')

    @ignore = ['www.merriam-webster.com', 'en.wiktionary.org', 'www.websters-online-dictionary.org', 'en.wikipedia.org', 'www.answers.com']
    @msg_count = 0

    @search_terms = []
    @search_term_iterator = 0

    @urls = []
    @url_iterator = 0

    # read URLs from file if the file exists; otherwise, generate URLs using
    # 5000 seed words
    initialize_urls(true, 5000)

    Dir.mkdir(@samples_folder) if (!File.exist?(@samples_folder))
    @samples_files = Dir.entries(@samples_folder)

    if (@samples_files.size == 2)
      # generate 500 docs from the URLs containing up 20 paragraphs each containg up 5 urls
      generate_docs(500, 20, 5)
      @samples_files = Dir.entries(@samples_folder)
    end

    @samples_files.delete('.')
    @samples_files.delete('..')



    LOG.debug("initialized...")
  end

  def teardown
   
  end

  def generate_docs(document_count = 100, max_paragraph_count = 20, max_url_count = 5)

    FileUtils.rm_f @samples_folder if File.exists?(@samples_folder)

    LOG.debug("creating #{document_count} document(s)...")

    (0..document_count).each {|i|
      generate_random_type_document(@samples_folder, max_paragraph_count, max_url_count)
      LOG.debug("generated #{i}/#{document_count}")
    }

  end

  def send_msg(from, to, attachment_paths, compression = false, max_paragraph_count = 20, max_url_count = 5)
    subject = "Sending "

    message = RMail::Message::new
    message.header['From'] = "<#{from}>"
    message.header['To'] = "<#{to}>"
    message.header['Date'] = Time::new.rfc2822
    LOG.debug("Created message object...")

    text_part = RMail::Message::new
    text_part.header['Content-Type'] = 'TEXT/PLAIN; format=flowed; charset=utf-8'
    text_part.body = generate_text('text/plain', max_paragraph_count, max_url_count)
    LOG.debug("Created text part...")

    html_part = RMail::Message::new
    html_part.header['Content-Type'] = 'text/html, charset=utf-8'
    html_part.body = generate_text('text/html', max_paragraph_count, max_url_count)
    LOG.debug("Created html part...")

    attachments = Array.new
    dst = File.join('/tmp', Guid.new.to_s)

    if ((compression) && (attachment_paths.size > 0))

      # attach files in an archive of some form

      Dir.mkdir(dst)

      tmp_filepaths = Array.new

      attachment_paths.each { |filepath|
        FileUtils.cp(filepath, dst)
        tmp_filepaths.push(File.join(dst, File.basename(filepath)))
      }

      if (attachment_paths.size > 1)
        if (rand() > 0.50)
          dst = File.join(dst, 'archive.zip')
          zip(dst, tmp_filepaths)
        else
          dst = File.join(dst, 'archive.tar')
          tar(dst, tmp_filepaths)

          if (rand() > 0.5)
            gzip([dst])
            dst += '.gz'
          else
            bzip2([dst])
            dst += '.bz2'
          end
        end
      else
        if ((r = rand()) > 0.66)
          gzip(tmp_filepaths)
          dst = tmp_filepaths[0] + '.gz'
        elsif (r > 0.33)
          dst = tmp_filepaths[0] + '.zip'
          zip(dst, tmp_filepaths)
        elsif (r > 0.0)
          bzip2(tmp_filepaths)
          dst = tmp_filepaths[0] + '.bz2'
        end
      end

      attachment_part = RMail::Message::new

      mime_type = MIME::Types.of(dst).first
      content_type = (mime_type ? mime_type.content_type : 'application/binary')
      filename = File.basename(dst)

      LOG.debug("Creating attachment part for #{dst}")

      subject = "#{filename} containing #{attachment_paths}"

      attachment_part.header['Content-Type'] = "#{content_type}; name=#{filename}"
      attachment_part.header['Content-Transfer-Encoding'] = 'BASE64'
      attachment_part.header['Content-Disposition:'] = "attachment; filename=#{filename}"
      attachment_part.body = [File.open(dst).read].pack('m')

      attachments.push(attachment_part)

      FileUtils.rm_rf(File.dirname(dst))

    else

      # attach files individually

      attachment_paths.each {|filepath|
        if File.file? filepath # ignore '.', and '..'
          attachment_part = RMail::Message::new

          mime_type = MIME::Types.of(filepath).first
          content_type = (mime_type ? mime_type.content_type : 'application/binary')
          filename = File.split(filepath)[1]

          if (attachments.empty?)
            subject += "#{filename}"
          else
            subject += ", #{filename}"
          end

          attachment_part.header['Content-Type'] = "#{content_type}; name=#{filename}"
          attachment_part.header['Content-Transfer-Encoding'] = 'BASE64'
          attachment_part.header['Content-Disposition:'] = "attachment; filename=#{filename}"
          attachment_part.body = [File.open(filepath).read].pack('m')

          attachments.push(attachment_part)

          LOG.debug("Created attachment part for #{filename}")
        else
          LOG.debug("Skipping #{filepath}")
        end
      }
    end

    if (!attachments.empty?)
      message.header['Subject'] = subject
      message.header['X-Number-of-Attachments'] = attachments.size.to_s
    else
      message.header['Subject'] = subject + "no attachments"
    end

    message.add_part(text_part)
    message.add_part(html_part)

    attachments.each {|attachment|
      message.add_part(attachment)
    }

    smtp = Net::SMTP.start("localhost.localdomain", 25)
    @msg_count += 1
    message.header['X-Count'] = "#{@msg_count}"

    smtp.send_message message.to_s, from, to
    smtp.finish

    LOG.debug("Sent message #{@msg_count}...")

    return true
  rescue Exception => e
    LOG.error("#{e.class} : #{e.message}\n#{e.backtrace.join("\n")}")
    return false
  end


  def send_all(from, to, path, sleep_sec = 0, attach_max = 1, compression = false, max_paragraph_count = 20, max_url_count = 5)

    value = true
    filepaths = Array.new
    attach_count = rand(attach_max)

    at = 0
    entries = Dir.entries(path)
    entries.each { |filename|

      at +=1

      filepath = File.join(path, filename)

      if File.file? filepath

        if (filepaths.size < attach_count)
          filepaths.push(filepath)
        end

        if ((filepaths.size == attach_count) || (at == entries.size))
          LOG.debug("sending #{filepaths}")
          LOG.debug("===========================")

          value = value && send_msg(from, to, filepaths, compression, max_paragraph_count, max_url_count)

          if (sleep_sec == -1)
            random_sleep_sec = rand()
            LOG.debug("sleeping #{random_sleep_sec} seconds...")
            sleep(random_sleep_sec)
          else
            LOG.debug("sleeping #{sleep_sec} seconds...")
            sleep(sleep_sec)
          end
          LOG.debug("===========================")

          filepaths = Array.new
        end
      else
        LOG.debug("not sending #{filepath}")
      end
    }

    return value
  end

  def test_tomcat_running
    value = false

    if @ooo_conversion_srvc_client.running?
      value = @ooo_conversion_srvc_client.listening?
    else
      value = @ooo_conversion_srvc_client.start
    end

    assert(value, true)
  end

  def test_start_from_shutdown
    value = false
    value = @ooo_conversion_srvc_client.start if @ooo_conversion_srvc_client.shutdown
    assert(value, true)
  end
  
  def test_shutdown_from_running
    value = false
    value = @ooo_conversion_srvc_client.shutdown if @ooo_conversion_srvc_client.start
    assert(value, true)
  end
  
  def test_restart_from_running
    value = false
    value = @ooo_conversion_srvc_client.restart if @ooo_conversion_srvc_client.start
    assert(value, true)
  end
  
  def test_restart_from_shutdown
    value = false
    value = @ooo_conversion_srvc_client.restart if @ooo_conversion_srvc_client.shutdown
    assert(value, true)
  end

  def test_send_mail

    value = true
    
    #from = 'walsh@honeycheck-milter.mitre.org'
    from = 'walsh@localhost.localdomain'
    
    #to = 'walsh@honeycheck-milter.mitre.org'
    to = 'walsh@localhost.localdomain'
    attach_max = 5

    chance_of_compression = 50
    chance_of_attachment = 50

    max_paragraph_count = 20
    max_url_count = 5

    at = 0

    count = 10000
    1.upto(count) do |i|
      LOG.debug("starting interation #{i}")
      
      attachment_paths = Array.new

      LOG.debug("#{@samples_folder} : #{@samples_files[at]}")

      1.upto(rand(attach_max) + 1) do
        attachment_paths << File.join(@samples_folder, @samples_files[at])
        if (at < (@samples_files.size - 1))
          at += 1
        else
          at = 0
        end
      end if (rand()*100 <= chance_of_attachment)

      puts("sending msg #{i} containing: #{attachment_paths}")

      value = value && send_msg(from, to, attachment_paths, rand()*100 <= chance_of_compression, max_paragraph_count, max_url_count)

      sleep 0.5

    end

  rescue Exception => e
    LOG.error("#{e.class} : #{e.message}\n#{e.backtrace.join("\n")}")
  ensure
    assert(value, true)
  end

end