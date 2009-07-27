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
require 'mime/types'
require 'rmail'
require 'net/smtp'
require 'fileutils'
require 'Compression'


class Send_Email

  def initialize(urls_filename = '/tmp/urls.txt', samples_folder = '/tmp/samples')

    #@log = Logger.new('/home/walsh/Development/workspace/postfixUrlParsing/lib/generate_docs.log')
    @log = Logger.new(STDOUT)
    @log.level = Logger::DEBUG #DEBUG INFO ERROR
    @log.datetime_format = "%H:%M:%S"

    @urls_filename = urls_filename
    @samples_folder = samples_folder
    @ignore = ['en.wikipedia.org', 'www.answers.com']
    @search_terms = []
    @url_iterator = 0
    @search_term_iterator = 0
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

    @msg_count = 0

    @log.debug("initialized...")

  end

  def initialize_urls(read_from_file, word_count = 1000)

    @log.debug("#{File.exist?(@urls_filename)}")
    @log.debug("#{read_from_file}")
    
    if (File.exist?(@urls_filename) && (read_from_file))
      read_urls_from_file
    
    else
      FileUtils.rm @urls_filename if File.exists?(@urls_filename)
          
      start = Time.now if (@log.level == Logger::DEBUG)

      load_search_terms

      if (@log.level == Logger::DEBUG)
        stop = Time.now
        @log.debug("read in #{@search_terms.size} search terms in #{stop-start} seconds.")
      end

      (1..word_count).each { |i|
        get_urls
      }

      @urls = @urls.uniq.compact
      @urls = @urls.sort_by { rand }

      write_urls_to_file
    end

    @log.debug("Using #{@urls.size} URLs")
  end

  def generate_docs(document_count = 100, max_paragraph_count = 20, max_url_count = 5)

    FileUtils.rm_f @samples_folder if File.exists?(@samples_folder)

    @log.debug("creating #{document_count} document(s)...")

    (0..document_count).each {|i|
      @log.debug("generating #{i}/#{document_count}")
      generate_document(max_paragraph_count, max_url_count)
    }

  end

  def send(from, to, filepaths, compress = false, max_paragraph_count = 20, max_url_count = 5)
    subject = "Sending "

    @log.debug("Creating message object...")
    message = RMail::Message::new
    message.header['From'] = "<#{from}>"
    message.header['To'] = "<#{to}>"
    message.header['Date'] = Time::new.rfc2822

    @log.debug("Creating text part...")
    text_part = RMail::Message::new
    text_part.header['Content-Type'] = 'TEXT/PLAIN; format=flowed; charset=utf-8'
    text_part.body = generate_text('text/plain', max_paragraph_count, max_url_count)

    @log.debug("Creating html part...")
    html_part = RMail::Message::new
    html_part.header['Content-Type'] = 'text/html, charset=utf-8'
    html_part.body = generate_text('text/html', max_paragraph_count, max_url_count)

    attachments = Array.new
    dst = File.join('/tmp', Guid.new.to_s)

    if ((compress) && (filepaths.size > 0) && (rand() > 0.5))

      Dir.mkdir(dst)

      tmp_filepaths = Array.new

      filepaths.each { |filepath|
        FileUtils.cp(filepath, dst)
        tmp_filepaths.push(File.join(dst, File.basename(filepath)))
      }

      if (filepaths.size > 1)
        if (rand() > 0.50)
          dst = File.join(dst, 'archive.zip')
          Compression.zip(dst, tmp_filepaths)
        else
          dst = File.join(dst, 'archive.tar')
          Compression.tar(dst, tmp_filepaths)

          if (rand() > 0.5)
            Compression.gzip([dst])
            dst += '.gz'
          else
            Compression.bzip2([dst])
            dst += '.bz2'
          end
        end
      else
        if ((r = rand()) > 0.66)
          Compression.gzip(tmp_filepaths)
          dst = tmp_filepaths[0] + '.gz'
        elsif (r > 0.33)
          dst = tmp_filepaths[0] + '.zip'
          Compression.zip(dst, tmp_filepaths)
        elsif (r > 0.0)
          Compression.bzip2(tmp_filepaths)
          dst = tmp_filepaths[0] + '.bz2'
        end
      end

      attachment_part = RMail::Message::new

      mime_type = MIME::Types.of(dst).first
      content_type = (mime_type ? mime_type.content_type : 'application/binary')
      filename = File.basename(dst)

      @log.debug("Creating attachment part for #{dst}")

      subject = "#{filename} containing #{filepaths}"

      attachment_part.header['Content-Type'] = "#{content_type}; name=#{filename}"
      attachment_part.header['Content-Transfer-Encoding'] = 'BASE64'
      attachment_part.header['Content-Disposition:'] = "attachment; filename=#{filename}"
      attachment_part.body = [File.open(dst).read].pack('m')

      attachments.push(attachment_part)

      FileUtils.rm_rf(File.dirname(dst))

    else
      filepaths.each {|filepath|
        if File.file? filepath # ignore '.', and '..'
          attachment_part = RMail::Message::new

          mime_type = MIME::Types.of(filepath).first
          content_type = (mime_type ? mime_type.content_type : 'application/binary')
          filename = File.split(filepath)[1]

          @log.debug("Creating attachment part for #{filename}")

          if (attachments.empty?)
            subject += "#{filename}"
          else
            subject += ", #{filename}"
          end

          attachment_part.header['Content-Type'] = "#{content_type}; name=#{filename}"
          attachment_part.header['Content-Transfer-Encoding'] = 'BASE64'
          attachment_part.header['Content-Disposition:'] = "attachment; filename=#{filename}"
          attachment_part.body = [File.open(filepath).read].pack('m')

          attachments.push(attachment_part)
        else
          @log.debug("Skipping #{filepath}")
        end
      }
    end

    if (!attachments.empty?)
      message.header['Subject'] = subject
      message.header['X-Number-of-Attachments'] = attachments.size.to_s
    else
      message.header['Subject'] = subject + "no attachments"
    end

    message.add_part(text_part)
    message.add_part(html_part)

    attachments.each {|attachment|
      message.add_part(attachment)
    }

    smtp = Net::SMTP.start("localhost.localdomain", 25)
    @msg_count += 1
    message.header['X-Count'] = "#{@msg_count}"
    @log.debug("Sending message #{@msg_count}...")
    smtp.send_message message.to_s, from, to
    smtp.finish
  end

  def send_all(from, to, path, sleep_sec = 0, attach_max = 1, compress = false, max_paragraph_count = 20, max_url_count = 5)

    filepaths = Array.new
    attach_count = rand(attach_max)

    at = 0
    entries = Dir.entries(path)
    entries.each { |filename|

      at +=1

      filepath = File.join(path, filename)

      if File.file? filepath

        if (filepaths.size < attach_count)
          filepaths.push(filepath)
        end

        if ((filepaths.size == attach_count) || (at == entries.size))
          @log.debug("sending #{filepaths}")
          @log.debug("===========================")
          send(from, to, filepaths, compress, max_paragraph_count, max_url_count)
          if (sleep_sec == -1)
            random_sleep_sec = rand()
            @log.debug("sleeping #{random_sleep_sec} seconds...")
            sleep(random_sleep_sec)
          else
            @log.debug("sleeping #{sleep_sec} seconds...")
            sleep(sleep_sec)
          end
          @log.debug("===========================")

          filepaths = Array.new
        end
      else
        @log.debug("not sending #{filepath}")
      end
    }
  end

  def keep_sending(from, to, path, sleep_sec = 0, attach_max = 1, compress = false, max_paragraph_count = 20, max_url_count = 5)
    l = 0
    loop do
      @log.debug("starting interation #{l}")
      send_all(from, to, path, sleep_sec, attach_max, compress, max_paragraph_count, max_url_count)
      l += 1
    end
  end

  protected

  def generate_document(max_paragraph_count = 20, max_url_count = 5)

    doc_type = rand(@doc_types.size) - 1

    doc = generate_text('text/plain', max_paragraph_count, max_url_count)

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

  def generate_text(html = 'text/plain', max_paragraph_count = 20, max_url_count = 5)

    if (html == 'text/html')
      doc = "<html>\n<body>\n"
    else
      doc = ''
    end

    paragraph_count = rand(max_paragraph_count) - 1

    (0..paragraph_count).each { |j|

      para_txt = Lorem::Base.new('paragraphs', 1).output

      paragraph = para_txt.split(' ')

      url_count = rand(max_url_count) - 1

      (0..url_count).each {|i|
        increment_url_iterator()

        @log.debug("adding <#{@urls[@url_iterator]}>, #{i}/#{url_count} to #{j}/#{paragraph_count} paragraph")

        if (html == 'text/html')
          paragraph.insert(rand(paragraph.size-1), " <href a=\"#{@urls[@url_iterator]}\">#{@urls[@url_iterator]}</a> ")
        else
          paragraph.insert(rand(paragraph.size-1), " #{@urls[@url_iterator]} ")
        end
      }

      @log.debug("adding #{j}/#{paragraph_count} paragraph to doc")

      if (html == 'text/html')
        doc << "<p>"
      end

      doc << paragraph.join(' ')

      if (html == 'text/html')
        doc << "</p>\n\n"
      else
        doc << "\n\n"
      end
    }

    if (html == 'text/html')
      doc << "</body>\n</html>"
    end

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
    f = File.open(@urls_filename, 'w')

    @urls.each { |url|
        f.puts(url)
    }

    f.close

    @log.debug("wrote #{@urls_filename}")
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

  def get_urls
    @log.debug("calling google search rest api")
    
    query = ''
    # randomly generate a query string using 2 to 4 words
    (1..(rand(1)+2)).each { |i|
      query << @search_terms[increment_search_term_iterator()] << '+'
    }

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

    url_string = "http://ajax.googleapis.com/ajax/services/search/web?v=1.0&q=" << query.chop!
    @log.debug("url = #{url_string}")
    url = URI.parse(url_string)
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
      begin
        url = item['url']
        host = URI.parse(url).host
        @urls.push(url) if (!@ignore.include?(host))
      rescue Exception => e
        #  swallow
      end
    }

  end
end

send_email = Send_Email.new('/tmp/urls.txt', '/tmp/samples')
# read URLs from file if the file exists; otherwise, generate URLs using
# 2000 seed words
send_email.initialize_urls(true, 2000)
# generate 500 docs from the URLs containing up 20 paragraphs each containg up
# 5 urls
#send_email.generate_docs(500, 20, 5)
#generate_docs.send_all('walsh@localhost.localdomain', 'walsh@localhost.localdomain', '/tmp/sample')
send_email.keep_sending('walsh@localhost.localdomain', 'walsh@localhost.localdomain', '/tmp/samples', 1, 4, true, 20, 5)


