#
#  == Synopsis
#   A module of shared methods used for testing purposes
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

require 'logger_patch'
require 'lorem'
require 'json'
require 'zlib'
require 'guid'

module Utility

  LOG = Logger.new(STDOUT)
  LOG.level = Logger::DEBUG #DEBUG INFO ERROR
  LOG.datetime_format = "%H:%M:%S"

  def increment_search_term_iterator()
    @search_term_iterator += 1
    if (@search_term_iterator > @search_terms.size)
      @search_term_iterator = 0
    end

    return @search_term_iterator
  end

  def increment_url_iterator()
    @url_iterator += 1
    if (@url_iterator > @urls.size)
      @url_iterator = 0
    end

    return @url_iterator
  end
  
  def read_urls_from_file

    LOG.debug("Reading in URLs from #{@urls_filename}")
    f = File.new(@urls_filename)

    f.readlines.map {|url|
      @urls.push(url.chomp)
    }

    f.close
  end
  
  def write_urls_to_file
    f = File.open(@urls_filename, 'w')

    @urls.each { |url|
      f.puts(url)
    }

    f.close

    LOG.debug("wrote #{@urls_filename}")
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

  def initialize_urls(read_from_file, word_count = 1000)

    if (File.exist?(@urls_filename) && (read_from_file))
      read_urls_from_file

    else
      FileUtils.rm @urls_filename if File.exists?(@urls_filename)

      start = Time.now if (LOG.level == Logger::DEBUG)

      load_search_terms

      if (LOG.level == Logger::DEBUG)
        stop = Time.now
        LOG.debug("read in #{@search_terms.size} search terms in #{stop-start} seconds.")
      end

      (1..word_count).each { |i|
        get_urls
      }

      @urls = @urls.uniq.compact
      @urls = @urls.sort_by { rand }

      write_urls_to_file
    end

    LOG.debug("Using #{@urls.size} URLs")
  end

  def generate_random_type_document(folder, max_paragraph_count = 20, max_url_count = 5)

    return generate_document(folder, JODConvert_3_x::DOC_TYPES.keys[rand( JODConvert_3_x::DOC_TYPES.keys.size) - 1], max_paragraph_count, max_url_count)

  end

  def generate_document(folder, doc_type, max_paragraph_count = 20, max_url_count = 5)

    if (JODConvert_3_x::DOC_TYPES[doc_type] == nil)
      raise UnsupportedDocumentType.new("'#{doc_type}' is unsupported document type.")
    end

    doc = case doc_type
    when :txt
      doc = generate_text('text/plain', max_paragraph_count, max_url_count)
    else
      text = generate_text('text/html', max_paragraph_count, max_url_count)
      #LOG.debug("src html document = #{text}")
      @manager.process_document_text(text, 'text/html', 'html', JODConvert_3_x::DOC_TYPES[doc_type], doc_type)
    end

    #LOG.debug("#{doc}")

    if (!Dir.exists?(folder))
      Dir.mkdir(folder)
    end

    file_name = File.join(folder, "#{Guid.new.to_s}.#{doc_type}")

    File.open(file_name, 'wb') {|f| f.write(doc) }

    LOG.debug("wrote #{file_name}")

    return file_name
  rescue Exception => e
    LOG.error("Something bad happended...")
    LOG.error("#{e.class}: #{e.message}")
    LOG.error("#{e.backtrace.join("\n")}")
  end

  def generate_text(html = 'text/plain', max_paragraph_count = 20, max_url_count = 5)

    text = nil

    if (html == 'text/html')
      text = "<html>\n<body>\n"
    else
      text = ''
    end

    paragraph_count = rand(max_paragraph_count) + 1

    LOG.debug("creating a document of #{paragraph_count} paragraphs...")

    (1..paragraph_count).each { |j|

      para_txt = Lorem::Base.new('paragraphs', 1).output

      paragraph = para_txt.split(' ')

      url_count = rand(max_url_count) - 1

      (1..url_count).each {|i|
        increment_url_iterator()

        LOG.debug(" >> adding '<#{@urls[@url_iterator]}>', #{i}/#{url_count} to #{j}/#{paragraph_count} paragraph")

        if (html == 'text/html')
          paragraph.insert(rand(paragraph.size-1), " <a href=\"#{@urls[@url_iterator]}\">#{@urls[@url_iterator]}</a> ")
        else
          paragraph.insert(rand(paragraph.size-1), " #{@urls[@url_iterator]} ")
        end
      }

      LOG.debug(" >> adding #{j}/#{paragraph_count} paragraph to doc")

      if (html == 'text/html')
        text << "<p>"
      end

      text << paragraph.join(' ')

      if (html == 'text/html')
        text << "</p>\n\n"
      else
        text << "\n\n"
      end
    }

    if (html == 'text/html')
      text << "</body>\n</html>"
    end

    return text
  end

  def get_urls
    LOG.debug("calling google search rest api")

    query = ''
    # randomly generate a query string using 2 to 4 words
    (1..(rand(1)+2)).each { |i|
      query << @search_terms[increment_search_term_iterator()] << '+'
    }

    start = Time.now if (LOG.level == Logger::DEBUG)
    headers = {
      'User-Agent' =>	'Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10.5; en-US; rv:1.9.1) Gecko/20090624 Firefox/3.5',
      'Accept' =>	'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language' =>	'en-us,en;q=0.5',
      'Accept-Encoding' =>	'gzip,deflate',
      'Accept-Charset' =>	'ISO-8859-1,utf-8;q=0.7,*;q=0.7',
      'Keep-Alive' => '300',
      'Connection' => 'keep-alive'
    }

    http_proxy = ENV['HTTP_PROXY']

    url_string = "http://ajax.googleapis.com/ajax/services/search/web?v=1.0&q=" << query.chop!

    LOG.debug("url = #{url_string}")

    url = URI.parse(url_string)
    request = Net::HTTP::Get.new(url_string.gsub("http://ajax.googleapis.com",""), headers)

    unless (http_proxy.nil?)
      response = Net::HTTP::Proxy(http_proxy.split(":")[0], http_proxy.split(":")[1]).start(url.host, url.port) {|http|
        response = http.request(request)
      }
    else
      response = Net::HTTP.start(url.host, url.port) {|http|
        response = http.request(request)
      }
    end
    
    if (LOG.level == Logger::DEBUG)
      stop = Time.now
      LOG.debug("google search rest api responded in #{stop-start} seconds.")
    end

    response = Zlib::GzipReader.new(StringIO.new(response.body))

    response = JSON.parse(response.read)

    response['responseData']['results'].each { |item|
      begin
        url = item['url']
        host = URI.parse(url).host
        @urls.push(url) if (!@ignore.include?(host))
      rescue Exception => e
        #  swallow
      end
    }
  rescue Zlib::GzipFile::Error => e
    LOG.error("Expected gzip format.")
    LOG.error("#{response.body}")
  rescue Exception => e
    LOG.error("#{e.class} : #{e.message}\n#{e.backtrace.join("\n")}")
  end
end
