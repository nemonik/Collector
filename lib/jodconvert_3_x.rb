#!/usr/local/bin/ruby19

#
#  == Synopsis
#   A Singleton class to interface to a JODConvert 3.x Web application to
#   process documents and manage the Tomcat servlet engine hosting.
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

require 'net/http'
require 'net/http/post/multipart'
require 'logger'
require 'guid'
require 'tomcat_manager'

class JODCovert_3_x < TomcatManager

  class ConversionError < RuntimeError; end;
  class UnsupportedDocumentType < RuntimeError; end;
  class ServiceNotAvailable < RuntimeError; end;
  class NoOfficeManagerAvailable < RuntimeError; end;

  $doc_types = {:doc=>'application/msword', :docx=>'application/vnd.openxmlformats-officedocument.wordprocessingml.document', :txt=>'text/plain', :rtf=>'text/rtf', :odt=>'application/vnd.oasis.opendocument.text', :pdf=>'application/pdf'}

  $protocol = 'http'
  $hostname = 'localhost'
  $port = 8080
  $webapp_path = '/jodconverter-sample-webapp-3.0-SNAPSHOT'
  $timeout = 300 # matches apache's default timeout

  def process_office_file(file_name, file_mime_type, out_format, out_suffix)

    @log.debug(" => Calling JODConvert 3.x OOo web service to convert #{file_name} to #{out_format}...")

    response_body = handle_jodconvert_3_x_req(UploadIO.new(file_name, file_mime_type), out_format, out_suffix)

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

    url = URI.parse("#{$protocol}://#{$hostname}:#{$port}#{$webapp_path}/converted/document.#{out_suffix}")

    start = Time.now if (@log.level == Logger::DEBUG)
    request = Net::HTTP::Post::Multipart.new(url.path, {"inputDocument"=>upload_io, "outputFormat"=>out_format})

    begin
      retries = 0

      begin
        response = Net::HTTP.start(url.host, url.port) do |http|
          http.read_timeout = $timeout
          http.open_timeout = $timeout
          response = http.request(request)
        end

        if (response.body =~ /javax.servlet.ServletException/)

          @log.error("#{response}")

          if (response.body =~ /no office manager available/)
            raise NoOfficeManagerAvailable.new()
          elsif (response.body =~ /conversion failed/)
            raise ConversionError.new("Jodconvert 3.x OOo web service failed to convert #{file_name} of #{file_mime_type}")
          end
        end

      rescue Errno::ECONNREFUSED
        
        @log.error("Could not connect to Jodconvert 3.x OOo web service")

        if (retries += 1) < 4
          @log.debug("Retrying service request. Attempt #{retries} out a possibe 3.")
          sleep 30 # give the service some time to start
          retry
        else
          @log.error("Tomcat needs to be restart.");
          raise TomcatNeedsToBeStarted.new
        end

      rescue Timeout::Error
        
        @log.error("Jodconvert 3.x OOo web service request timed out.")

        if (retries += 1) < 4
          @log.debug("Retrying service request. Attempt #{retries} out a possibe 3.")
          retry
        else
          @log.error("Tomcat needs a forced restart.");
          raise TomcatNeedsAForcedRestart.new
        end
      end 
      
    rescue NoOfficeManagerAvailable || TomcatNeedsAForcedRestart || TomcatNeedsToBeStarted
      
      if restart
        retry
      else
        log.error("Tomcat cannot be restarted.")
        raise TomcatCannotBeRestarted.new
      end
    end

    if (@log.level == Logger::DEBUG)
      stop = Time.now
      @log.debug(" => Jodconvert 3.x OOo web service responded in #{stop-start} seconds.")
    end

    return response.body
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