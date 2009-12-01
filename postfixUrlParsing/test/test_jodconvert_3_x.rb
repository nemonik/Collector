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
require 'jodconvert_3_x'
require 'tomcat_cannot_be_started'
require 'tomcat_already_running'
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

class TestJODConvert_3_x < Test::Unit::TestCase
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

    @manager = JODConvert_3_x.instance

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

    begin
      LOG.debug("asking for tomcat to start")
      @manager.ask_for(:start);
    rescue TomcatAlreadyRunning
      LOG.debug("Tomcat already running.")
    end

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

    if @manager.running?
      value = @manager.manager_listening?
    else
      value = @manager.ask_for(:start)
    end

    assert(value, true)
  end

  def test_start_from_shutdown
    value = false
    value = @manager.ask_for(:start) if @manager.ask_for(:shutdown)
    assert(value, true)
  end
  
  def test_shutdown_from_running
    value = false
    value = @manager.ask_for(:shutdown) if @manager.ask_for(:start)
    assert(value, true)
  end
  
  def test_restart_from_running
    value = false
    value = @manager.ask_for(:restart) if @manager.ask_for(:start)
    assert(value, true)
  end
  
  def test_restart_from_shutdown
    value = false
    value = @manager.ask_for(:restart) if @manager.ask_for(:shutdown)
    assert(value, true)
  end

  def test_threaded_five_restarts
    threads = []
    success = 0

    5.times { |i|
      threads << Thread.new(i) {
        manager = JODConvert_3_x.instance

        if manager.ask_for(:restart)
          success += 1
        end
      }
    }

    threads.each {|t| t.join }

    all_exit = false
    until (all_exit == true)
      all_exit = true
      threads.size.times {|i|
        all_exit = all_exit && (threads[i].status == false)
      }
    end

    assert(success, 5)
  rescue Timeout::Error
    raise TomcatCannotBeStarted.new('Restart timed out; Tomcat cannot be restarted.')
  end

  def test_threaded_four_restarts_followed_by_a_shutdown
    threads = []
    success = 0

    5.times { |i|
      threads << Thread.new(i) {
        manager = JODConvert_3_x.instance

        if (i == 4)

          # for the fifth thread request a shutdown

          retries = JODConvert_3_x::MAX_RETRIES

          until((retries -= 1) == 0)
            if manager.ask_for(:shutdown)
              success += 1
              break
            else
              LOG.debug("resending shutdown request")
            end
          end

        else

          # otherwise ask for a restart

          if manager.ask_for(:restart)
            success += 1
          end
        end
      }
    }

    threads.each {|t| t.join }

    all_exit = false
    until (all_exit == true)
      all_exit = true
      threads.size.times {|i|
        all_exit = all_exit && (threads[i].status == false)
      }
    end

    assert(success, 5)
  rescue Timeout::Error
    raise TomcatCannotBeStarted.new('Restart timed out; Tomcat cannot be restarted.')
  end

  def test_threaded_four_restarts_followed_by_a_shutdown
    threads = []
    success = 0

    5.times { |i|
      threads << Thread.new(i) {
        manager = JODConvert_3_x.instance

        if (i == 4)

          # for the fifth thread, request a shutdown

          retries = JODConvert_3_x::MAX_RETRIES

          until((retries -= 1) == 0)
            if manager.ask_for(:shutdown)
              success += 1
              break
            else
              LOG.debug("resending shutdown request")
            end
          end

        else

          # otherwise ask for a restart

          if manager.ask_for(:restart)
            success += 1
          end
        end
      }
    }

    threads.each {|t| t.join }

    all_exit = false
    until (all_exit == true)
      all_exit = true
      threads.size.times {|i|
        all_exit = all_exit && (threads[i].status == false)
      }
    end

    assert(success, 5)
  rescue Timeout::Error
    raise TomcatCannotBeStarted.new('Restart timed out; Tomcat cannot be restarted.')
  end

  def test_threaded_two_restarts_a_shutdown_and_two_restarts
    threads = []
    success = 0

    5.times { |i|
      threads << Thread.new(i) {
        manager = JODConvert_3_x.instance

        if (i == 2)

          # for the 3rd thread, request a shutdown

          retries = JODConvert_3_x::MAX_RETRIES

          until((retries -= 1) == 0)
            if manager.ask_for(:shutdown)
              success += 1
              break
            else
              LOG.debug("resending shutdown request")
            end
          end

        else

          # otherwise ask for a restart

          if manager.ask_for(:restart)
            success += 1
          end
        end
      }
    }

    threads.each {|t| t.join }

    all_exit = false
    until (all_exit == true)
      all_exit = true
      threads.size.times {|i|
        all_exit = all_exit && (threads[i].status == false)
      }
    end

    assert(success, 5)
  rescue Timeout::Error
    raise TomcatCannotBeStarted.new('Restart timed out; Tomcat cannot be restarted.')
  end

  def test_shutdown_webapp_then_handle_process_office_file

    info = []
    file_name = ''
    value = false

    # get a random office file from samples...
    until (value)
      file_name = File.join(@samples_folder, Dir.entries(@samples_folder)[rand(Dir.entries(@samples_folder).size)])

      info = mime_shared_info(file_name)

      value = info[1].include?('openoffice') && !(info[1].include?('openoffice.org-impress'))
    end

    manager = JODConvert_3_x.instance
    value = value && !manager.process_office_file(file_name, info[0], 'text/html', 'html').nil?

  rescue Exception => e
    LOG.error("#{e.class} : #{e.message}\n#{e.backtrace.join("\n")}")
  ensure
    assert(value, true)
  end


  def test_threaded_random_kill_of_tomcat_while_threads_convert_5000_through_process_office_file

    number_of_times = 5000;
    mutex = Mutex.new
    value = true
    threads = []

    Thread.new() do
      
      LOG.debug("Started kill thread...")

      while mutex.synchronize {number_of_times} > 0
        sleep rand(60)+30
        LOG.debug("Waking up, and killing Tomcat...".yellow)

        pid = -1
        
        IO.popen("ps aux | grep org.apache.catalina.startup.Bootstrap") {|stdout|
          out = stdout.read

          out.split(/\n/).each { |line|

            LOG.debug("line = \"#{line}\"")

            if line.include? 'java'
              pid = line.split(" ")[1]
              break
            end
          } 
        }

        IO.popen("kill -9 #{pid}") {|stdout|
          stdout.read
        }

      end
    end

    10.times {|i|
      threads << Thread.new(i) do
        manager = JODConvert_3_x.instance
        while (mutex.synchronize {number_of_times} > 0)
          begin

            info = []
            file_name = ''
            value = false

            # get a random office file from samples...
            until (value)
              file_name = File.join(@samples_folder, @samples_files[rand(@samples_files.size)])

              info = mime_shared_info(file_name)

              value = (info[1].include?('openoffice')) && !(info[1].include?('openoffice.org-impress'))
            end

            LOG.debug("request: #{mutex.synchronize {number_of_times}} processing")

            tmp_value = !manager.process_office_file(file_name, info[0], 'text/html', 'html').nil?

            mutex.synchronize {
              number_of_times -= 1
              value = value && tmp_value
            }

            #sleep rand(15)
            #sleep 5
            sleep 0.5
          rescue 
            LOG.error("#{e.class} : #{e.message}\n#{e.backtrace.join("\n")}")
          end
        end
      end
    }

    threads.each {|t| t.join }

    all_exit = false
    until (all_exit == true)
      all_exit = true
      threads.size.times {|i|
        all_exit = all_exit && (threads[i].status == false)
      }
    end

  rescue Exception => e
    LOG.error("#{e.class} : #{e.message}\n#{e.backtrace.join("\n")}")
  ensure
    assert(value, true)
  end

  def test_threaded_random_stop_of_webapp_while_threads_convert_5000_through_process_office_file

    number_of_times = 5000;
    mutex = Mutex.new
    value = true
    threads = []

    Thread.new() {
      LOG.debug("Started stop webapp thread...")

      while mutex.synchronize {number_of_times} > 0
        sleep rand(60)+30
        begin

          LOG.debug("Waking up, and asking for stop of webapp...".yellow)

          req = Net::HTTP::Get.new("/manager/html/stop?path=#{JODConvert_3_x::WEBAPP_PATH}")
          req.basic_auth(JODConvert_3_x::TOMCAT_MANAGER_USER, JODConvert_3_x::TOMCAT_MANAGER_PASSWORD)

          Net::HTTP.start(JODConvert_3_x::HOSTNAME, JODConvert_3_x::PORT) {|http|
            http.request(req)
          }
        rescue Exception => e
          # swallow
        end
      end
    }

    20.times {|i|
      threads << Thread.new(i) do
        manager = JODConvert_3_x.instance
        while (mutex.synchronize {number_of_times} > 0)

          begin
            info = []
            file_name = ''
            value = false

            # get a random office file from samples...
            until (value)
              file_name = File.join(@samples_folder, @samples_files[rand(@samples_files.size)])

              info = mime_shared_info(file_name)

              value = (info[1].include?('openoffice')) && !(info[1].include?('openoffice.org-impress'))
            end

            LOG.debug("request: #{mutex.synchronize {number_of_times}} processing")

            tmp_value = !manager.process_office_file(file_name, info[0], 'text/html', 'html').nil?

            mutex.synchronize {
              number_of_times -= 1
              value = value && tmp_value
            }

            #sleep rand(15)
            #sleep 5
            #sleep 0.5

            # no sleep, hammer it as fast you can
          rescue Exception => e
            LOG.error("#{e.class} : #{e.message}\n#{e.backtrace.join("\n")}")
          end
        end
      end
    }

    threads.each {|t| t.join }

    all_exit = false
    until (all_exit == true)
      all_exit = true
      threads.size.times {|i|
        all_exit = all_exit && (threads[i].status == false)
      }
    end

  rescue Exception => e
    LOG.error("#{e.class} : #{e.message}\n#{e.backtrace.join("\n")}")
  ensure
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

    Thread.new() {
      LOG.debug("Started stop webapp thread...")

      while mutex.synchronize {number_of_times} > 0
        sleep rand(60)+30
        begin

          LOG.debug("Waking up, and asking for stop of webapp...".yellow)

          req = Net::HTTP::Get.new("/manager/html/stop?path=#{JODConvert_3_x::WEBAPP_PATH}")
          req.basic_auth(JODConvert_3_x::TOMCAT_MANAGER_USER, JODConvert_3_x::TOMCAT_MANAGER_PASSWORD)

          Net::HTTP.start(JODConvert_3_x::HOSTNAME, JODConvert_3_x::PORT) {|http|
            http.request(req)
          }
        rescue Exception => e
          # swallow
        end
      end
    }

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

      sleep 5.0

    end

  rescue Exception => e
    LOG.error("#{e.class} : #{e.message}\n#{e.backtrace.join("\n")}")
  ensure
    assert(value, true)
  end

end