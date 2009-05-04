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
#    -V, --verbose                    be verbose (default).
#    -q, --quiet                      quiet (no output).
#
# == AMQP server options:
#    -H, --host HOST                  set host to HOST
#    -P, --port PORT                  set port to PORT
#    -u, --user USER                  set login to USER.
#    -p, --password PASSWORD          set password to PASSWORD.
#
# == Actions:
#    -l, --amqp_logging               enable AMQP server interaction logging.
#    -U, --use parser                 parse HTML email with 'uri' (default), 'hpricot', or 'nokogiri'.
#    -h, --help                       display this help and exit.
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

class POSTFIX_URL_Filter
  VERSION = '0.0.1'

  attr_reader :options

  def initialize(arguments, stdin)
    @arguments = arguments
    @stdin = stdin

    @recipients = []
    @links = []

    # Set defaults
    @options = OpenStruct.new
    @options.verbose = true
    @options.quiet = false
    @options.amqp_logging = false
    @options.use = 'nokogiri'
    @options.amqp_host = 'localhost'
    @options.amqp_port = '5672'
    @options.amqp_user = 'guest'
    @options.amqp_password = 'guest'
    @options.tmp_folder_for_attachments = "/home/walsh/tmp"
    @options.uri_schemes = ['http', 'https', 'ftp', 'ftps']
  end

  # Parse options, check arguments, then process the email
  def run

    if parsed_options?
      if arguments_valid?

        puts "Start at #{DateTime.now}\n\n" if @options.verbose

        output_options if @options.verbose # [Optional]

        process_arguments
        process_email(process_standard_input)  # process email from standard input
        send_to_amqp_queue 

        puts "\nFinished at #{DateTime.now}" if @options.verbose
      else
        puts "invalid arguments"
      end
    else
      puts "invalid options"
    end

  end

  protected

  def parsed_options?

    # Specify options
    option_parser = OptionParser.new do |opts|

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
      opts.on('-V', '--verbose', 'be verbose (default).') { @options.verbose = true }
      opts.on('-q', '--quiet', 'quiet (no output).') { @options.quiet = true}

      opts.separator('')
      opts.separator('AMQP server options:')

      opts.on('-H', '--host HOST', 'set host to HOST') { |string| @options.amqp_host = string }

      opts.on('-P', '--port PORT', 'set port to PORT') { |string| @options.amqp_port = string }

      opts.on('-u', '--user USER', 'set login to USER.') { |string| @options.user = string }

      opts.on('-p', '--password PASSWORD', 'set password to PASSWORD.') {|string| @options.password = string }

      opts.separator('')
      opts.separator('Actions:');

      opts.on('-l', '--amqp_logging', 'enable AMQP server interaction logging.') { @options.amqp_logging = true }

      opts.on('-U', '--use parser', 'parse HTML email with \'uri\' (default), \'hpricot\', or \'nokogiri\'.')  { @options.use_hpricot = string }

      opts.on_tail('-h', '--help', 'display this help and exit.') do
        puts opts
        exit
      end

    end

    option_parser.parse!(@arguments) rescue return false

    #post_process_options

    true
  end

  # Dump command-line options
  def output_options
    puts "Options:\n"

    @options.marshal_dump.each do |name, val|
      puts "  #{name} = #{val}"
    end
  end

  # Performs post-parse processing on options
  def process_options

    @options.verbose = false if @options.quiet

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

        if (header['Content-Type'].downcase.include? 'text/plain') # handle plain text part

          # handle text/plain
          get_links_with_uri(doc)

        elsif (header['Content-Type'].downcase.include? 'text/html') # handle html part

          # handle hmtl
          get_links(doc)

        elsif (header['Content-Type'].downcase.include? 'application') #handle application/octet-stream, application/msword, ...

          # create unique directory to holder file to allow for easy cleanup
          folder = @options.tmp_folder_for_attachments + "/" + Guid.new.to_s
          Dir.mkdir(folder)
          filename = folder + "/" + header['Content-Type'].chomp.split(/;\s*/)[1].split(/\s*=\s*/)[1].gsub(/\"/, "")

          if (header['Content-Transfer-Encoding'].downcase == 'base64')

            #puts "writing #{filename}"

            file = File.new(filename, 'w')

            file.syswrite(doc.unpack("m")[0]) # base64 decode and write out

            file.close
          end

          # run open office converter macro
          IO.popen("/usr/lib64/openoffice.org3/program/soffice -invisible \"macro:///HoneyClient.Conversion.ConvertToHTML(#{filename})\"") { |io|
            puts '|' + io.read + '|'
          }

          # handle hmtl, if the doc was ms word-like
          get_links(File.open(filename + ".html").read) if File.exists?(filename + ".html")

          # handle html, if the doc was ms powerpoint-like
          Dir.foreach(folder) {|f|
            get_links(File.open(folder + '/' + f).read) if ((f.match(/^text/)) && (f.match(/.html$/)))
          }

          # clean up temp files
          FileUtils.rm_rf(folder)

        elsif (header['Content-Type'].downcase.include? 'message/rfc822') # handle forwarded email

          process_email(doc)

        else # handle unknown content-type

          puts "Unhandled content-type #{header['Content-Type']}"

        end if ((doc.class != NilClass) && (doc.strip != ''))
      } if (message.multipart?)
  end

  # send off to AMQP queue
  def send_to_amqp_queue

    # strip off dupes
    @links = @links.uniq.compact

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

    #pp "sent"

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
    URI.extract(text, @options.uri_schemes) {|url|
      @links.push(url.gsub(/\/$/,''))
    }
  end

  # can be tuned to be more pecific as to what URLs are retrieved from HTML
  def get_links_with_hpricot(text)

    if ((text.class != NilClass) && (text.strip != ''))
      # the version of hpricot I developed against
      # is not attribute case insensitive
      text = text.gsub(/\sHREF/, ' href')
      text = text.gsub(/\sSRC/, ' src')

      # parse HTML content after fixing up content
      html = Hpricot(text, :fixup_tags => true)

      # pull URLs from anchor tags
      html.search('//a').map { |a|
        if (a['href'] != nil)
          url = URI.extract(a['href'], @options.uri_schemes)[0]
          @links.push(url.gsub(/\/$/,'')) if url
        end
      }

      # pull URLs from img tags
      html.search('//img').map { |img|
        if (img['src'] != nil)
          url = URI.extract(img['src'], @options.uri_schemes)[0]
          @links.push(url.gsub(/\/$/,''))  if url
        end
      }
    end
  end

  # can be tuned to be more specific as to what URLs are retrieved from HTML
  def get_links_with_nokogiri(text)

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

    #IO.read('../test/Word DOCX Test.msg') if (File.exists?('../test/Word DOCX Test.msg'))
    IO.read('../test/FWD Word DOCX Test.msg') if (File.exists?('../test/FWD Word DOCX Test.msg'))
    #IO.read('../test/Power Point Prez.msg') if (File.exists?('../test/Power Point Prez.msg'))
  end
end

# Create and run the filter
filter = POSTFIX_URL_Filter.new(ARGV, STDIN)
filter.run