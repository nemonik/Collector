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
#    -H, --host HOST                  set host to HOST.
#    -P, --port PORT                  set port to PORT.
#    -u, --user USER                  set login to USER.
#    -p, --password PASSWORD          set password to PASSWORD.
#    -q, --queue QUEUE                set queue to QUEUE.
#
# == Actions:
#    -l, --[no-]amqp_logging          enable AMQP server interaction logging.
#        --use [PARSER]               select PARSER for HTML/XML (uri, hpricot, nokogiri).
#    -I, --ingore_attachments         ignore attachments, don't parse them.
#    -t, --timeout SECONDS            set a SECONDS timeout for how long the filter
#                                       should run parsing for URLs. Default is 40.
#    -f, --file FILENAME              parse this FILENAME path instead of the
#                                       standard input.
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

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
require 'eventmachine'
require 'json'
require 'fileutils'
require 'socket'
require 'logger'
require 'Compression'
require 'timeout'


class POSTFIX_URL_Filter
  VERSION = '0.0.1'

  attr_reader :options

  # Initialize the filter
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
    @options.amqp_vhost = "/honeyclient.org"
    @options.amqp_routing_key = '1.job.create.job.urls'
    @options.amqp_user = 'guest'
    @options.amqp_password = 'guest'
    @options.amqp_exchange = 'events'
    @options.tmp_folder_for_attachments = '/home/walsh/tmp'
    @options.uri_schemes = ['http', 'https', 'ftp', 'ftps']
    @options.ignore_attachments = false
    @options.timeout = 40
    @options.file_name = ''
  end

  # Parse options, check arguments, then process the email
  def run

    if parsed_options?
      if arguments_valid?

        start_time = Time.now
        @log.info("Start at #{start_time}") if @options.verbose

        output_options if @options.verbose # [Optional]

        process_arguments

        if @options.file_name.empty?
          process_email(process_standard_input)  # process email from standard input
        else
          process_email(process_file_input) # process email from input file
        end

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

  rescue AMQP::Error
    @log.error("Could not send links to be processed, reason: \"#{$!}\"")
  rescue
    @log.error("#{$!}")
  end

  protected

  # Have the options been parsed
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

      opts.on('-H', '--host HOST', String, 'set host to HOST.') { |host|
        @options.amqp_host = host
      }

      opts.on('-P', '--port PORT', String, 'set port to PORT.') { |port|
        @options.amqp_port = port
      }

      opts.on('-u', '--user USER', String, 'set login to USER.') { |user|
        @options.amqp_user = user
      }

      opts.on('-p', '--password PASSWORD', String, 'set password to PASSWORD.') {|password|
        @options.amqp_password = password
      }

      opts.on('-e', '--exchange EXCHANGE', String, 'set exchange to EXCHANGE.') {|exchange|
        @options.amqp_exchange = exchange
      }

      opts.on('-v', '--vhost VHOST', String, 'set virtual host to VHOST.') {|vhost|
        @options.amqp_vhost = vhost
      }

      opts.on('-k', '--routing_key ROUTING_KEY', String, 'set routing key to ROUTING_KEY.') {|routing_key|
        @options.amqp_routing_key = routing_key
      }

      opts.separator('')
      opts.separator('Actions:');

      opts.on('-l', '--[no-]amqp_logging', 'enable AMQP server interaction logging.') { |boolean|
        @options.amqp_logging = boolean
      }

      opts.on('--use [PARSER]', [:uri, :hpricot, :nokogiri], 'select PARSER for HTML/XML (uri, hpricot, nokogiri).') { |parser|
        @options.use = parser
      }

      opts.on('-i', '--ignore_attachments', 'don\'t parse attachments.') { |boolean|
        @options.ignore_attachments = boolean
      }

      opts.on('-t', '--timeout SECONDS', Integer, 'set a SECONDS timeout for how long the filter should run parsing for URLs. Default is #{@options.timeout}.') { |timeout|
        @options.timeout = timeout
      }

      opts.on('-f', '--file FILE_NAME', String, 'parse this FILENAME path instead of the standard input.') { |file_name|
        @options.file_name = file_name
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

  end

  # Output the version
  def output_version

    puts "#{File.basename(__FILE__)} version #{VERSION}"

  end

  # Process the email, pulling out all the unique links and send to AMQP
  # server to be later be processed
  def process_email(msg_text)

    @log.debug("#{msg_text}")

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

          @log.debug('handling base64 attachment...')

          # create unique directory to hold the file for processing, and allow for easy cleanup
          folder_name = @options.tmp_folder_for_attachments + "/" + Guid.new.to_s
          Dir.mkdir(folder_name)

          file_name = File.join(folder_name, header['Content-Type'].chomp.split(/;\s*/)[1].split(/\s*=\s*/)[1].gsub(/\"/, ""))

          file = File.new(file_name, 'w')

          file.syswrite(doc.unpack('m')[0]) # base64 decode and write out

          file.close

          begin
            Timeout::timeout(@options.timeout) {
              process_file(file_name)
            }
          rescue Timeout::Error
            @log.info('Processing of attachments has timed out.')
          end

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
  rescue
    @log.error("#{$!}, email is likely not properly formatted.")
  end

  # Process the file
  def process_file(file_name)

    @log.debug("writing file #{file_name}...")

    file_type = mime_shared_info(file_name)

    @log.debug("file is  \"#{file_type}\"...")

    if ('Microsoft Office Document, OpenOffice Document, Microsoft Office Open XML Format Document'.match("#{file_type}"))
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
      process_compressed(file_name, 'tar')
    else
      @log.error("Unhandled file type of \"#{file_type}\"")
    end

  end

  # Process the compressed file using a particular compression
  def process_compressed(file_name, compression)

    dst = File.dirname(file_name)

    @log.debug("processing #{compression} compressed #{file_name}...")

    if (compression == 'zip')
      Compression.unzip(file_name, dst)
      FileUtils.rm(file_name)
    elsif (compression == 'gzip')
      Compression.gunzip(file_name)
    elsif (compression == 'bzip2')
      Compression.bunzip2(file_name)
    elsif (compression == 'tar')
      Compression.untar(file_name, dst)
      FileUtils.rm(file_name)
    else
      @log.error("#{compression} unhandled form of compression")
    end

    # process contents, drilling into sub-folders if they exist
    Find.find(dst) { |contents|
      if File.file? contents
        @log.debug("from #{File.basename(file_name)}, processing #{contents}")
        process_file(contents)
      end
    }
  end

  # Determine the mimetype of the file
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
        return 'Microsoft Office Open XML Format Document'
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

  # Get the links from the MS Office or OpenOffice document
  def get_links_from_office_doc(file_name)
    # TODO: Handle Excel documents.

    # run open office converter macro
    IO.popen("/usr/lib64/openoffice.org3/program/soffice -invisible \"macro:///HoneyClient.Conversion.ConvertToHTML(#{file_name})\"") { |io|
      @log.info("#{io.read}")  # shouldn't really return anything
    }

    # handle hmtl, if the doc was ms word-like
    file_name = file_name + '.html'

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

  # Send the links off to AMQP exchange/queue
  def send_to_amqp_queue

    # strip off dupes
    @log.debug("URL count before compact #{@links.size}")
    @links = @links.uniq.compact
    @log.debug("Sending #{@links.size} links to amqp server #{@links}...")

    time = Time.new

    # create job_source
    job_source = {}
    job_source['name'] = @message_id
    job_source['protocol'] = 'smtp'

    # create job
    job = {}
    job['uid'] = Guid.new.to_s
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

    puts JSON.pretty_generate job

    # publish message to RabbitMQ
    EM.run do
      connection = AMQP.connect(:host => @options.amqp_host, :port => @options.amqp_port,:user => @options.amqp_user, :password => @options.amqp_password, :vhost => @options.amqp_vhost, :logging => @options.amqp_logging)
      channel = MQ.new(connection)
      exchange = MQ::Exchange.new(channel, :topic, @options.amqp_exchange, {:passive => false, :durable => true, :auto_delete => false, :internal => false, :nowait => false})
      queue = MQ::Queue.new(channel, 'events', :durable => true)
      queue.bind(exchange)
      queue.publish(JSON.pretty_generate job, {:routing_key => '1.job.create.job.urls', :persistent => true})
      connection.close{ EM.stop }
    end

  end

  # Select the method to parse out links
  def get_links(text)
    if (@options.use == 'uri')
      get_links_with_uri(text)
    elsif (@options.use == 'hpricot')
      get_links_with_hpricot(text)
    elsif (@options.use == 'nokogiri')
      get_links_with_nokogiri(text)
    end
  end

  # Retrieves all links in the text described by @options.uri_schema
  def get_links_with_uri(text)
    @log.debug("using URI to extract URLs...")

    URI.extract(text, @options.uri_schemes) {|url|
      @links.push(url.gsub(/\/$/,'').gsub(/\)$/, '').gsub(/\>/,'')) #TODO: need a better regex
    }
  end

  # Get the links from the text using the Hpricot XML/HTML parser
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

  # Get the links from the text using the Nokogiri XML/HTML parser
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

  # Process the standard input
  def process_standard_input
    @log.debug("Processing standard input...")
    @stdin.read
  end

  # Process the file input
  def process_file_input
    @log.debug("Processing input read from #{@options.file_name}...")

    if File.exist?(@options.file_name)
      File.open(@options.file_name).read
    else
      raise IOError("File not found!")
    end
  end
end

# Create and run the filter
filter = POSTFIX_URL_Filter.new(ARGV, STDIN)
filter.run