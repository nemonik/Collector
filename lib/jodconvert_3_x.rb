#
#  == Synopsis
#   A module to interface to a JODConvert 3.x Web application to process
#   documents.
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

require 'net/http'
require 'net/http/post/multipart'
require 'logger'
require 'guid'
require 'socket'

module JODCovert_3_x

  class ConversionError < RuntimeError; end;
  class UnsupportedDocumentType < RuntimeError; end;
  class ServiceNotAvailable < RuntimeError; end;

  $doc_types = {:doc=>'application/msword', :docx=>'application/vnd.openxmlformats-officedocument.wordprocessingml.document', :txt=>'text/plain', :rtf=>'text/rtf', :odt=>'application/vnd.oasis.opendocument.text', :pdf=>'application/pdf'}

  $webapp_path = '/jodconverter-sample-webapp-3.0-SNAPSHOT'

  def jodconvert_3_x_running?
    socket = TCPSocket.open("localhost", 8080)
    socket.print("GET #{$webapp_path} HTTP/1.0\r\n\r\n")
    socket.read

    return true
  rescue Exception => e
    raise ServiceNotAvailable.new("#{e}; The JODConvert 3.x Web service is not running; Start Apache Tomcat.")
  ensure
    socket.close if socket
  end

  def process_office_file(file_name, file_mime_type, out_format, out_suffix)

    @log.debug(" => Calling JODConvert 3.x OOo web service to convert #{file_name} to #{out_format}...")

    response_body = handle_jodconvert_3_x_req(UploadIO.new(file_name, file_mime_type), out_format, out_suffix)

    if (response_body =~ /javax.servlet.ServletException/)
      raise ConversionError.new("Jodconvert 3.x OOo web service failed to convert #{file_name} of #{file_mime_type}")
    end

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

    url = URI.parse("http://localhost:8080#{$webapp_path}/converted/document.#{out_suffix}")

    start = Time.now if (@log.level == Logger::DEBUG)

    request = Net::HTTP::Post::Multipart.new(url.path, {"inputDocument"=>upload_io, "outputFormat"=>out_format})

    response = Net::HTTP.start(url.host, url.port) do |http|
      #http.read_timeout = 500
      #http.open_timeout = 500
      response = http.request(request)
    end
    
    if (@log.level == Logger::DEBUG)
      stop = Time.now
      @log.debug(" => Jodconvert 3.x OOo web service responded in #{stop-start} seconds.")
    end

    return response.body
  rescue Exception => e
    @log.error("#{e}")
    SystemExit.new
  end
end
