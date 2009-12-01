#!/usr/local/bin/ruby19

#
# == Synopsis
#   A singleton used for managing restarting of Apache Tomcat
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

require 'net/http'
require 'logger_patch'
require 'uri'
require 'singleton'
require 'tomcat_cannot_be_started'
require 'tomcat_already_running'

class TomcatManager
  include Singleton

  LOG = Logger.new(STDOUT)
  LOG.level = Logger::WARN #DEBUG INFO ERROR
  LOG.datetime_format = "%H:%M:%S"

  module StateLevel
    UNKNOWN = 'Unknown'
    TOMCAT_STARTING = 'Tomcat Starting'
    TOMCAT_RUNNING = 'Tomcat Running'
    TOMCAT_SHUTTINGDOWN = 'Tomcat Shuttingdown'
    TOMCAT_SHUTDOWN = 'Tomcat Shutdown'
    WEBAPP_STARTING = 'Webapp Starting'
    WEBAPP_RUNNING = 'Webapp Running'
    WEBAPP_STOPPING = 'Webapp Stopping'
    WEBAPP_STOPPED = 'Webapp Stopped'
    WEBAPP_UNKNOWN = 'Webapp Unknown'
  end
  include StateLevel

  HOSTNAME = 'localhost'
  PORT = 8080
  TOMCAT_MANAGER_USER = 'admin'
  TOMCAT_MANAGER_PASSWORD = 'ABc_123!'
  MAX_RETRIES = 12

  PID_DOESNT_EXIST = -1

  attr_reader :restart_count

  def initialize
    @state = UNKNOWN
    @restart_count = 0

    @mutex = Mutex.new
  end

  def manager_listening?
    begin
      req = Net::HTTP::Get.new("/manager/html")
      req.basic_auth(TOMCAT_MANAGER_USER, TOMCAT_MANAGER_PASSWORD)

      response = Net::HTTP.start(HOSTNAME, PORT) {|http|
        http.request(req)
      }

      if response.class == Net::HTTPOK
        LOG.debug('Tomcat manager is listening.')
        return true
      end

    rescue Exception => e
      LOG.warn("#{e.class} : #{e.message}") #TODO: remove
    end

    LOG.debug('Tomcat manager is not listening.');
    return false
  end

  def get_tomcat_pid

    # although "netstat -nlp | grep #{PORT}" would allow me to determine the
    # pid of a specific instance of tomcat listening at PORT, it possible
    # for tomcat never to bind to the PORT and still be running
    out = nil
    pid = PID_DOESNT_EXIST
    IO.popen("ps aux | grep org.apache.catalina.startup.Bootstrap") {|stdout|
      out = stdout.read

      out.split(/\n/).each { |line|

        LOG.debug("line = \"#{line}\"")
        
        if line.include? 'java'
          pid = line.split(" ")[1]
          break
        end
      } if out != nil && !out.empty?
    }

    LOG.debug("tomcat pid is #{pid}")
    return pid
  end

  def running?
    if get_tomcat_pid != PID_DOESNT_EXIST
      LOG.debug("Tomcat is running.")
      return true
    else
      LOG.debug("Tomcat is not running.")
      return false
    end
  end

  def get_restart_count
    @mutex.synchronize {$restart_count}
  end

  def get_state
    @mutex.synchronize {@state}
  end

  private

  def start

    if !running?
      @mutex.synchronize {
        @state = TOMCAT_STARTING
      }

      IO.popen('/home/walsh/apache-tomcat-6.0.20/bin/startup.sh') {|stdout|
        stdout.read
      }

      LOG.info("Tomcat starting...")
    else
      if (manager_listening?)
        # tomcat is up and running and the manager is listening so
        # raise and exception to the start
        raise TomcatAlreadyRunning
      else
        # tomcat appears to be running, but the manager is not listening.
        # force a shutdown, and attempt to start.
        shutdown
        return start
      end
    end

    retries = 0

    LOG.debug("MAX_RETRIES = #{MAX_RETRIES}")

    until (retries +=1) == MAX_RETRIES

      LOG.debug("attempt #{retries} to determine of the manager is listening")

      if (manager_listening?)
        @mutex.synchronize {
          @state = TOMCAT_RUNNING
        }

        LOG.debug("returning true that manager is listing...")
        return true
      else
        LOG.debug("manager_listening? returned false")
      end

      sleep 5
    end

    LOG.debug("throwing tomcat cannot be started...")

    throw TomcatCannotBeStarted.new("#{retries} attempts were made to restart Tomcat")
  rescue Exception => e

    LOG.debug("an exception got thrown; #{e.class} : #{e.message} ; #{e.backtrace.join("\n")}")

    raise e
  end

  def shutdown

    @mutex.synchronize {
      @state = TOMCAT_SHUTTINGDOWN
    }

    pid = get_tomcat_pid

    if pid != PID_DOESNT_EXIST
      IO.popen("kill -9 #{pid}") {|stdout|
        stdout.read
      }
      LOG.info('Shutdown tomcat')
    end

    @mutex.synchronize {
      @state = TOMCAT_SHUTDOWN
    }

    return true
  end
end