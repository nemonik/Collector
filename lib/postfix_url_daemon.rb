#!/usr/local/bin/ruby19

# == Synopsis
#   A daemon to parse URLs from emails pulled off a socket
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

$LOAD_PATH << File.dirname(__FILE__)  # hack for now to pick up my Compression module

require 'rubygems'
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
require 'logger_patch'
require 'compression'
require 'timeout'
require 'net/http'
require 'net/http/post/multipart'
require 'iconv'
require 'thread'
require 'socket'
require 'eventmachine'
require 'term/ansicolor'
require 'daemons/daemonize'
require 'jodconvert_3_x'
include Daemonize
include Term::ANSIColor

class PostfixUrlDaemon

  VERSION = '0.0.1'

  attr_reader :options

  class ThreadPool
    class Worker
      include Compression

      def initialize(log, name)
        @log = log
        @name = name

        @msg_text = nil
        @recipients = []
        @links = []
        @x_count = nil # used inconjunction with Send_Email.rb script.

        @mutex = Mutex.new
        @mutex.synchronize {@waiting = true}
        @mutex.synchronize {@running = false}

        @manager = JODConvert_3_x.instance

        @thread = Thread.new do
          while @mutex.synchronize {@waiting}
            if @mutex.synchronize {@running}
              process_email
              send_to_amqp_queue if $options.send_to_amqp
              free
              @mutex.synchronize {@running = false}
            end
          end
        end
      end

      def free
        @links = []
        @recipients = []
        @msg_text = nil
        @x_count = nil
      end

      def get_name
        "#{@name} (#{name})"
      end

      def name
        @thread.inspect
      end

      def run(msg_text)
        @msg_text = msg_text

        @mutex.synchronize {@running = true}
      end

      def busy?
        @mutex.synchronize {@running}
      end

      def stop
        @mutex.synchronize {@waiting = false}
        @thread.join
      end

      private

      def log(level, msg)

        case level
        when :debug
          @log.debug("worker #{@name} : #{msg}")
        when :info
          @log.info("worker #{@name} : #{msg}")
        when :warn
          @log.warn("worker #{@name} : #{msg}")
        when :error
          @log.error("worker #{@name} : #{msg}")
        end
      end

      # Record the error for posterity
      def record_error(e)
        if ((!@message_id.nil?) && (!@message_id.empty?))
          begin
            log(:error, "\"#{e.message}\" for message #{@message_id}\n#{e.backtrace}")

            @message_id = @message_id.gsub('<', '').gsub('>','')
            folder_name = File.join($options.tmp_folder_for_attachments, 'bad-msg', @message_id)
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
          log(:error, "#{e.message}\n#{e.backtrace}")
        end
      end

      # Process the email, pulling out all the unique links and send to AMQP
      # server to be later be processed
      def process_email

        #log(:debug, "#{@msg_text}")

        message = RMail::Parser.read(@msg_text)

        header = message.header

        @from = RMail::Address.parse(header['from'])

        @subject = header['subject'].to_s

        @x_count = header['x-count'].to_s # used with Send_mail.rb script

        @subject = '(no subject)' if @subject.size == 0

        @message_id = (header['Message-ID'] != nil) ? header['Message-ID'] : Guid.new.to_s

        @recipients.concat(RMail::Address.parse(header['to']) + RMail::Address.parse(header['cc'])) #RMail::Address.parse(header.match(/^(to|cc)/, //))) Should work, but doesn't.

        #give email as input to the Postfix sendmail command
        if $options.sendmail
          sendmail_cmd = "/usr/sbin/sendmail.postfix -G -i #{@from.addresses[0]} "

          @recipients.each { |recipient|
            sendmail_cmd.concat(recipient.address)
            sendmail_cmd.concat(" ")
          }

          sendmail_cmd.chomp(" ")

          log(:debug, "sending msg #{@message_id} to sendmail...")
          IO.popen("#{sendmail_cmd}", "w") { |sendmail| sendmail << "#{@msg_text}" }

        end

        if (message.multipart?)
          message.each_part { |part|

            header = part.header

            doc = (header['Content-Transfer-Encoding'] == 'quoted-printable') ? part.body.unpack('M')[0] : part.body

            log(:debug, '====================')

            if ((header['Content-Type'].downcase.include? 'text/plain') && (!header.has_key?('Content-Disposition')))

              log(:debug, 'handling plain text part...')

              get_links_with_uri(doc)

            elsif ((header['Content-Type'].downcase.include? 'text/html') && (!header.has_key?('Content-Disposition')))
              log(:debug, 'handling html part...')
             
              get_links(doc)

            elsif ((header.has_key?('Content-Disposition')) && (header['Content-Disposition'].downcase.include? 'attachment') && (!$options.ignore_attachments))

              if (header['Content-Transfer-Encoding'].downcase.include? 'base64')

                log(:debug, 'handling base64 attachment...')

                # create unique directory to hold the file for processing, and allow for easy cleanup
                folder_name = $options.tmp_folder_for_attachments + "/" + Guid.new.to_s
                Dir.mkdir(folder_name)

                file_name = File.join(folder_name, header['Content-Type'].chomp.split(/;\s*/)[1].split(/\s*=\s*/)[1].gsub(/\"/, ""))

                file = File.new(file_name, 'w')
                file.syswrite(doc.unpack('m')[0]) # base64 decode and write out
                file.close

                begin
                  Timeout::timeout($options.timeout) {
                    process_file(file_name)
                  }
                rescue Timeout::Error

                  log(:info, ' => Processing of attachments has timed out.')

                ensure
                  FileUtils.rm_rf(folder_name) #unless folder_name.nil?
                end
              else
                log(:warn, " => Unhandled content-transfer-encoding #{header['Content-Transfer-Encoding']}")
              end

            elsif (header['Content-Type'].downcase.include? 'message/rfc822')

              log(:debug, 'handling forwarded email...')

              process_email(doc)

            else # handle unknown content-type

              log(:warn,"Unhandled content-type #{header['Content-Type']}")

            end if ((doc.class != NilClass) && (doc.strip != ''))
          }
        else
          get_links_with_uri(message.body)
        end
      end

      # Process the file
      def process_file(file_name)

        log(:debug, " => writing file #{file_name}...")

        info = mime_shared_info(file_name)

        log(:debug, " => info = #{info}")

        if (info[0] == 'application/pdf')
          out = nil
          IO.popen("pdftotext #{file_name} /dev/stdout") {|stdout|
            out = stdout.read
          }

          get_links_with_uri(out)

        elsif ('application/rtf, text/plain, text/csv'.include?(info[0]))
          get_links_with_uri(File.open(file_name).read)

        elsif ('text/html, application/xml'.include?(info[0]))
          get_links(File.open(file_name).read)

        elsif (info[0] == 'application/zip')
          process_compressed(file_name, 'application/zip')

        elsif ('application/x-compressed-tar, application/x-gzip'.include?(info[0]) || info[0].include?('application/x-gz'))
          process_compressed(file_name, 'application/x-gzip')

        elsif (info[0].include?('application/x-bz'))
          process_compressed(file_name, 'application/x-bzip')

        elsif (info[0] == 'application/x-tar')
          process_compressed(file_name, 'application/x-tar')

        elsif (info[1].include?('openoffice.org-calc'))
          # calc/excel docs need to first be converted to a csv, then
          # the urls pulled from
          if (csv = @manager.process_office_file(file_name, info[0], 'text/csv', 'csv'))
            file_name = file_name + '.csv'
            File.open(file_name, 'wb') {|f|
              f.write(csv)
            }

            get_links_with_uri(File.open(file_name).read)
          end
        elsif (info[1].include?('openoffice.org-impress'))
          # presentation/powerpoint docs cannot be convert straight away, but
          # instead need a two step process of first being converted to
          # pdf and then to text
          # TODO: try another way, now that we are using JODconvert 3.0
          if (pdf = @manager.process_office_file(file_name, info[0], 'application/pdf', 'pdf'))
            file_name = file_name + '.pdf'
            File.open(file_name, 'wb') {|f|
              f.write(pdf)
            }

            out = nil
            IO.popen("pdftotext #{file_name} /dev/stdout") {|stdout|
              out = stdout.read
            }

            get_links_with_uri(out)
          end

        elsif (info[1].include?('openoffice'))
          html = @manager.process_office_file(file_name, info[0], 'text/html', 'html')

          log(:debug, " => service returned : #{html}")

          get_links(html) if html

        else
          log(:error, " => Unhandled file type of \"#{info}\"")
        end

      end

      # Process the compressed file using a particular compression
      def process_compressed(file_name, compression)

        dst = File.dirname(file_name)

        log(:debug, " => processing #{compression} compressed #{file_name}...")

        if (compression == 'application/zip')
          unzip(file_name, dst)
          FileUtils.rm(file_name)

        elsif (compression == 'application/x-gzip')
          gunzip(file_name)

        elsif (compression == 'application/x-bzip')
          bunzip2(file_name)

        elsif (compression == 'application/x-tar')
          untar(file_name, dst)
          FileUtils.rm(file_name)

        else
          log(:error, " => #{compression} unhandled form of compression")
        end

        # process contents, drilling into sub-folders if they exist
        Find.find(dst) { |contents|
          if File.file? contents
            log(:debug, " => from #{File.basename(file_name)}, processing #{contents}")
            process_file(contents)
          end
        }
      end

      # Determine the mimetype of the file
      def mime_shared_info(file_name)
        #Name              : Sample.doc
        #Type              : Regular
        #MIME type         : application/msword
        #Default app       : openoffice.org-writer.desktop

        info = []

        IO.popen("gnomevfs-info \"#{file_name}\"") { |stdout|

          if (out = stdout.read)
            out.split(/\n/).each {|line|
              pair = line.split(':')
              name = pair[0].strip!;
              if ('MIME type, Default app'.include?(name))
                info.push(pair[1].strip!)
                break if name == 'Default app'
              end
            }
          end
        }

        return info
      end

      # Send the links off to AMQP exchange/queue
      def send_to_amqp_queue

        # strip off dupes
        log(:debug, "URL count before compact #{@links.size}")
        @links = @links.uniq.compact

        if (@links.size > 0)

          $count_mutex.synchronize {$count += @links.size}

          if ($count_mutex.synchronize {$count <= $options.max_count})
            time = Time.new

            # create job_source
            job_source = {}
            job_source['name'] = @message_id
            job_source['protocol'] = 'smtp'
            job_source['x_count']= @x_count

            # create job
            job = {}
            job['uuid'] = Guid.new.to_s
            job['url_count'] = @links.size
            job['created_at'] = time
            job['job_source'] = job_source

            urls = []

            url_status = {}
            url_status['status'] = 'queued'

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

            wrapper = {}
            wrapper['job'] = job

            log(:info, "Publishing #{@links.size} links to AMQP server :: #{@links}...")

            begin
              EM.run do
                connection = AMQP.connect(:host => $options.amqp_host, :port => $options.amqp_port,:user => $options.amqp_user, :pass => $options.amqp_password, :vhost => $options.amqp_vhost, :logging => $options.amqp_logging)
                channel = MQ.new(connection)
                exchange = MQ::Exchange.new(channel, :topic, $options.amqp_exchange, {:key=> $options.amqp_routing_key, :passive => false, :durable => true, :auto_delete => false, :internal => false, :nowait => false})
                #      queue = MQ::Queue.new(channel, 'events', :durable => true)
                #      queue.bind(exchange)
                #      queue.publish(JSON.pretty_generate job, {:routing_key => $options.amqp_routing_key, :persistent => true})
                #      exchange.publish(JSON.pretty_generate job, {:routing_key => $options.amqp_routing_key, :persistent => true})
                exchange.publish(JSON.pretty_generate wrapper, {:persistent => true})
                connection.close{ EM.stop }
              end
            rescue Exception => e
              log(:error, "Problem sending message to AMQP server, #{$!}")
            end
          else
            log(:info, "Not publishing  #{@links.size} links to AMQP server :: #{@links}...")
          end
        end
      end

      # Select the method to parse out links
      def get_links(text)
        if ($options.use == :uri)
          get_links_with_uri(text)
        elsif ($options.use == :hpricot)
          get_links_with_hpricot(text)
        elsif ($options.use == :nokogiri)
          get_links_with_nokogiri(text)
        else
          log(:error, " => Unknown parser #{$options.use} requested!");
        end
      end

      # Retrieves all links in the text described by $options.uri_schema
      def get_links_with_uri(text)

        # cleanup encoding...
        ic = Iconv.new("#{text.encoding.name}//IGNORE", "#{text.encoding.name}")
        text = ic.iconv(text + ' ')[0..-2]

        tmp_links = []

        if ((!text.nil?) && (!text.strip.empty?))
          URI.extract(text, $options.uri_schemes) {|url|
            url = url.gsub(/\/$/,'').gsub(/\)$/, '').gsub(/\>/,'') #TODO: need a better regex
            tmp_links.push(url)
          }

          log(:debug, " => URI adds #{tmp_links} containing #{tmp_links.size} URLs to count")

          @links = @links + tmp_links
        else
          log(:debug, ' => text is empty')
        end
      rescue Exception => e
        log(:error, " => had a problem pulling URL from text, #{e.message}, x-count #{@x_count}")
        log(:error, " => -------------------------------------------------------------------------------\n => #{text}\n => -------------------------------------------------------------------------------")
        raise e
      end

      # Get the links from the text using the Hpricot XML/HTML parser
      def get_links_with_hpricot(text)

        if ((!text.nil?) && (!text.strip.empty?))
          # the version of hpricot I developed against
          # is not attribute case insensitive
          text = text.gsub(/\sHREF/, ' href')
          text = text.gsub(/\sSRC/, ' src')

          tmp_links = []

          # parse HTML content after fixing up content
          html = Hpricot(text, :fixup_tags => true)

          # pull URLs from anchor tags
          html.search('//a').map { |href|
            if (href['href'] != nil)
              url = URI.extract(href['href'], $options.uri_schemes)[0]
              tmp_links.push(url.gsub(/\/$/,'')) if url
            end
          }

          # pull URLs from img tags
          html.search('//img').map { |img|
            if (img['src'] != nil)
              url = URI.extract(img['src'], $options.uri_schemes)[0]
              tmp_links.push(url.gsub(/\/$/,''))  if url
            end
          }

          log(:debug, " => hpricot adds #{tmp_links} containing #{tmp_links.size} URLs to count")

          @links = @links + tmp_links
        end
      end

      # Get the links from the text using the Nokogiri XML/HTML parser
      def get_links_with_nokogiri(text)

        if ((!text.nil?) && (!text.strip.nil?))
          html = Nokogiri::HTML(text)
          tmp_links = []

          # pull URLs from anchor tags
          html.xpath('//a').map { |href|
            if (href['href'] != nil)
              url = URI.extract(href['href'], $options.uri_schemes)[0]
              tmp_links.push(url.gsub(/\/$/,'')) if url
            end
          }

          # pull URLs from img tags
          html.xpath('//img').map { |img|
            if (img['src'] != nil)
              url = URI.extract(img['src'], $options.uri_schemes)[0]
              log(:debug, "  src url is #{url}")
              tmp_links.push(url.gsub(/\/$/,''))  if url
            end
          }

          log(:debug, " => nokogiri adds #{tmp_links} containing #{tmp_links.size} URLs to count")

          @links = @links + tmp_links
        end
      end
    end # Worker

    attr_accessor :max_size

    def initialize(log, max_size = 3)
      @log = log
      @max_size = max_size

      @worker_increment = 0
      @workers = []
      @mutex = Mutex.new
    end

    def size
      @mutex.synchronize {@workers.size}
    end

    def busy?
      @mutex.synchronize {@workers.any? {|w| w.busy?}}
    end

    def status_of_workers
      values = []
      @mutex.synchronize {
        @workers.each {|w|

          value = ''
          value += "#{w.get_name} is "
          if w.busy?
            value += 'busy'
            value = value.red
          else
            value += 'idle'
            value = value.green
          end
          values.push(value)
        }

      }

      values
    end

    def shutdown
      @log.info("Shutting down pool..")
      @mutex.synchronize {@workers.each {|w| w.stop}}
    end

    alias :join :shutdown

    def get_worker
      while true
        worker = next_worker
        return worker if worker
      end
    end

    # Used by workers to report ready status
    def signal
      @cv.signal
    end

    private
    def next_worker
      @mutex.synchronize {available_worker || create_worker}
    end

    def available_worker
      @workers.each {|w| return w unless w.busy? }
      nil
    end

    def create_worker
      return nil if @workers.size >= @max_size
      worker = Worker.new(@log, @worker_increment += 1)
      @workers << worker
      worker
    end
  end # Pool

  # Initialize the filter
  def initialize(arguments)

    @arguments = arguments

    $count = 0
    $count_mutex = Mutex.new

    #@log = Logger.new('/home/walsh/Development/workspace/postfixUrlParsing/lib/log.txt')
    @log = Logger.new(STDOUT)
    @log.level = Logger::DEBUG #DEBUG INFO ERROR
    @log.datetime_format = "%H:%M:%S"

    # Set defaults
    $options = OpenStruct.new
    $options.port = 8081
    $options.workers = 10
    $options.verbose = false
    $options.sendmail = false
    $options.amqp_logging = false
    $options.use = :nokogiri
    $options.amqp_host = nil #'localhost'
    $options.amqp_port = nil #5672
    $options.amqp_vhost = nil #'/honeyclient.org'
    $options.amqp_routing_key = nil #'1.job.create.job.urls.job_alerts'
    $options.amqp_user = nil #'guest'
    $options.amqp_password = nil #'guest'
    $options.amqp_exchange = nil #'events'
    $options.send_to_amqp = false
    $options.tmp_folder_for_attachments = '/home/walsh/tmp'
    $options.uri_schemes = ['http', 'https', 'ftp', 'ftps']
    $options.ignore_attachments = false
    $options.timeout = 40
    $options.count_period = 3600
    $options.max_count = 4000
    $options.daemonize = true

    # Parse options, check arguments, then process the email

    if parsed_options?
      if arguments_valid?

        username = nil
        if $options.verbose
          IO.popen('whoami') { |io|
            username = io.read
          }

          start_time = Time.now
          @log.info("Start at #{start_time} by #{username}")

          output_options
        end

        process_arguments

      else
        @log.error("invalid arguments")
        SystemExit.new(-1)
      end
    else
      @log.error("invalid options")
      SystemExit.new(-1)
    end
  end

  def run
    throttle_amqp_sends

    mutex = Mutex.new

    $pool = ThreadPool.new(@log, $options.workers)

    @log.info("Running HoneyClient POSTFIX URL daemon on #{$options.port}...")

    server = TCPServer.open($options.port)

    shutdown = false
    connections = 1

    Thread.abort_on_exception=true

    until (shutdown != false)
      @log.debug("listening...")

      # might want to consider changing this over to SMTP Server interface
      
      Thread.start(server.accept) do |socket|

        begin 
          mutex.synchronize { connections += 1 }

          @log.debug "Handling connection from #{socket.peeraddr[2]}:#{socket.peeraddr[1]}..."

          if (socket.peeraddr[2].match(/^localhost/))

            text = socket.read if not socket.closed?

            if (text.match(/^From/))

              @log.debug("Processing email, getting worker...")

              socket.close if not socket.closed?

              worker = $pool.get_worker

              @log.debug("Running worker... ")

              worker.run(text)

            elsif (text.match(/^shutdown/i))

              @log.debug("Recieved shutdown command...")

              socket.close if not socket.closed?

              shutdown = true
              server.shutdown(2)

            elsif (text.match(/^get count/i))

              @log.debug("Writing count to client...")

              begin
                $count_mutex.synchronize {
                  value ="#{$count}\n"

                  if $count >= ($options.max_count - ($options.max_count/3))
                    value = value.red
                  elsif $count >= ($options.max_count - ($options.max_count * 2/3))
                    value = value.yellow
                  elsif $count < ($options.max_count - ($options.max_count * 2/3))
                    value = value.green
                  end
                
                  socket.write(value)

                }
                socket.close
              end if not socket.closed?

            elsif (text.match(/^set count/i))

              @log.debug("Setting count to value provide from client...")

              begin
                $count_mutex.synchronize {
                  #                value = text.match(/[0-9].*/)[0]
                  if (value = text.match(/[0-9].*/)[0]) != 0
                    $count = value.to_i
                    socket.write("count set to #{$count}\n".green)
                  else
                    socket.write("count remains #{$count}\n".red)
                  end
                }
                socket.close
              end if not socket.closed?

            elsif (text.match(/^get pool/i))

              @log.debug("Writing worker pool status to client...")

              begin
                $pool.status_of_workers.each {|status|
                  socket.write("#{status}\n")
                }
                socket.close
              end if not socket.closed?
            elsif (text.match(/^get connections/i))
            
              @log.debug("Writing connection count to client...")
            
              begin
                socket.write("#{mutex.synchronize {connections}}\n")
                socket.close
              end if not socket.closed?
            else
              @log.error("Unexpected data!")
              @log.error("=========\n#{text}\n=========\n")
              socket.close if not socket.closed?
            end

            @log.debug("Connection handler done...")
            mutex.synchronize { connections -= 1 }
          end
        rescue Errno::EPIPE => e
          @log.error("#{e.class} : #{e.msg}");
        end
      end
    end

    @log.debug("Shutting down HoneyClient POSTFIX URL daemon on #{$options.port}...")

  rescue Errno::EINVAL => e
    # swallow, this is thrown when a thread shutsdown the server and another
    # thread is listening for a new connection.
    
  rescue Interrupt => e
    @log.info("Shutting down HoneyClient POSTFIX URL daemon on #{$options.port}...")
    SystemExit.new(0)

  rescue Exception => e
    @log.error("Something bad happended...")
    @log.error("#{e.class}: #{e.message}")
    @log.error("#{e.backtrace.join("\n")}")
    SystemExit.new(1) #TODO: get a better status code value
  end

  private
  
  def throttle_amqp_sends()
    # Kick off a thread to reset count. the count is used to limit the number 
    # of AMQP messages sent in an $options.seconds_to_hold_count, typically
    # 3600 seconds.
    Thread.new() {
      loop do
        sleep $options.count_period
        @log.debug("Awaking to reset the count to 0...")
        $count_mutex.synchronize {$count = 0}
      end
    }
  end

  # Have the options been parsed
  def parsed_options?

    # Specify options
    option_parser = OptionParser.new { |opts|

      opts.banner = "Usage:  #$0 [options]"

      explanation = <<-EOE

A POSTFIX daemon that filters email for URLs and sends the URLs off to
RabbitMQ queue to be later processed.


Examples:
      ./postfix_url_daemon.rb --port 8081 --workers 10 --sendmail \\\\
        --amqp_host drone.honeyclient.org \\\\
        --amqp_port 5672 --amqp_vhost /collector.testing --amqp_user guest \\\\
        --amqp_password guest --exchange events \\\\
        --amqp_routing_key 1.job.create.job.urls.job_alerts \\\\
        --no-amqp_logging --timeout 100 --use nokogiri \\\\
        --daemonize --no-sendmail

      ./postfix_url_daemon.rb -h

      ./postfix_url_daemon.rb --no-daemonize
      EOE

      opts.separator(explanation)
      opts.separator('')
      opts.separator('Common options:')

      opts.on('-v', '--version', 'Display version number and exit.') {output_version ; exit 0 }

      opts.on('-V', '--[no-]verbose', "Run verbosely. Default is '#{$options.verbose}'.") { |boolean|
        $options.verbose = boolean
      }

      opts.on('-h', '--help', 'Display this help and exit.') do
        puts opts
        exit
      end

      opts.separator('')
      opts.separator('Daemon options:')

      opts.on('-P', '--port PORT', String, "Set port to PORT. Default is '#{$options.port}'.") { |port|
        $options.port = port
      }
      
      opts.on('-W', '--workers INTEGER', Integer, "Set number of workers to INTEGER. Default is '#{$options.workers}'.") { |workers|
        $options.workers = workers
      }

      opts.separator('')
      opts.separator('AMQP server options:')

      opts.on('--amqp_host HOST', String, 'Set amqp_host to HOST.') { |amqp_host|
        $options.amqp_host = amqp_host
      }

      opts.on('--amqp_port PORT', Integer, 'Set amqp_port to PORT.') { |amqp_port|
        $options.amqp_port = amqp_port
      }

      opts.on('-u', '--amqp_user USER', String, 'Set user login to USER.') { |user|
        $options.amqp_user = user
      }

      opts.on('-p', '--amqp_password PASSWORD', String, 'Set password to PASSWORD.') {|password|
        $options.amqp_password = password
      }

      opts.on('-e', '--amqp_exchange EXCHANGE', String, 'Set exchange to EXCHANGE.') {|exchange|
        $options.amqp_exchange = exchange
      }

      opts.on('-v', '--amqp_vhost VHOST', String, 'Set virtual host to VHOST.') {|vhost|
        $options.amqp_vhost = vhost
      }

      opts.on('-k', '--amqp_routing_key ROUTING_KEY', String, 'Set routing key to ROUTING_KEY.') {|routing_key|
        $options.amqp_routing_key = routing_key
      }

      opts.separator('')
      opts.separator('Actions:');

      opts.on('--[no-]sendmail', "Send message onto SendMail. Default is '#{$options.sendmail}'.") { |boolean|
        $options.sendmail = boolean
      }

      opts.on('--[no-]amqp_logging', "Enable AMQP server interaction logging. Default is '#{$options.amqp_logging}'.") { |boolean|
        $options.amqp_logging = boolean
      }

      opts.on('--use [PARSER]', [:uri, :hpricot, :nokogiri], "Select PARSER for HTML/XML (uri, hpricot, nokogiri). Default is '#{$options.use}'.") { |parser|
        $options.use = parser
      }

      opts.on('--[no-]ignore_attachments', "Don\'t parse attachments. Default is '#{$options.ignore_attachments}'.") { |boolean|
        $options.ignore_attachments = boolean
      }

      opts.on('-t', '--timeout SECONDS', Integer, "Set a SECONDS timeout for how long the filter should run parsing for URLs. Default is '#{$options.timeout}'.") { |timeout|
        $options.timeout = timeout
      }

      opts.on('-c', '--count_period SECONDS', Integer, "Set period of seconds to hold the count of URLs sent to the AMQP server to SECONDS. Default is '#{$options.count_period}'.") { |count_period|
        $options.count_period = count_period
      }

      opts.on('-m', '--max_count MAX_COUNT', Integer, "Set count of  URLS sent to the AMQP server to MAX_COUNT. Default is '#{$options.max_count}'.") { |max_count|
        $opts.max_count = max_count
      }

      opts.on('--[no-]daemonize', "Daemonize the service. Default is '#{$options.daemonize}'.") { |boolean|
        $options.daemonize = boolean
      }
    }

    option_parser.parse!(@arguments) rescue return false

    post_process_options

    true
  end

  # Dump command-line options
  def output_options

    @log.info("Options:")

    $options.marshal_dump.each do |name, val|
      @log.info("  #{name} = \"#{val}\"")
    end
  end

  # Performs post-parse processing on options
  def process_options

  end

  # Post process options
  def post_process_options
    $options.send_to_amqp = true if ($options.amqp_host != nil) && ($options.amqp_port != nil) && ($options.amqp_vhost != nil) && ($options.amqp_routing_key != nil) && ($options.amqp_user != nil) && ($options.amqp_password != nil) && ($options.amqp_exchange != nil)
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
end

# Create and run the URL filter daemon

filter = PostfixUrlDaemon.new(ARGV)

if $options.daemonize
  fork do
    daemonize
    filter.run
  end
else
  filter.run
end