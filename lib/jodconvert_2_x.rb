#!/usr/local/bin/ruby19

#
#  == Synopsis
#   A Singleton class to interface to a JODConvert 2.x Web application to
#   process documents and manage the Tomcat servlet engine hosting.
#
# TODO: not as complete at the 3.x version
#
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

require 'net/http'
require 'logger'
require 'TomcatManager'


class JODConvert_2_x < TomcatManager

  $PROTOCOL = 'http'
  $HOSTNAME = 'localhost'
  $PORT = 8080
  $openoffice_port = 8100
  $WEBAPP_PATH = '/jodconverter-webapp-2.2.2/service'

  def process_office_doc(file_name, mime_type, accept)

    @log.debug(" => calling Jodconvert 2.x OOo web service to process #{file_name}")

    doc = File.open(file_name,"rb") {|io| io.read}

    return handle_req(log, doc, mime_type, accept)
  end

  # Get the links from the MS Office or OpenOffice document
  def handle_jodconvert_2_x_req(text, mime_type, accept)

    start = Time.now if (log.level == Logger::DEBUG)
    headers = {
      'Content-Type' => mime_type,
      'Accept' => accept
    }

    url = URI.parse("#{$PROTOCOL}://#{$HOSTNAME}:#{$PORT}#{$WEBAPP_PATH}")

    request = Net::HTTP::Post.new(url.path, headers)
    request.body = text

    response = Net::HTTP.start(url.host, url.port) {|http|
      response = http.request(request)
    }

    if (log.level == Logger::DEBUG)
      stop = Time.now
      @log.debug(" => Jodconvert 2.x OOo web service responded in #{stop-start} seconds.")
    end

    return response.body

  end
end
