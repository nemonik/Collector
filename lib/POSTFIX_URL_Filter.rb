#!/bin/usr/local/ruby19

# == Synopsis
#   A POSTFIX script that filters email for URLs and sends the URLs off to
#   RabbitMQ queue to be later processed.
#
# == Usage:  postfix_url_filter.rb [options] AMQP_queue
#
# A POSTFIX script that filters email for URLs and sends the URLs off to
# RabbitMQ queue to be later processed.
#
# == Examples:
#    cat email.eml > main.rb
#    cat email.eml > main.rb jobs
#    cat email.eml > main.rb --host localhost --port 5672 --user quest --password quest jobs
#
# == Common options:
#    -v, --version                    display version number and exit.
#    -V, --[no-]verbose               run verbosely.
#    -h, --help                       display this help and exit.
#
# == AMQP server options:
#    -H, --host HOST                  set host to HOST
#    -P, --port PORT                  set port to PORT
#    -u, --user USER                  set login to USER.
#    -p, --password PASSWORD          set password to PASSWORD.
#
# == Actions:
#    -l, --[no-]amqp_logging          enable AMQP server interaction logging.
#        --use [PARSER]               select PARSER for HTML/XML (uri, hpricot, nokogiri)
#    -I, --ingore_attachments         ignore attachments, don't parse them.
#
# == Author
#   Michael Joseph Walsh
#
# == Copyright
#   Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.

require 'optparse'
require 'ostruct'
require 'date'
require 'rmail'
require 'pp'
require 'uri'
require 'hpricot'
require 'nokogiri'
require 'guid'
require 'mq'
require 'json'
require 'fileutils'
require 'socket'
require 'logger'
require 'Compression'

