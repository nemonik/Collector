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
require 'conversion_error'
require 'logger'
require 'lorem'
require 'thread'
require 'term/ansicolor'

class TestJODConvert_3_x < Test::Unit::TestCase
  include Term::ANSIColor

  def setup
    @manager = JODConvert_3_x.instance

    @log = Logger.new(STDOUT)
    @log.level = Logger::DEBUG #DEBUG INFO ERROR
    @log.datetime_format = "%H:%M:%S"
  end

  def teardown
   
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
              @log.debug("resending shutdown request")
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
              @log.debug("resending shutdown request")
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
              @log.debug("resending shutdown request")
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

    # generate a temp file

    file_name = "/tmp/#{Guid.new.to_s}.txt"

    File.open(file_name, 'w') {|f|
      f.write(Lorem::Base.new('paragraphs', 10).output)
    }

    manager = JODConvert_3_x.instance
    value = nil
    value = manager.process_office_file(file_name, 'text/plain', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'docx') if manager.ask_for(:shutdown)

    File.delete(file_name)

    assert(value, !nil)
  end

  def test_threaded_random_shutdown_webapp_while_looping_through_5000_handle_process_office_file

    # generate a temp file

    file_name = "/tmp/#{Guid.new.to_s}.txt"

    File.open(file_name, 'w') {|f|
      f.write(Lorem::Base.new('paragraphs', 10).output)
    }

    number_of_times = 5000;

    Thread.new() {
      shutdown_thread_manager = JODConvert_3_x.instance

      while number_of_times > 0
        shutdown_thread_manager.ask_for(:stop_webapp)
        sleep 15
      end
    }

    value = true 
    while (number_of_times > 0)
      @log.debug("request: #{number_of_times}")
      number_of_times -= 1
      value = value && !@manager.process_office_file(file_name, 'text/plain', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'docx').nil?
    end

    File.delete(file_name)

    assert(value, true)
  end

  def test_threaded_random_up_shutdown_tomcat_while_in_a_single_thread_looping_through_5000_process_office_file

    # generate a temp file

    file_name = "/tmp/#{Guid.new.to_s}.txt"

    File.open(file_name, 'w') {|f|
      f.write(Lorem::Base.new('paragraphs', 10).output)
    }

    number_of_times = 5000;

    Thread.new() {
      shutdown_thread_manager = JODConvert_3_x.instance

      @log.debug("Started shutdown thread...")
      
      while number_of_times > 0
        shutdown_thread_manager.ask_for(:shutdown)
        sleep 15
      end
    }

    shutdown_thread.join

    value = true
    while (number_of_times > 0)
      @log.debug("request: #{number_of_times}")
      number_of_times -= 1
      value = value && !@manager.process_office_file(file_name, 'text/plain', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'docx').nil?
    end

    File.delete(file_name)

    assert(value, true)
  end

  def test_threaded_random_shutdown_of_tomcat_while_10_threads_convert_5000_through_process_office_file

    # generate a temp file
    file_name = "/tmp/#{Guid.new.to_s}.txt"

    File.open(file_name, 'w') {|f|
      f.write(Lorem::Base.new('paragraphs', 10).output)
    }

    number_of_times = 5000;
    mutex = Mutex.new

    Thread.new() {
      shutdown_thread_manager = JODConvert_3_x.instance

      @log.debug("Started shutdown thread...")

      while mutex.synchronize {number_of_times} > 0
        sleep rand(60)+30
        @log.debug("Waking up, and asking for shutdown of Tomcat...".yellow)
        shutdown_thread_manager.ask_for(:shutdown)
      end
    }

    value = true
    threads = []

    10.times {|i|
      threads << Thread.new(i) {
        manager = JODConvert_3_x.instance
        while (mutex.synchronize {number_of_times} > 0)
          @log.debug("request: #{mutex.synchronize {number_of_times}}")

          mutex.synchronize {number_of_times -= 1}
          
          tmp_value = mutex.synchronize {value} && !manager.process_office_file(file_name, 'text/plain', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'docx').nil?
          mutex.synchronize {value = tmp_value}

          sleep rand(15)
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

    File.delete(file_name)

    assert(value, true)
  end

  def test_threaded_random_of_stop_webapp_while_10_threads_convert_5000_through_process_office_file

    # generate a temp file
    file_name = "/tmp/#{Guid.new.to_s}.txt"

    File.open(file_name, 'w') {|f|
      f.write(Lorem::Base.new('paragraphs', 10).output)
    }

    number_of_times = 5000;
    mutex = Mutex.new

    Thread.new() {
      shutdown_thread_manager = JODConvert_3_x.instance

      @log.debug("Started stop webapp thread...")

      while mutex.synchronize {number_of_times} > 0
        sleep rand(60)+30
        @log.debug("Waking up, and asking for stop of webapp...".yellow)
        shutdown_thread_manager.ask_for(:stop_webapp)
      end
    }

    value = true
    threads = []

    10.times {|i|
      threads << Thread.new(i) {
        manager = JODConvert_3_x.instance
        while (mutex.synchronize {number_of_times} > 0)
          @log.debug("request: #{mutex.synchronize {number_of_times}}")

          mutex.synchronize {number_of_times -= 1}

          tmp_value = mutex.synchronize {value} && !manager.process_office_file(file_name, 'text/plain', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'docx').nil?
          mutex.synchronize {value = tmp_value}

          sleep rand(15)
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

    File.delete(file_name)

    assert(value, true)
  end


  def test_threaded_random_kill_openoffice_while_10_threads_convert_5000_through_process_office_file

    # generate a temp file
    file_name = "/tmp/#{Guid.new.to_s}.txt"

    File.open(file_name, 'w') {|f|
      f.write(Lorem::Base.new('paragraphs', 10).output)
    }

    number_of_times = 5000;
    mutex = Mutex.new

    Thread.new() {
      shutdown_thread_manager = JODConvert_3_x.instance

      @log.debug("Started kill openoffice thread...")

      while mutex.synchronize {number_of_times} > 0
        sleep rand(60)+30

        if ((pid = shutdown_thread_manager.get_openoffice_pid) != JODConvert_3_x::PID_DOESNT_EXIST)
          @log.info('Shutting down OpenOffice...'.yellow)
          IO.popen("kill -9 #{pid}") {|stdout|
            stdout.read
          }
        end
      end
    }

    value = true
    threads = []

    10.times {|i|
      threads << Thread.new(i) {
        manager = JODConvert_3_x.instance
        while (mutex.synchronize {number_of_times} > 0)
          @log.debug("request: #{mutex.synchronize {number_of_times}}")

          mutex.synchronize {number_of_times -= 1}

          tmp_value = mutex.synchronize {value} && !manager.process_office_file(file_name, 'text/plain', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'docx').nil?
          mutex.synchronize {value = tmp_value}

          sleep rand(15)
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

    File.delete(file_name)

    assert(value, true)
  end

  def test_threaded_random_of_stop_webapp_while_10_threads_convert_5000_through_process_office_file

    # generate a temp file
    file_name = "/tmp/#{Guid.new.to_s}.txt"

    File.open(file_name, 'w') {|f|
      f.write(Lorem::Base.new('paragraphs', 10).output)
    }

    number_of_times = 5000;
    mutex = Mutex.new

    Thread.new() {
      shutdown_thread_manager = JODConvert_3_x.instance

      @log.debug("Started stop webapp thread...")

      while mutex.synchronize {number_of_times} > 0
        sleep rand(60)+30
        @log.debug("Waking up, and asking for stop of webapp...".yellow)
        shutdown_thread_manager.ask_for(:stop_webapp)
      end
    }

    value = true
    threads = []

    10.times {|i|
      threads << Thread.new(i) {
        manager = JODConvert_3_x.instance
        while (mutex.synchronize {number_of_times} > 0)
          @log.debug("request: #{mutex.synchronize {number_of_times}}")

          mutex.synchronize {number_of_times -= 1}

          tmp_value = mutex.synchronize {value} && !manager.process_office_file(file_name, 'text/plain', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'docx').nil?
          mutex.synchronize {value = tmp_value}

          sleep rand(15)
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

    File.delete(file_name)

    assert(value, true)
  end
end




