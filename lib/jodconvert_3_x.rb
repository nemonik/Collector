#!/usr/local/bin/ruby19

#
#  == Synopsis
#   A Singleton class to interface to a JODConvert 3.x Web application to
#   process documents and manage the Tomcat servlet engine hosting.
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

require 'thread'
require 'net/http'
require 'net/http/post/multipart'
require 'logger_patch'
require 'guid'
require 'tomcat_manager'
require 'conversion_error'
require 'unsupported_document_type'
require 'conversion_error'
require 'service_not_available'
require 'no_office_manager_available'
require 'tomcat_needs_to_be_started'
require 'tomcat_cannot_be_started'
require 'webapp_cannot_be_started'

class JODConvert_3_x < TomcatManager

  DOC_TYPES = {:doc=>'application/msword', :docx=>'application/vnd.openxmlformats-officedocument.wordprocessingml.document', :txt=>'text/plain', :rtf=>'text/rtf', :odt=>'application/vnd.oasis.opendocument.text', :pdf=>'application/pdf'}

  EXPECTED_STATE = {:restart=>WEBAPP_RUNNING, :start=>WEBAPP_RUNNING, :shutdown=>TOMCAT_SHUTDOWN, :stop_webapp=>WEBAPP_STOPPED, :start_webapp=>WEBAPP_RUNNING}

  PROTOCOL = 'http'
  HOSTNAME = 'localhost'
  PORT = 8080
  WEBAPP_PATH = '/jodconverter%2Dsample%2Dwebapp%2D3%2E0%2DSNAPSHOT' #/jodconverter-sample-webapp-3.0-SNAPSHOT
  TIMEOUT = 30 # apache's default timeout is 300
  OPENOFFICE_PORT = 8100


  def initialize
    super
    @waiting = 0
    @waiting_threads = []
  end

  def busy?
    @mutex.synchronize {@running}
  end

  def ask_for(action)
    if (!busy?)

      @mutex.synchronize {@running = true}

      @log.warn("handling thread:#{Thread.current.object_id} asking for \"#{action}\"...")

      begin
        case action
        when :restart then
          restart
        when :start then
          start
        when :shutdown then
          shutdown
        when :start_webapp then
          start_webapp
        when :stop_webapp then
          stop_webapp
        end
      ensure
        @mutex.synchronize {

          @running = false

          @waiting_threads.each { |thread|
            @log.warn("Awaking thread:#{thread.object_id} from wait...")
            thread.run
          }

          @waiting_threads = []

          @log.warn("state is \"#{@state}\", expected \"#{EXPECTED_STATE[action]}\", returning #{@state == EXPECTED_STATE[action]}...")

          return @state == EXPECTED_STATE[action]
        }
      end
    else
      @log.warn("thread:#{Thread.current.object_id} entering wait for \"#{action}\"...")

      @mutex.synchronize {
        @waiting_threads << Thread.current
      }
      
      Thread.stop

      @mutex.synchronize {
        @log.warn("thread:#{Thread.current.object_id} leaving wait, state is \"#{@state}\", expected \"#{EXPECTED_STATE[action]}\", returning #{@state == EXPECTED_STATE[action]}...")
        return @state == EXPECTED_STATE[action]
      }
    end
  end

  def get_openoffice_pid

    # although "netstat -nlp | grep #{openoffice_port" would allow me to
    # determine the pid for openoffice it possible that openoffice never
    # binded to the OPENOFFICE_PORT and is still running

    out = nil
    pid = PID_DOESNT_EXIST
    IO.popen("ps aux | grep \"/usr/lib64/openoffice.org3/program/soffice.bin\"") {|stdout|
      out = stdout.read

      out.split(/\n/).each { |line|
        if line.include? "-accept=socket,host=127.0.0.1,port=#{OPENOFFICE_PORT};urp;"
          pid = line.split(" ")[1]
          break
        end
      } if out != nil && !out.empty?
    }

    @log.debug("openoffice pid is #{pid}")

    return pid
  end

  def process_office_file(file_name, file_mime_type, out_format, out_suffix)

    response_body = handle_jodconvert_3_x_req(UploadIO.new(file_name, file_mime_type), out_format, out_suffix)

    @log.debug(" => Called JODConvert 3.x OOo web service to convert #{file_name} to #{out_format}...")

    return response_body
  end

  def process_document_text(stream, in_mime_type, in_suffix , out_format, out_suffix)

    file_name = "/tmp/#{Guid.new.to_s}.#{in_suffix}"
    file = File.new(file_name, 'w')
    file.puts stream
    file.flush
    file.close

    @log.debug(" => Created temp file #{file_name} to hold #{in_mime_type} data stream for JODConvert 3.x processing...");

    response_body = process_office_file(file_name, in_mime_type, out_format, out_suffix)

    File.delete(file_name)

    return response_body
  end

  # Get the links from the MS Office or OpenOffice document
  def handle_jodconvert_3_x_req(upload_io, out_format, out_suffix)

    #TODO: verify tomcat isn't cacheing prior conversions.

    url = URI.parse("#{PROTOCOL}://#{HOSTNAME}:#{PORT}#{WEBAPP_PATH}/converted/document.#{out_suffix}")

    start = Time.now if (@log.level == Logger::DEBUG)

    retries = MAX_RETRIES

    begin

      request = Net::HTTP::Post::Multipart.new(url.path, {"inputDocument"=>upload_io, "outputFormat"=>out_format})

      begin
        response = Net::HTTP.start(url.host, url.port) do |http|
          http.read_timeout = TIMEOUT
          http.open_timeout = TIMEOUT
          response = http.request(request)
        end

        if (response.class != Net::HTTPOK)
          @log.debug("Service responsed with #{response.class}; #{response.code}; #{response.message}; #{response.body}; Tomcat needs to be restart.")
          raise TomcatNeedsToBeStarted.new("Service responsed with #{response.class}; #{response.code}; #{response.message}; #{response.body}; Tomcat needs to be restart.")
        elsif (response.body =~ /javax.servlet.ServletException/)
          if (response.body =~ /no office manager available/)
            raise NoOfficeManagerAvailable.new("No office manager is available;")
          elsif (response.body =~ /conversion failed/)
            raise ConversionError.new("Jodconvert 3.x OOo web service failed to convert #{file_name} of #{file_mime_type}")
          end
        end

      rescue Exception => e

        if (retries -= 1) == 0
          @log.info(" => #{e.class}: #{e.message}; making another attempt...")
          sleep 5
          @log.debug(" => Retrying Jodconvert 3.x OOo web service; #{retries} retries remain")

          retry
        else
          raise TomcatNeedsToBeStarted.new("#{e.message}; made #{MAX_RETRIES} attempts; Tomcat needs a forced restart")
        end
      end
      
    rescue TomcatNeedsToBeStarted, NoOfficeManagerAvailable => e

      @log.info("#{e.class}: #{e.message}; attempting to restart Tomcat.")

      restart_retries = MAX_RETRIES
      until (restart_retries -= 1) == 0
        if ask_for(:restart)
          @log.debug("appears to be running, attempting a retry")
          retry
        end
      end

      raise TomcatCannotBeStarted.new("Tried to restart #{MAX_RETRIES} times; Tomcat cannot be restarted.")
      
    end

    if (@log.level == Logger::DEBUG)
      stop = Time.now
      @log.debug(" => Jodconvert 3.x OOo web service handled the request in #{stop-start} seconds.")
    end

    return response.body

  rescue Timeout::Error
    raise TomcatCannotBeStarted.new('Restart timed out; Tomcat cannot be restarted.')
  end

  def running?
    if super
      if (get_openoffice_pid != PID_DOESNT_EXIST)
        return true
      else
        return false
      end
    else
      return false
    end
  end

  def webapp_listening?
    begin
      response = Net::HTTP.get_response(HOSTNAME, "#{WEBAPP_PATH}/", PORT)
      
      @log.debug("#{response.class} : #{response.message}")

      if response.class == Net::HTTPOK
        @log.debug('Webapp is listening.')
        return true
      end
    rescue Exception => e
      @log.debug("#{e.class} : #{e.message}")
    end

    @log.debug('Webapp is not listening.')
    return false
  end



  private

  def restart
    if shutdown
      if start
        return true
      else
        false
      end
    else
      false
    end
    # todo: remove rescue
  rescue exception => e
    @log.error("#{e.class}: #{e.message}")
    @log.error("#{e.backtrace.join("\n")}")
    raise e
  end
  
  def start_webapp

    begin
      @mutex.synchronize {
        @state = WEBAPP_STARTING
      }

      req = Net::HTTP::Get.new("/manager/html/start?path=#{WEBAPP_PATH}")
      req.basic_auth(TOMCAT_MANAGER_USER, TOMCAT_MANAGER_PASSWORD)

      response = Net::HTTP.start(HOSTNAME, PORT) {|http|
        http.request(req)
      }

      if response.class == Net::HTTPOK

        # the manager kicked the webapp off, now poll 'til up and running.

        retries = MAX_RETRIES
        listening = false
        until (retries -= 1) == 0
          if (webapp_listening?)
            listening = true
            break
          end

          sleep 5
        end

        if listening

          @mutex.synchronize {
            @state = WEBAPP_RUNNING
            @restart_count += 1
          }

          @log.debug("JODConvert 3.x Web Service started.")

          return true
        end
      end
    rescue Exception
    end

    @mutex.synchronize {
      @state = WEBAPP_UNKNOWN
    }

    @log.debug("JodConvert 3.x Web Service failed to start.")
    return false
  end

  def stop_webapp

    begin
      @mutex.synchronize {
        @state = WEBAPP_STOPPING
      }
      req = Net::HTTP::Get.new("/manager/html/stop?path=#{WEBAPP_PATH}")
      req.basic_auth(TOMCAT_MANAGER_USER, TOMCAT_MANAGER_PASSWORD)

      response = Net::HTTP.start(HOSTNAME, PORT) {|http|
        http.request(req)
      }

      if response.class == Net::HTTPOK
        @log.debug('JODConvert 3.x Web Service stopped.')
        @mutex.synchronize {
          @state = WEBAPP_STOPPED
        }
        return true
      end
    rescue Exception => e
    end

    @mutex.synchronize {
      @state = WEBAPP_UNKNOWN
    }

    @log.debug('Failed to stop JODConvert 3.x Web Service')
    return false
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
      @log.info('Shutdown tomcat')
    end

    pid = get_openoffice_pid

    if pid != PID_DOESNT_EXIST
      IO.popen("kill -9 #{pid}") {|stdout|
        stdout.read
      }
      @log.info('Shutdown OpenOffice')
    end

    @mutex.synchronize {
      @state = TOMCAT_SHUTDOWN
    }

    return true
  end

  def start

    @log.debug("entered jodconvert_3_x start");

    begin
      super
    rescue TomcatAlreadyRunning => e
      @log.debug(e.message)
    end

    @log.debug("does jodconvert_3_x need to start the webapp?")

    # then, if needed start the webapp
    if (!webapp_listening?)
      return start_webapp
    else
      # otherwise it is listening, update the state and increment restart_count
      @mutex.synchronize {
        @state = WEBAPP_RUNNING
        @restart_count += 1
      }
      
      return true
    end
  end

end

#
#threads = []
#
#5.times { |i|
#  threads << Thread.new(i) {
#    puts "#{Thread.current.object_id} : started thread #{i}"
#    manager = JODCovert_3_x.instance
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

#manager = JODCovert_3_x.instance
#puts("#{manager.listening?}")
