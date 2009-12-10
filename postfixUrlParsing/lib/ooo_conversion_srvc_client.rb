#!/usr/local/bin/ruby19

# == Synopsis
#   A client interface to the OOo Conversion Service
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

require 'json'
require 'socket'
require 'logger'
require 'logger_patch'
require 'guid'
require 'timeout'
require 'service_not_available'
require 'conversion_error'

class OOoConversionSrvcClient

  PID_DOESNT_EXIST = -1
  OPENOFFICE_PORT = 8100
  HOSTNAME = 'localhost'
  PORT = 8080

  LOG = Logger.new(STDOUT)
  LOG.level = Logger::DEBUG #DEBUG INFO ERROR WARN
  LOG.datetime_format = "%H:%M:%S"

  def initialize
    
  end

  def process_document_text(stream, input_suffix, output_suffix)

    guid = "#{Guid.new.to_s}"
    input_filename = "#{guid}.#{input_suffix}"
    output_filename = "#{guid}.#{output_suffix}"

    request = {}

    request['inputFilename'] = input_filename
    request['inputBase64FileContents'] = stream.pack('m')
    request['outputFilename'] = output_filename

    client_socket = TCPSocket.new(HOSTNAME, PORT)

    start = Time.now

    client_socket.write(JSON.generate(request))
    client_socket.flush

    buffer = client_socket.read

    response = JSON.parse(buffer)
    client_socket.close

    if (LOG.level == Logger::DEBUG)
      LOG.debug(" => OOoConversioSrvc handled the request in #{Time.now - start} seconds.")
    end

    if ((response['msg'].downcase.index('success') != nil) && (response['outputBase64FileContents'] != nil))
      return response['outputBase64FileContents'].unpack('m')
    else
      raise ConversionError.new(response['msg'])
    end
  end

  def process_office_file(input_filename, output_filename)

    request = {}

    request['inputFilename'] = input_filename
    request['inputBase64FileContents'] = nil
    request['outputFilename'] = output_filename

    client_socket = TCPSocket.new(HOSTNAME, PORT)

    start = Time.now

    client_socket.write(json_request = JSON.generate(request))

    LOG.debug("Request sent to OOoConversionSrvc: #{json_request}")

    client_socket.flush

    buffer = client_socket.read

    LOG.debug("Response from OOoConversionSrvc: #{buffer}")

    response = JSON.parse(buffer)
    client_socket.close

    if (LOG.level == Logger::DEBUG)
      LOG.debug(" => OOoConversioSrvc handled the request in #{Time.now - start} seconds.")
    end

    if (response['msg'].downcase.index('success') != nil)
      return true
    else
      raise ConversionError.new(response['msg'])
    end
  end

  def start
    IO.popen("java -jar ../../OOoConversionSrvc/executable/OOoConversionSrvc-1.0-SNAPSHOT-executable.jar 2>&1 &") unless running?

    Timeout::timeout(60) do
      until (running? && listening?)
        sleep 0.5
      end
      return true
    end
  rescue Timeout::Error
    return false
  end

  alias :start_ooo_conversion_srvc :start

  def stop
    IO.popen("kill #{get_ooo_conversion_srvc_pid}") unless running?

    Timeout::timeout(60) do
      until (!running?)
        sleep 0.5
      end

      return true
    end
  rescue Timeout::Error
    return false
  end

  alias :stop_ooo_conversion_srvc :stop

  def restart

    start if stop
  end

  alias :restart_ooo_conversion_srvc :restart

  def running?
    begin
      get_ooo_conversion_srvc_pid
      LOG.debug("OOoConversionSrvc is running.")
      return true
    rescue ServiceNotAvailable
      LOG.debug("OOoConversionSrvc is not running.")
      return false
    end
  end

  def listening?
    begin
      client_socket = TCPSocket.new(HOSTNAME, PORT)
      client_socket.close
      LOG.debug('OOoConversionSrvc is listening.')
      return true
    rescue Exception => e
      LOG.debug("#{e.class} : #{e.message}")
    end

    LOG.debug('OOoConversionSrvc is not listening.')
    return false
  end

  private

  def get_openoffice_pid

    # although "netstat -nlp | grep #{openoffice_port" would allow me to
    # determine the pid for openoffice it possible that openoffice never
    # binded to the OPENOFFICE_PORT and is still running

    out = nil
    IO.popen("ps aux | grep \"/usr/lib64/openoffice.org3/program/soffice.bin\" | awk '{print $2}'") {|stdout|
      out = stdout.read

      return out if out != nil && !out.empty?
    }

    raise ServiceNotAvailable.new('OOo daemon unavailable.')
  end

  def get_ooo_conversion_srvc_pid

    out = nil
    pid = PID_DOESNT_EXIST
    IO.popen("ps aux | grep OOoConversionSrvc-1.0-SNAPSHOT-executable.jar") do |stdout|
      out = stdout.read

      out.split(/\n/).each { |line|
        if line.include? 'java'
          pid = line.split(" ")[1]
          break
        end
      } if out != nil && !out.empty?
    end

    return pid if pid != PID_DOESNT_EXIST

    raise ServiceNotAvailable.new('OOoConversionSrvc not available.')
  end
end
