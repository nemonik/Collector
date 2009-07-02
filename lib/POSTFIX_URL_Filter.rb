#!/usr/local/bin/ruby19

# == Synopsis
#   A POSTFIX script that filters email for URLs and sends the URLs off to
#   RabbitMQ queue to be later processed.
#
# == Usage:  postfix_url_filter.rb [options] AMQP_queue
#
# Usage:  ./POSTFIX_URL_Filter.rb [options]
#
# A POSTFIX script that filters email for URLs and sends the URLs off to
# RabbitMQ queue to be later processed.
#
#
# Examples:
#      POSTFIX_URL_Filter.rb --sendmail --host drone.honeyclient.org \\
#        --port 5672 --vhost /collector.testing --user guest \\
#        --password guest --exchange events \\
#        --routing_key 1.job.create.job.urls.job_alerts \\
#        --no-amqp_logging --timeout 100 --use nokogiri
#
#      POSTFIX_URL_Filter.rb --sendmail --host drone.honeyclient.org \\
#        --port 5672 --vhost /collector.testing --user guest \\
#        --password guest --exchange events \\
#        --routing_key 1.job.create.job.urls.job_alerts \\
#        --no-amqp_logging --timeout 100 --use nokogiri \\
#        --file ../test/Sample_doc.msg
#
#      POSTFIX_URL_Filter.rb -h
#
# Common options:
#       --version                    display version number and exit.
#    -V, --[no-]verbose               run verbosely.
#    -h, --help                       display this help and exit.
#
# AMQP server options:
#    -H, --host HOST                  set host to HOST.
#    -P, --port PORT                  set port to PORT.
#    -u, --user USER                  set login to USER.
#    -p, --password PASSWORD          set password to PASSWORD.
#    -e, --exchange EXCHANGE          set exchange to EXCHANGE.
#    -v, --vhost VHOST                set virtual host to VHOST.
#    -k, --routing_key ROUTING_KEY    set routing key to ROUTING_KEY.
#
# Actions:
#    -S, --[no-]sendmail              Send message onto SendMail.
#    -l, --[no-]amqp_logging          enable AMQP server interaction logging.
#        --use [PARSER]               select PARSER for HTML/XML (uri, hpricot,
#                                        nokogiri).
#    -i, --ignore_attachments         don't parse attachments.
#    -t, --timeout SECONDS            set a SECONDS timeout for how long the
#                                        filter should run parsing for URLs.
#                                        Default is 40.
#    -f, --file FILE_NAME             parse this FILENAME path instead of the
#                                        standard input.
#                                                                                              
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::
#
# Dependencies:
#
# A large number of command-line dependencies including, but not limited to:
#
# => yum groupinstall Office/Productivity
# => yum install openoffice.org-headless
#


$LOAD_PATH << File.dirname(__FILE__)  # hack for now to pick up my Compression module

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
require 'open3'


