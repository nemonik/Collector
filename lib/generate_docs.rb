#!/usr/local/bin/ruby19

# == Synopsis
#   A script to randomly generate attachments for the purposes of testing
#
# == Usage:  Start_OOo.rb {start/stop}
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

require 'logger'
require 'lorem'
require 'json'
require 'uri'
require 'net/http'
require 'stringio'
require 'zlib'
require 'open-uri'
require 'guid'


class Generate_Docs

  def initialize

    #@log = Logger.new('/home/walsh/Development/workspace/postfixUrlParsing/lib/generate_docs.log')
    @log = Logger.new(STDOUT)
    @log.level = Logger::DEBUG #DEBUG INFO ERROR

    @urls_filename = '/tmp/urls.txt'
    @samples_folder = '/tmp/samples'
    @ignore = ['en.wikipedia.org', 'www.answers.com']
    @search_terms = []
    @iterator = 0
    @urls = []
    @doc_types = ['application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'text/plain', 
      'text/rtf',
      'application/vnd.oasis.opendocument.text',
      'application/pdf']
# cannot be converted to
#      'application/vnd.ms-powerpoint',
#      'application/vnd.openxmlformats-officedocument.presentationml.presentation']

    @doc_file_extension = ['doc', 'docx', 'txt', 'rtf', 'odt', 'pdf']

    if (File.exist?(@urls_filename))
      read_urls_from_file
    else

      start = Time.now if (@log.level == Logger::DEBUG)

      load_search_terms

      if (@log.level == Logger::DEBUG)
        stop = Time.now
        @log.debug("read in #{@search_terms.size} search terms in #{stop-start} seconds.")
      end

      (1..500).each { |i|
        get_urls
      }

      @urls = @urls.sort_by { rand }
      puts @urls.size

      write_urls_to_file
    end

    @log.debug("Using #{@urls.size} URLs")

    doc = generate_text

    document_count = rand(100) - 1

    @log.debug("creating #{document_count} document(s)...")
    
    (0.. document_count).each {|i|
      @log.debug("generating #{i}/#{document_count}")
      generate_document(doc)
    }
  end

  protected

  def generate_document(doc)

    doc_type = rand(@doc_types.size) - 1

    doc = generate_text

    if (doc_type != 'text/plain')
      if (doc_type == 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
        doc = create_office_doc(create_office_doc(doc, 'text/plain', 'application/msword'),'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
      elsif (doc_type == 'text/rtf')
        doc = create_office_doc(doc, 'text/plain', 'text/rtf')
      else
        doc = create_office_doc(doc, 'text/plain', @doc_types[doc_type])
      end
    end

    if (!Dir.exists?(@samples_folder))
       Dir.mkdir(@samples_folder)
    end

    filename = File.join(@samples_folder, Guid.new.to_s + '.' + @doc_file_extension[doc_type])

    File.open(filename, 'wb') {|f| f.write(doc) }

    @log.debug("wrote #{filename}")
  end


  def create_office_doc(doc, content_type, accept)
    # TODO: Handle Excel documents.

    @log.debug("calling OOo web service to create document...")

    start = Time.now if (@log.level == Logger::DEBUG)
    headers = {
      'Content-Type' => content_type,
      'Accept' => accept
    }

    url = URI.parse('http://localhost:8080/converter/service')
    request = Net::HTTP::Post.new(url.path, headers)
    request.body = doc

    response = Net::HTTP.start(url.host, url.port) {|http|
      response = http.request(request)
    }

    if (@log.level == Logger::DEBUG)
      stop = Time.now
      @log.debug("OOo web service responded in #{stop-start} seconds.")
    end

    return response.body

  end

  def generate_text
    url_iterator = 0
    doc = ''

    paragraph_count = rand(20) -1

    (0..paragraph_count).each { |j|

      para_txt = Lorem::Base.new('paragraphs', 1).output

      paragraph = para_txt.split(' ')

      url_count = rand(5) - 1

      (0..url_count).each {|i|
        url_iterator += 1

        if (url_iterator > @urls.size)
            url_iterator =0
        end

        @log.debug("adding #{@urls[url_iterator]} to #{i} paragraph")
        paragraph.insert(rand(paragraph.size-1), " #{@urls[url_iterator]} ")
      }

      @log.debug("adding #{j}/#{paragraph_count} to doc")

      doc << paragraph.join(' ')
      doc << "\n\n"
    }

    return doc
  end

  def read_urls_from_file

      @log.debug("Reading in URLs from #{@urls_filename}")
      f = File.new(@urls_filename)

      f.readlines.map {|url|
        @urls.push(url.chomp)
      }

      f.close
  end

  def write_urls_to_file
    f = File.open('/tmp/url.txt', 'w')

    @urls.each { |url|
        f.puts(url)
    }

    f.close
  end

  def load_search_terms
    f = File.new('/usr/share/dict/words')

    f.readlines.map {|word|
      @search_terms.push(word.chomp)
    }

    # randomize search_terms
    @search_terms = @search_terms.sort_by { rand }

    f.close
  end

  def get_urls
    @log.debug("calling google search rest api")

    @iterator += 1

    start = Time.now if (@log.level == Logger::DEBUG)
    headers = {
      'User-Agent' =>	'Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.5; en-US; rv:1.9.1) Gecko/20090624 Firefox/3.5',
      'Accept' =>	'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language' =>	'en-us,en;q=0.5',
      'Accept-Encoding' =>	'gzip,deflate',
      'Accept-Charset' =>	'ISO-8859-1,utf-8;q=0.7,*;q=0.7',
      'Keep-Alive' => '300',
      'Connection' => 'keep-alive'
    }

    url_string = "http://ajax.googleapis.com/ajax/services/search/web?v=1.0&q=#{@search_terms[@iterator]}"
    url = URI.parse(url_string)
    @log.debug("url = #{url_string}")
    request = Net::HTTP::Get.new(url_string, headers)

    response = Net::HTTP.start(url.host, url.port) {|http|
      response = http.request(request)
    }

    if (@log.level == Logger::DEBUG)
      stop = Time.now
      @log.debug("google search rest api responded in #{stop-start} seconds.")
    end

    response = Zlib::GzipReader.new(StringIO.new(response.body))

    response = JSON.parse(response.read)

    response['responseData']['results'].each { |item|
      url = item['url']
      host = URI.parse(url).host
      @urls.push(url) if (!@ignore.include?(host))
    }

  end
end

generate_docs = Generate_Docs.new

