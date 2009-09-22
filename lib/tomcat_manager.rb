#!/usr/local/bin/ruby19

# == Synopsis
#   A singleton used for managing restarting of Apache Tomcat
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

require 'net/http'
require 'logger'
require 'singleton'
require 'term/ansicolor'
require 'uri'

include Term::ANSIColor


# hack logger to show the thread id per log message, and turn ERROR messages red
# TODO: need to move this elsewhere...
class Logger

  alias original_add add

  def add(severity, message = nil, progname = nil, &block)
    progname = "thread #{Thread.current.object_id} : #{progname}"
    progname = progname.red if severity == ERROR

    original_add(severity, message, progname, &block)
  end
end

class TomcatManager
  include Singleton

  class TomcatCannotBeRestarted < RuntimeError; end;
  class TomcatNeedsAForcedRestart < RuntimeError; end;
  class TomcatNeedsToBeStarted < RuntimeError; end;

  module StateLevel
    OTHER_THAN_RESTARTING = 0
    RESTARTING = 1
  end
  include StateLevel

  $host = 'localhost'
  $port = 8080
  $openoffice_port = 8100
  $webapp_path = '/jodconverter-sample-webapp-3.0-SNAPSHOT'

  $PID_DOESNT_EXIST = -1

  def initialize
    @state = OTHER_THAN_RESTARTING
    @mutex = Mutex.new

    @log = Logger.new(STDOUT)
    @log.level = Logger::DEBUG #DEBUG INFO ERROR
    @log.datetime_format = "%H:%M:%S"
  end

  def listening?
    begin

      response = Net::HTTP.get_response(URI.parse("#{$protocol}://#{$hostname}:#{$port}#{$webapp_path}/"))

      if response.class == Net::HTTPOK
        return true
      else
        return false
      end
    rescue Exception 
      return false
    end
  end

  def get_tomcat_pid

    # although "netstat -nlp | grep #{$port}" would allow me to determine the
    # pid of a specific instance of tomcat listening at $port, it possible
    # for tomcat never to bind to the $port and still be running

    out = nil
    pid = $PID_DOESNT_EXIST
    IO.popen("ps aux | grep org.apache.catalina.startup.Bootstrap") {|stdout|
      out = stdout.read

      if out != nil && !out.empty? && out.split(" ")[10] =~ /java$/
        pid = out.split(" ")[1]
        break
      end
    }

    return pid
  end

  def get_openoffice_pid

    # although "netstat -nlp | grep #{openoffice_port" would allow me to
    # determine the pid for openoffice it possible that openoffice never
    # binded to the $port and is still running

    out = nil
    pid = $PID_DOESNT_EXIST
    IO.popen("ps aux | grep \"/usr/lib64/openoffice.org3/program/soffice.bin -accept=socket,host=127.0.0.1,port=#{$openoffice_port};urp;\"") {|stdout|
      out = stdout.read

      if out != nil && !out.empty?
        pid = out.split(" ")[1]
        break
      end
    }

    return pid
  end

  def running?
    if get_tomcat_pid != $PID_DOESNT_EXIST && get_open_office_pid != $PID_DOESNT_EXIST
      return true
    else
      return false
    end
  end

  def restart

    if (@mutex.synchronize {@state} != RESTARTING)

      # allow for tomcat to be restarted

      @mutex.synchronize {@state = RESTARTING}

      shutdown

      start

      until listening?
        @log.debug('Sleeping until listening...')
        sleep 5
      end

      @mutex.synchronize {@state = OTHER_THAN_RESTARTING}
    else

      # all other enterants wait

      until @mutex.synchronize {@state} == OTHER_THAN_RESTARTING
        @log.debug("Waiting until tomcat is restarted...")
        sleep 5
      end

      @log.debug("done waiting...")
    end

    return true
  end

  private

  def shutdown
    pid = get_tomcat_pid

    if pid != $PID_DOESNT_EXIST
      @log.info('Shutting down tomcat...')
      IO.popen("kill -9 #{pid}") {|stdout|
        stdout.read
      }
    end

    pid = get_openoffice_pid

    if pid != $PID_DOESNT_EXIST
      @log.info('Shutting down OpenOffice...')
       IO.popen("kill -9 #{pid}") {|stdout|
        stdout.read
      }
    end
  end

  def start
    if (!running?)
      @log.info("Starting tomcat...")
      IO.popen('/home/walsh/apache-tomcat-6.0.20/bin/startup.sh') {|stdout|
        stdout.read
      }
    end
  end
end

#threads = []
#
#5.times { |i|
#  threads << Thread.new(i) {
#    puts "#{Thread.current.object_id} : started thread #{i}"
#    manager = TomcatManager.instance
#    loop do
#      seconds = rand(60)
#      puts "#{Thread.current.object_id} : Sleeping for #{seconds}-seconds..."
#      sleep seconds
#      manager.restart
#    end
#  }
#}
#
#threads.each {|t| t.join }