class POSTFIX_URL_Filter
  VERSION = '0.0.1'

  attr_reader :options

  # Initialize the filter
  def initialize(arguments, stdin)
    @arguments = arguments
    @stdin = stdin
    
    @msg_text = nil
    
    @recipients = []
    @links = []
    @x_count = "" # used inconjunction with Send_Email.rb script.

    @log = Logger.new('/home/walsh/Development/workspace/postfixUrlParsing/lib/log.txt')
    #@log = Logger.new(STDOUT)
    @log.level = Logger::DEBUG #DEBUG INFO ERROR
    @log.datetime_format = "%H:%M:%S"

    # Set defaults
    @options = OpenStruct.new
    @options.verbose = false
    @options.sendmail = true
    @options.amqp_logging = false
    @options.use = 'nokogiri'
    @options.amqp_host = 'localhost'
    @options.amqp_port = '5672'
    @options.amqp_vhost = '/honeyclient.org'
    @options.amqp_routing_key = '1.job.create.job.urls.job_alerts'
    @options.amqp_user = 'guest'
    @options.amqp_password = 'guest'
    @options.amqp_exchange = 'events'
    @options.tmp_folder_for_attachments = '/home/walsh/tmp'
    @options.uri_schemes = ['http', 'https', 'ftp', 'ftps']
    @options.ignore_attachments = false
    @options.timeout = 40
    @options.file_name = nil
  end

  # Parse options, check arguments, then process the email
  def run

    if parsed_options?
      if arguments_valid?

        username = nil
        if @options.verbose
          IO.popen('whoami') { |io|
            username = io.read 
          }

          start_time = Time.now
          @log.info("Start at #{start_time} by #{username}")

          output_options
        end

        process_arguments

        if ((@options.file_name.nil?) || (@options.file_name.empty?))
          process_standard_input  # process email from standard input
        else
          process_file_input # process email from input file
        end

        process_email

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

  rescue Exception => e
    record_error(e)
    SystemExit.new(69)  # EX_UNAVAILABLE  
  end

  protected
  
  # Record the error for posterity
  def record_error(e)
    if ((!@message_id.nil?) && (!@message_id.empty?))
      begin
        @log.error("\"#{e.message}\" for message #{@message_id}\n#{e.backtrace}")

	      @message_id = @message_id.gsub('<', '').gsub('>','')
      	folder_name = File.join(@options.tmp_folder_for_attachments, 'bad-msg', @message_id)
        Dir.mkdir(folder_name)

        msg_file_name = File.join(folder_name, @message_id + '.msg')

        msg_file = File.new(msg_file_name, 'w')
        msg_file.syswrite(@msg_text)
        
        exception_name = File.join(folder_name, @message_id + '.backtrace')
        
        exception_file = File.new(exception_name, 'w')
        exception_file.syswrite("#{e.message}\n\n")
        exception_file.syswrite("#{e.backtrace.join("\n")}")
      ensure
        msg_file.close unless msg_file.nil?
        exception_file.close unless exception_file.nil?
      end
    else
       @log.error("#{e.message}\n#{e.backtrace}")
    end
  end	

  # Have the options been parsed
  def parsed_options?

    # Specify options
    option_parser = OptionParser.new { |opts|

      opts.banner = "Usage:  #$0 [options]"

      explanation = <<-EOE

A POSTFIX script that filters email for URLs and sends the URLs off to
RabbitMQ queue to be later processed.


Examples:
      POSTFIX_URL_Filter.rb --sendmail --host drone.honeyclient.org \\\\
        --port 5672 --vhost /collector.testing --user guest \\\\
        --password guest --exchange events \\\\
        --routing_key 1.job.create.job.urls.job_alerts \\\\
        --no-amqp_logging --timeout 100 --use nokogiri
         
      POSTFIX_URL_Filter.rb --sendmail --host drone.honeyclient.org \\\\
        --port 5672 --vhost /collector.testing --user guest \\\\
        --password guest --exchange events \\\\
        --routing_key 1.job.create.job.urls.job_alerts \\\\
        --no-amqp_logging --timeout 100 --use nokogiri \\\\
        --file ../test/Sample_doc.msg
         
      POSTFIX_URL_Filter.rb -h   
      EOE

      opts.separator(explanation)
      opts.separator('')
      opts.separator('Common options:')

      opts.on('-v', '--version', 'display version number and exit.') {output_version ; exit 0 }
      
      opts.on('-V', '--[no-]verbose', 'run verbosely.') { |boolean|
        @options.verbose = boolean
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

      opts.on('-S', '--[no-]sendmail', 'Send message onto SendMail.') { |boolean|
        @options.sendmail = boolean
      }

      opts.on('-l', '--[no-]amqp_logging', 'enable AMQP server interaction logging.') { |boolean|
        @options.amqp_logging = boolean
      }

      opts.on('--use [PARSER]', [:uri, :hpricot, :nokogiri], 'select PARSER for HTML/XML (uri, hpricot, nokogiri).') { |parser|
        @options.use = parser
      }

      opts.on('-i', '--ignore_attachments', 'don\'t parse attachments.') { |boolean|
        @options.ignore_attachments = boolean
      }

      opts.on('-t', '--timeout SECONDS', Integer, "set a SECONDS timeout for how long the filter should run parsing for URLs. Default is #{@options.timeout}.") { |timeout|
        @options.timeout = timeout
      }

      opts.on('-f', '--file FILE_NAME', String, 'parse this FILENAME path instead of the standard input.') { |file_name|
        @options.file_name = file_name
      }

    }

    option_parser.parse!(@arguments) rescue return false

    post_process_options

    true
  end

  # Dump command-line options
  def output_options

    @log.info("Options:")

    @options.marshal_dump.each do |name, val|
      @log.info("  #{name} = \"#{val}\"")
    end
  end

  # Performs post-parse processing on options
  def process_options

  end

  # Post process options
  def post_process_options

  end


  # True if required arguments were provided
  def arguments_valid?

    true 

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
  def process_email

    #@log.debug("#{@msg_text}")

    message = RMail::Parser.read(@msg_text)

    header = message.header

    @from = RMail::Address.parse(header['from'])

    @subject = header['subject'].to_s
    
    @x_count = header['x-count'].to_s # used with Send_mail.rb script

    @subject = '(no subject)' if @subject.size == 0

    @message_id = (header['Message-ID'] != nil) ? header['Message-ID'] : Guid.new.to_s

    @recipients.concat(RMail::Address.parse(header['to']) + RMail::Address.parse(header['cc'])) #RMail::Address.parse(header.match(/^(to|cc)/, //))) Should work, but doesn't.

    #give email as input to the Postfix sendmail command
    if @options.sendmail
      sendmail_cmd = "/usr/sbin/sendmail.postfix -G -i #{@from.addresses[0]} "

      @recipients.each { |recipient|
        sendmail_cmd.concat(recipient.address)
        sendmail_cmd.concat(" ")
      }

      sendmail_cmd.chomp(" ")

      @log.debug("sending msg to sendmail...")
      IO.popen("#{sendmail_cmd}", "w") { |sendmail| sendmail << "#{@msg_text}" }
      
    end

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

          ensure
            FileUtils.rm_rf(folder_name) #unless folder_name.nil?
          end
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

    if (file_output.downcase.match(/cdf v2 document/)) 
       ## TODO: unix-file command is reporting something new for MS Word Docs...
       ## for now just look at the file extension, til a second pass be
       ## taken with gnomevfs-info or something else...
       if (".doc, .ppt, .xls".match(File.extname(file_name)))
          return 'Microsoft Office Document'
       end
    elsif (file_output.downcase.match(/microsoft/))
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

    @log.debug("calling open office to process #{file_name}")

    Open3.popen3("/usr/lib64/openoffice.org3/program/soffice -invisible -nologo -headless \"macro:///HoneyClient.Conversion.ConvertToHTML(#{file_name})\"") { |stdin, stdout, stderr|
      error = stderr.read
      @log.error("stderr = #{error}") if error
      out = stdout.read
      @log.info("stdout = #{out}") if out
    }

    @log.debug("tmp #{File.dirname(file_name)} folder contains")
    Find.find(File.dirname(file_name)) do |f| @log.debug("  -> #{f}") if (f != File.dirname(file_name)) end
 
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

    time = Time.new

    # create job_source
    job_source = {}
    job_source['name'] = @message_id
    job_source['protocol'] = 'smtp'
    job_source['x-count']= @x_count

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

    @log.info("Publishing #{@links.size} links to AMQP server #{@links}...")    
    
    EM.run do
      connection = AMQP.connect(:host => @options.amqp_host, :port => @options.amqp_port,:user => @options.amqp_user, :pass => @options.amqp_password, :vhost => @options.amqp_vhost, :logging => @options.amqp_logging)
      channel = MQ.new(connection)
      exchange = MQ::Exchange.new(channel, :topic, @options.amqp_exchange, {:passive => false, :durable => true, :auto_delete => false, :internal => false, :nowait => false})
      queue = MQ::Queue.new(channel, 'events', :durable => true)
      queue.bind(exchange)
#      queue.publish(JSON.pretty_generate job, {:routing_key => @options.amqp_routing_key, :persistent => true})      
      exchange.publish(JSON.pretty_generate job, {:routing_key => @options.amqp_routing_key, :persistent => true})
      connection.close{ EM.stop }
    end
    
  rescue Exception => e
    @log.error("Problem sending message to AMQP server, #{$!}")
  end

  # Select the method to parse out links
  def get_links(text)
    if (@options.use == :uri)
      get_links_with_uri(text)
    elsif (@options.use == :hpricot)
      get_links_with_hpricot(text)
    elsif (@options.use == :nokogiri)
      get_links_with_nokogiri(text)
    else
      @log.error("Unknown parser #{@options.use} requested!");
    end
  end

  # Retrieves all links in the text described by @options.uri_schema
  def get_links_with_uri(text)
    @log.debug("using URI to extract URLs from text in #{text.encoding.name} encoding.")

    tmp_links = []

    if ((!text.nil?) && (!text.strip.empty?))
      URI.extract(text, @options.uri_schemes) {|url|
        url = url.gsub(/\/$/,'').gsub(/\)$/, '').gsub(/\>/,'') #TODO: need a better regex
        tmp_links.push(url)
      }

      @log.debug("adding #{tmp_links} containing #{tmp_links.size} URLs to count")

      @links = @links + tmp_links
    end  
  rescue Exception => e
    @log.error("had a problem pulling URL from text, #{$!}, x-count #{@x_count}")
    raise e
  end

  # Get the links from the text using the Hpricot XML/HTML parser
  def get_links_with_hpricot(text)

    @log.debug("using hpricot to parse...")

    if ((!text.nil?) && (!text.strip.empty?))
      # the version of hpricot I developed against
      # is not attribute case insensitive
      text = text.gsub(/\sHREF/, ' href')
      text = text.gsub(/\sSRC/, ' src')

      tmp_links = []

      # parse HTML content after fixing up content
      html = Hpricot(text, :fixup_tags => true)
      
      # pull URLs from anchor tags
      html.search('//a').map { |a|
        if (a['href'] != nil)
          url = URI.extract(a['href'], @options.uri_schemes)[0]
          tmp_links.push(url.gsub(/\/$/,'')) if url
        end
      }

      # pull URLs from img tags
      html.search('//img').map { |img|
        if (img['src'] != nil)
          url = URI.extract(img['src'], @options.uri_schemes)[0]
          tmp_links.push(url.gsub(/\/$/,''))  if url
        end
      }

      @log.debug("adding #{tmp_links} containing #{tmp_links.size} URLs to count")

      @links = @links + tmp_links
    end
  end

  # Get the links from the text using the Nokogiri XML/HTML parser
  def get_links_with_nokogiri(text)

    @log.debug("using nokogiri to parse...")

    if ((!text.nil?) && (!text.strip.nil?))
      html = Nokogiri::HTML(text)
      tmp_links = []

      # pull URLs from anchor tags
      html.xpath('//a').map { |a|
        if (a['href'] != nil)
          url = URI.extract(a['href'], @options.uri_schemes)[0]
          tmp_links.push(url.gsub(/\/$/,'')) if url
        end
      }

      # pull URLs from img tags
      html.xpath('//img').map { |img|
        if (img['src'] != nil)
          url = URI.extract(img['src'], @options.uri_schemes)[0]
          tmp_links.push(url.gsub(/\/$/,''))  if url
        end
      }

      @log.debug("adding #{tmp_links} containing #{tmp_links.size} URLs to count")

      @links = @links + tmp_links
    end
  end

  # Process the standard input
  def process_standard_input
    @log.debug("Processing standard input...")
    @msg_text = @stdin.read
  end

  # Process the file input
  def process_file_input
    @log.debug("Processing input read from #{@options.file_name}...")

    if File.exist?(@options.file_name)
      @msg_text = File.open(@options.file_name).read
    else
      raise IOError("File not found!")
    end
  end
end

# Create and run the filter
filter = POSTFIX_URL_Filter.new(ARGV, STDIN)
filter.run