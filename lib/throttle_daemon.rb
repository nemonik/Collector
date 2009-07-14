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

      if (Throttle_Daemon.get_count >= 4000)
        send("closed\n")
      else
        send("open\n")
      end

      close_connection_after_writing
    elsif data.match(/^get/)
      send("#{Throttle_Daemon.get_count}\n")
      close_connection_after_writing
    end
  end

  def send(msg)
    @log.debug("sending: #{msg}")

    send_data msg
  end

end

class Throttle_Daemon

  def initialize(port, seconds_to_hold_count)

    #@log = Logger.new('/home/walsh/Development/workspace/postfixUrlParsing/lib/throttle.log')
    @@log = Logger.new(STDOUT)
    @@log.level = Logger::DEBUG #ERROR DEBUG INFO

    @port = port

    @@sync = Sync.new

    @@count = 0

    Thread.new {
      while true
        sleep seconds_to_hold_count
        @log.debug("Awaking to reset the count...")
        Throttle_Daemon.set_count(0) # reset count
      end
    }

  end

  def self.get_count
    return @@count
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

throttle_daemon = Throttle_Daemon.new(8081, 3600)
throttle_daemon.run