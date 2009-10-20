#!/usr/local/bin/ruby19

# == Synopsis
#   A script to randomly generate attachments for the purposes of testing
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

$LOAD_PATH << File.expand_path('../lib')  # hack for now, to pick up my Compression module

require 'logger'
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
require 'jodconvert_3_x'
require 'utility'
require 'tomcat_already_running'

class SendEmail

  include Utility, Compression

  attr_accessor :urls_filename
  attr_accessor :samples_folder
  attr_accessor :ignore
  attr_accessor :search_terms
  attr_accessor :search_term_iterator
  attr_accessor :urls
  attr_accessor :url_iterator
  attr_accessor :doc_types

  def initialize(urls_filename = File.expand_path('~/urls.txt'), samples_folder =  File.expand_path('~/samples'))

    @log = Logger.new(STDOUT)
    @log.level = Logger::DEBUG #DEBUG INFO ERROR
    @log.datetime_format = "%H:%M:%S"

    @urls_filename = urls_filename
    @samples_folder = samples_folder

    @ignore = ['en.wikipedia.org', 'www.answers.com']
    @msg_count = 0

    @search_terms = []
    @search_term_iterator = 0

    @urls = []
    @url_iterator = 0

    @manager = JODConvert_3_x.instance

    begin
      @log.debug("asking for tomcat to start")
      @manager.ask_for(:start);
    rescue TomcatAlreadyRunning
      @log.debug("Tomcat already running.")
    end

    @log.debug("initialized...")

  end

  def generate_docs(document_count = 100, max_paragraph_count = 20, max_url_count = 5)

    FileUtils.rm_f @samples_folder if File.exists?(@samples_folder)

    @log.debug("creating #{document_count} document(s)...")

    (0..document_count).each {|i|
      generate_random_type_document(@samples_folder, max_paragraph_count, max_url_count)
      @log.debug("generated #{i}/#{document_count}")
    }

  end

  def send(from, to, filepaths, compress = false, max_paragraph_count = 20, max_url_count = 5, chance_of_attachment = 90)
    subject = "Sending "

    message = RMail::Message::new
    message.header['From'] = "<#{from}>"
    message.header['To'] = "<#{to}>"
    message.header['Date'] = Time::new.rfc2822
    @log.debug("Created message object...")

    text_part = RMail::Message::new
    text_part.header['Content-Type'] = 'TEXT/PLAIN; format=flowed; charset=utf-8'
    text_part.body = generate_text('text/plain', max_paragraph_count, max_url_count)
    @log.debug("Created text part...")

    html_part = RMail::Message::new
    html_part.header['Content-Type'] = 'text/html, charset=utf-8'
    html_part.body = generate_text('text/html', max_paragraph_count, max_url_count)
    @log.debug("Created html part...")

    attachments = Array.new
    dst = File.join('/tmp', Guid.new.to_s)

    if ((compress) && (filepaths.size > 0) && (rand() > (1 - chance_of_attachment * 0.01)))

      Dir.mkdir(dst)

      tmp_filepaths = Array.new

      filepaths.each { |filepath|
        FileUtils.cp(filepath, dst)
        tmp_filepaths.push(File.join(dst, File.basename(filepath)))
      }

      if (filepaths.size > 1)
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

      @log.debug("Creating attachment part for #{dst}")

      subject = "#{filename} containing #{filepaths}"

      attachment_part.header['Content-Type'] = "#{content_type}; name=#{filename}"
      attachment_part.header['Content-Transfer-Encoding'] = 'BASE64'
      attachment_part.header['Content-Disposition:'] = "attachment; filename=#{filename}"
      attachment_part.body = [File.open(dst).read].pack('m')

      attachments.push(attachment_part)

      FileUtils.rm_rf(File.dirname(dst))

    else
      filepaths.each {|filepath|
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

          @log.debug("Created attachment part for #{filename}")
        else
          @log.debug("Skipping #{filepath}")
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

    @log.debug("Sent message #{@msg_count}...")
  end

  def send_all(from, to, path, sleep_sec = 0, attach_max = 1, compress = false, max_paragraph_count = 20, max_url_count = 5, chance_of_attachment = 90)

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
          @log.debug("sending #{filepaths}")
          @log.debug("===========================")
          send(from, to, filepaths, compress, max_paragraph_count, max_url_count, chance_of_attachment)
          if (sleep_sec == -1)
            random_sleep_sec = rand()
            @log.debug("sleeping #{random_sleep_sec} seconds...")
            sleep(random_sleep_sec)
          else
            @log.debug("sleeping #{sleep_sec} seconds...")
            sleep(sleep_sec)
          end
          @log.debug("===========================")

          filepaths = Array.new
        end
      else
        @log.debug("not sending #{filepath}")
      end
    }
  end

  def keep_sending(from, to, path, sleep_sec = 0, attach_max = 1, compress = false, max_paragraph_count = 20, max_url_count = 5, chance_of_attachment = 90)
    l = 0
    loop do
      @log.debug("starting interation #{l}")
      send_all(from, to, path, sleep_sec, attach_max, compress, max_paragraph_count, max_url_count, chance_of_attachment)
      l += 1
    end
  end
end

send_email = SendEmail.new

puts send_email.urls

# read URLs from file if the file exists; otherwise, generate URLs using
# 2000 seed words
send_email.initialize_urls(true, 2000)
# generate 500 docs from the URLs containing up 20 paragraphs each containg up
# 5 urls
#send_email.generate_docs(500, 20, 5)
#send_email.send_all('walsh@localhost.localdomain', 'walsh@localhost.localdomain', '/tmp/sample')
send_email.keep_sending('walsh@localhost.localdomain', 'walsh@localhost.localdomain', File.expand_path('~/samples'), 2, 4, true, 20, 5, 90)
