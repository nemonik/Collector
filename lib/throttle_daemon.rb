#!/usr/local/bin/ruby19

# A throttle daemon used to limit the number of AMQP messages sent in an
# hour...
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

require 'rubygems'
require 'eventmachine'
require 'sync'
require 'logger'

class Connection < EventMachine::Connection

  def initialize(*args)
    super
    @log = Logger.new(STDOUT)
    @log.level = Logger::DEBUG #ERROR DEBUG INFO
  end

  def post_init
    @log.debug("Received a new connection.")
  end

  def unbind
    @log.debug("Server terminated connection.")
  end

  def receive_data(data)
    @log.debug("recieved: \"#{data.chomp!}\"")

    if data.match(/^add/)
      amount = data.split(' ', 2)[1].to_i

      Throttle_Daemon.set_count(Throttle_Daemon.get_count + amount)

      if (Throttle_Daemon.get_count >= Throttle_Daemon.get_count_to_throttle_at)
        send("closed\n")
      else
        send("open\n")
      end

      close_connection_after_writing
    elsif data.match(/^get count/)
      send("#{Throttle_Daemon.get_count}\n")
      close_connection_after_writing
    elsif data.match(/^get running_count/)
      send("#{Throttle_Daemon.get_running_count}\n}")
      close_connection_after_writing
    elsif data.match(/^uptime/)
      uptime = Time.now - Throttle_Daemon.get_start_time
      send("#{uptime} seconds\n")
      close_connection_after_writing
    else
      send("unknown command\n")
      close_connection_after_writing
    end
  end

  def send(msg)
    @log.debug("sending: #{msg}")

    send_data msg
  end

end

class Throttle_Daemon

  def initialize(port, seconds_to_hold_count, count_to_throttle_at)

    #@log = Logger.new('/home/walsh/Development/workspace/postfixUrlParsing/lib/throttle.log')
    @@log = Logger.new(STDOUT)
    @@log.level = Logger::DEBUG #ERROR DEBUG INFO

    @port = port

    @@sync = Sync.new

    @@start_time = Time.now
    
    @@count = 0
    @@running_count = 0
    @@count_to_throttle_at = count_to_throttle_at

    @@log.debug("right before thread")		

    count_thread = Thread.new {
      while true
        @@log.debug("seconds_to_hold_count = #{seconds_to_hold_count}")
        sleep seconds_to_hold_count
        @@log.debug("Awaking to reset the count...")
        @@running_count += @@count
        Throttle_Daemon.set_count(0) # reset count
      end
    }

  end

  def self.get_count
    return @@count
  end
  
  def self.get_running_count
    return @@running_count
  end  

   def self.get_count_to_throttle_at
    return @@count_to_throttle_at
  end

  def self.get_start_time
    return @@start_time
  end

  def self.set_count(value)
    @@sync.synchronize(:EX) do
      @@count = value
      @@log.debug("count set to #{value}")
    end
  end

  def run

    EventMachine::run {
      EventMachine::start_server "127.0.0.1", @port, Connection
      @@log.info("Running throttle daemon on #{@port}...")
    }
  rescue Interrupt => e
      puts "Shutting down throttle daemon on #{@port}..."
      SystemExit.new(0)
  rescue Exception => e
      puts "Likely another service running at port 8081..."
      SystemExit.new(1) #TODO: get a better status code value
  end
end

throttle_daemon = Throttle_Daemon.new(8081, 3600, 11288)
throttle_daemon.run