class POSTFIX_URL_Filter
  VERSION = '0.0.1'

  attr_reader :options

  def initialize(arguments, stdin)
    @arguments = arguments
    @stdin = stdin

    @recipients = []
    @links = []

    @log = Logger.new(STDOUT)
    @log.level = Logger::DEBUG
    @log.datetime_format = "%H:%M:%S"

    # Set defaults
    @options = OpenStruct.new
    @options.verbose = true
    @options.amqp_logging = false
    @options.use = 'nokogiri'
    @options.amqp_host = 'localhost'
    @options.amqp_port = '5672'
    @options.amqp_user = 'guest'
    @options.amqp_password = 'guest'
    @options.tmp_folder_for_attachments = "/home/walsh/tmp"
    @options.uri_schemes = ['http', 'https', 'ftp', 'ftps']
    @options.ignore_attachments = false
  end

  # Parse options, check arguments, then process the email
  def run

    if parsed_options?
      if arguments_valid?

        start_time = Time.now
        @log.info("Start at #{start_time}") if @options.verbose

        output_options if @options.verbose # [Optional]

        process_arguments
        process_email(process_standard_input)  # process email from standard input
        send_to_amqp_queue 

        finish_time = Time.now
        if @options.verbose
          @log.info("Finished at #{finish_time}")
          @log.info("Ran in #{finish_time - start_time} seconds")
        end
      else
        @log.error("invalid arguments")
      end
    else
      @log.error("invalid options")
    end

  end

  #protected

  def parsed_options?

    # Specify options
    option_parser = OptionParser.new { |opts|

      opts.banner = "Usage:  #$0 [options] AMQP_queue"

      explanation = <<-EOE

A POSTFIX script that filters email for URLs and sends the URLs off to
RabbitMQ queue to be later processed.


Examples:
    cat email.eml > main.rb
    cat email.eml > main.rb jobs
    cat email.eml > main.rb --host localhost --port 5672 --user quest --password quest jobs
      EOE

      opts.separator(explanation)

      opts.separator('')
      opts.separator('Common options:')

      opts.on('-v', '--version', 'display version number and exit.') {output_version ; exit 0 }
      opts.on("-V", "--[no-]verbose", "run verbosely.") { |v|
        @options.verbose = v
      }

      opts.on('-h', '--help', 'display this help and exit.') do
        puts opts
        exit
      end

      opts.separator('')
      opts.separator('AMQP server options:')

      opts.on('-H', '--host HOST', 'set host to HOST') { |string| @options.amqp_host = string }

      opts.on('-P', '--port PORT', 'set port to PORT') { |string| @options.amqp_port = string }

      opts.on('-u', '--user USER', 'set login to USER.') { |string| @options.user = string }

      opts.on('-p', '--password PASSWORD', 'set password to PASSWORD.') {|string| @options.password = string }

      opts.separator('')
      opts.separator('Actions:');

      opts.on('-l', '--[no-]amqp_logging', 'enable AMQP server interaction logging.') { |l|
        @options.amqp_logging = l
      }

      opts.on("--use [PARSER]", [:uri, :hpricot, :nokogiri], "select PARSER for HTML/XML (uri, hpricot, nokogiri)") { |p|
         @options.use = p
      }

      opts.on('-I', '--ignore_attachments', 'don\'t parse attachments') {|i|
        @options.ignore_attachments = i
      }

    }

    option_parser.parse!(@arguments) rescue return false

    #post_process_options

    true
  end

  # Dump command-line options
  def output_options
    @log.info("Options:")

    @options.marshal_dump.each do |name, val|
      @log.info("  #{name} = #{val}")
    end
  end

  # Performs post-parse processing on options
  def process_options

  end

  # True if required arguments were provided
  def arguments_valid?

    true if ((@arguments.length >= 0) && (@arguments.length <= 1))

  end

  # Setup the arguments
  def process_arguments

    @options.amqp_queue = @arguments.length == 1 ? @arguments[0] : 'jobs'

  end

  # Output the version
  def output_version

    puts "#{File.basename(__FILE__)} version #{VERSION}"

  end

  # Process the email, pulling out all the unique URLs and send to AMQP
  # server to be later be processed
  def process_email(msg_text)

    message = RMail::Parser.read(msg_text)

    header = message.header

    @from = RMail::Address.parse(header['from'])

    @subject = header['subject'].to_s

    @subject = '(no subject)' if @subject.size == 0

    @message_id = (header['Message-ID'] != nil) ? header['Message-ID'] : Guid.new.to_s
    
    @recipients.concat(RMail::Address.parse(header['to']) + RMail::Address.parse(header['cc'])) #RMail::Address.parse(header.match(/^(to|cc)/, //))) Should work, but doesn't.

    message.each_part { |part|

      header = part.header

      doc = (header['Content-Transfer-Encoding'] == 'quoted-printable') ? part.body.unpack('M')[0] : part.body

      @log.debug('====================')

      if ((header['Content-Type'].downcase.include? 'text/plain') && (!header.has_key?('Content-Disposition')))

        @log.debug('handling plain text part...')

        get_links_with_uri(doc)

      elsif ((header['Content-Type'].downcase.include? 'text/html') && (!header.has_key?('Content-Disposition')))
        @log.debug('handling html part...')

        get_links(doc)

      elsif ((header.has_key?('Content-Disposition')) && (header['Content-Disposition'].downcase.include? 'attachment') && (!@options.ignore_attachments))

        @log.debug('message has an attachment...')

        if (header['Content-Transfer-Encoding'].downcase.include? 'base64')

          @log.debug("handling base64 attachment...")

          # create unique directory to hold the file for processing, and allow for easy cleanup
          folder_name = @options.tmp_folder_for_attachments + "/" + Guid.new.to_s
          Dir.mkdir(folder_name)

          file_name = File.join(folder_name, header['Content-Type'].chomp.split(/;\s*/)[1].split(/\s*=\s*/)[1].gsub(/\"/, ""))

          file = File.new(file_name, 'w')

          file.syswrite(doc.unpack("m")[0]) # base64 decode and write out

          file.close

          process_file(file_name)

          # clean up temp files
          FileUtils.rm_rf(folder_name)
        else
          @log.warn("Unhandled content-transfer-encoding #{header['Content-Transfer-Encoding']}")
        end

      elsif (header['Content-Type'].downcase.include? 'message/rfc822')

        @log.debug('handling forwarded email...')

        process_email(doc)

      else # handle unknown content-type

        @log.warn("Unhandled content-type #{header['Content-Type']}")

      end if ((doc.class != NilClass) && (doc.strip != ''))
    } if (message.multipart?)
  end

  def process_file(file_name)

    @log.debug("writing file #{file_name}...")

    file_type = mime_shared_info(file_name)

    @log.debug("file is  \"#{file_type}\"...")

    if ('Microsoft Office Document, OpenOffice Document'.match("#{file_type}"))
      get_links_from_office_doc(file_name)
    elsif (file_type == 'PDF Document')
      get_links_with_uri(`pdftotext #{file_name} /dev/stdout`)
    elsif (file_type == 'text')
      get_links_with_uri(File.open(file_name).read)
    elsif (file_type == 'XML document')
      get_links(File.open(file_name).read)
    elsif (file_type == 'Zip archive')
      process_compressed(file_name, 'zip')
    elsif (file_type == 'gzip compressed data')
      process_compressed(file_name, 'gzip')
    elsif (file_type == 'bzip2 compressed data')
      process_compressed(file_name, 'bzip2')
    elsif (file_type == 'tar archive')
      process_compressed(file_name, 'tart')
    end
  end

  def process_compressed(file_name, compression)

    @log.debug("processing #{compression} compressed #{file_name}...")

    dst = File.join(File.dirname(file_name), Guid.new.to_s)
    Dir.new(dst)
    FileUtils.cp(file_name, dst)

    tmp_file_name = File.join(dst, File.basename(file_name))

    if (compression == 'zip')
      Compression.unzip(tmp_file_name, dst)
    elsif (compression == 'gzip')
      Compression.gunzip(tmp_file_name)
    elsif (compression == 'bzip2')
      Compression.bunzip2(tmp_file_name)
    elsif (compression == 'tar')
      Compression.untar(tmp_file_name, dst)
    else
      @log.error("#{compression} unhandled form of compression")
    end

    FileUtils.rm(tmp_file_name)

    Dir.foreach(dst) { |file_name|
      file_name = File.join(dst, file_name)

      process_file(file_name) if file_name.file?
    }

  end

  def mime_shared_info(file_name)

    file_output = `file -kb \"#{file_name}\"`.gsub(/\n/,"")
    
    @log.debug("'file -kb \"#{file_name}\"\' returns \"#{file_output}\", determining file type...")
    
    if (file_output.downcase.match(/microsoft/))
      return 'Microsoft Office Document'
    elsif (file_output.downcase.match(/opendocument/))
      return 'OpenOffice Document'
    elsif (file_output.downcase.match(/pdf/))
      return 'PDF Document'
    elsif (file_output.downcase.match(/xml/))
      return 'XML document'
    elsif (file_output.downcase.match(/text/))
      return 'text'
    elsif (file_output.downcase.match(/zip archive data/))

      @log.debug("determining file type from file extension...")
      
      # Determine if Office Open XML format
      if (".pptx, .docx, .xlsx".match(File.extname(file_name)))
        return 'Microsoft Office Document'
      else
        return 'Zip archive'
      end

    elsif (file_output.downcase.match(/gzip compressed data/))
      return 'gzip compressed data'
    elsif (file_output.downcase.match(/tar archive/))
      return 'tar archive'
    elsif (file_output.downcase.match(/bzip2 compressed data/))
      return 'bzip2 compressed data'
    end
  end

  def get_links_from_office_doc(file_name)
    # TODO: Handle Excel documents.

    # run open office converter macro
    IO.popen("/usr/lib64/openoffice.org3/program/soffice -invisible \"macro:///HoneyClient.Conversion.ConvertToHTML(#{file_name})\"") { |io|
      @log.info("#{io.read}")  # shouldn't really return anything
    }

    # handle hmtl, if the doc was ms word-like
    file_name = file_name + ".html"
    if File.exists?(file_name)
      @log.debug("reading #{file_name}")
      get_links(File.open(file_name).read)
    end

    # handle html, if the doc was ms powerpoint-like
    folder_name = File.dirname(file_name)
    Dir.foreach(folder_name) {|f|
      file_name = File.join(folder_name, f)
      if ((f.match(/^text/)) && (f.match(/.html$/)))
        @log.debug("reading #{file_name}")
        get_links(File.open(file_name).read)
      end
    }
  end

  # send off to AMQP queue
  def send_to_amqp_queue

    # strip off dupes
    @log.debug("URL count before compact #{@links.size}")
    @links = @links.uniq.compact
    @log.debug("Sending #{@links.size} links to amqp server #{@links}...")

    time = Time.new

    # create job_source
    job_source = {}
    job_source['name'] = Socket.gethostname
    job_source['protocol'] = 'smtp'

    # create job
    job = {}
    job['uid'] = @message_id
    job['url_count'] = @links.size
    job['created_at'] = time
    job['update_at'] = time
    job['job_source'] = job_source

    urls = []

    url_status = {}
    url_status['satus'] = 'queued'

    @links.map {|link|
      url = {}
      url['url'] = link
      url['priority'] = 1
      url['url_status'] = url_status

      urls.push(url)
    }

    job['urls'] = urls

    job_alerts = []

    # foreach recipient create a job_alert and add
    @recipients.each { |recipient|
      job_alert = {}
      job_alert['protocol'] = 'smtp'
      job_alert['address'] = recipient.address

      job_alerts.push(job_alert)
    }

    #job['job_alerts'] = job_alerts

    # publish message to RabbitMQ
    AMQP.start(:host => @options.amqp_host, :port => @options.amqp_port,:user => @options.amqp_user, :password => @options.amqp_password, :logging => @options.amqp_logging) do
      MQ.queue(@options.amqp_queue, :durable => true).publish(JSON.pretty_generate job, :persistent => true)
      # todo: need to set send to a exchange, using a routing a key...
      AMQP.stop { EM.stop }
    end
  end

  # select the method to parse out URLs
  def get_links(text)
    if (@options.use == 'uri')
      get_links_with_uri(text)
    elsif (@options.use == 'hpricot')
      get_links_with_hpricot(text)
    elsif (@options.use == 'nokogiri')
      get_links_with_nokogiri(text)
    end
  end

  # retrieves all URLs in the text described by @options.uri_schema
  def get_links_with_uri(text)
    @log.debug("using URI to extract URLs...")

    URI.extract(text, @options.uri_schemes) {|url|
      @links.push(url.gsub(/\/$/,'').gsub(/\)$/, '').gsub(/\>/,'')) #TODO: need a better regex
    }
  end

  # can be tuned to be more pecific as to what URLs are retrieved from HTML
  def get_links_with_hpricot(text)

    @log.debug("using hpricot to parse...")

    if ((text.class != NilClass) && (text.strip != ''))
      # the version of hpricot I developed against
      # is not attribute case insensitive
      text = text.gsub(/\sHREF/, ' href')
      text = text.gsub(/\sSRC/, ' src')

      # parse HTML content after fixing up content
      html = Hpricot(text, :fixup_tags => true)
      
      # pull URLs from anchor tags
      html.search('//a').map { |a|

        @log.debug("#{a}")

        if (a['href'] != nil)
          url = URI.extract(a['href'], @options.uri_schemes)[0]
          @links.push(url.gsub(/\/$/,'')) if url
        end
      }

      # pull URLs from img tags
      html.search('//img').map { |img|

         @log.debug("#{img}")

        if (img['src'] != nil)
          url = URI.extract(img['src'], @options.uri_schemes)[0]
          @links.push(url.gsub(/\/$/,''))  if url
        end
      }
    end
  end

  # can be tuned to be more specific as to what URLs are retrieved from HTML
  def get_links_with_nokogiri(text)

    @log.debug("using nokogiri to parse...")

    if ((text.class != NilClass) && (text.strip != ''))
      html = Nokogiri::HTML(text)

      # pull URLs from anchor tags
      html.xpath('//a').map { |a|
        if (a['href'] != nil)
          url = URI.extract(a['href'], @options.uri_schemes)[0]
          @links.push(url.gsub(/\/$/,'')) if url
        end
      }

      # pull URLs from img tags
      html.xpath('//img').map { |img|
        if (img['src'] != nil)
          url = URI.extract(img['src'], @options.uri_schemes)[0]
          @links.push(url.gsub(/\/$/,''))  if url
        end
      }
    end
  end

  def process_standard_input
    #@stdin.read

    #IO.read('../test/Sample_csv.msg') if (File.exists?('../test/Sample_csv.msg'))
    #IO.read('../test/Sample_docx.msg') if (File.exists?('../test/Sample_docx.msg'))
    #IO.read('../test/Sample_odt.msg') if (File.exists?('../test/Sample_odt.msg'))
    #IO.read('../test/Sample_ppt.msg') if (File.exists?('../test/Sample_ppt.msg'))
    #IO.read('../test/Sample_RTF.msg') if (File.exists?('../test/Sample_rtf.msg'))
    #IO.read('../test/Sample_doc.msg') if (File.exists?('../test/Sample_doc.msg'))
    #IO.read('../test/Sample_html.msg') if (File.exists?('../test/Sample_html.msg'))
    #IO.read('../test/Sample_pdf.msg') if (File.exists?('../test/Sample_pdf.msg'))
    #IO.read('../test/Sample_pptx.msg') if (File.exists?('../test/Sample_pptx.msg'))
    #IO.read('../test/Sample_txt.msg') if (File.exists?('../test/Sample_txt.msg'))
    #IO.read('../test/FWD_Sample_pptx.msg') if (File.exists?('../test/FWD_Sample_pptx.msg'))
    IO.read('../test/Sample_rtf_docx_doc.msg') if (File.exists?('../test/Sample_rtf_docx_doc.msg'))
    #IO.read('../test/Sample_rtf_docx.msg') if (File.exists?('../test/Sample_rtf_docx.msg'))
    #IO.read('../test/Sample_no_attachment.msg') if (File.exists?('../test/Sample_no_attachment.msg'))

  end
end

# Create and run the filter
filter = POSTFIX_URL_Filter.new(ARGV, STDIN)
filter.run