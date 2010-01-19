#!/usr/local/bin/ruby19

# == Synopsis
#   A daemon to parse URLs from emails pulled off a socket
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2010 The MITRE Corporation.  All Rights Reserved.
# License:: GNU GENERAL PUBLIC LICENSE

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
require 'eventmachine'
require 'term/ansicolor'
require 'daemons/daemonize'
require 'ooo_conversion_srvc_client'
require 'mime'
require 'SysVIPC'
require 'inotify'
require "redis"
require 'digest/md5'

include SysVIPC
include Daemonize
include Term::ANSIColor

class UrlParsingSrvc

  WORKER_STATUS_MTYPE = 1
  MSGMAX = 8191
  MODE = 0660

  LOG = Logger.new(STDOUT)
  LOG.level = Logger::DEBUG #DEBUG INFO ERROR
  LOG.datetime_format = "%H:%M:%S"

  class Worker
    include Compression, Mime
    
    def initialize()

      Signal.trap('HUP') {
        @running = false

        @inotify.close
      }

      @running = true

      @inotify = Inotify.new

      @key = ftok($options.sysv_ipc_msg_queue_path, 1)
      @msg_queue = MessageQueue.new(@key, IPC_CREAT | MODE)

      @ooo_conversion_srvc_client = OOoConversionSrvcClient.new()

      @msg_text = nil
      @mail_filename = nil
      @recipients = []
      @links = []
      @x_count = nil # used inconjunction with Send_Email.rb script.

      @db = Redis.new

    end

    def run

      @inotify.add_watch($options.mail_incoming_path, Inotify::MOVED_TO)

      @msg_queue.send(WORKER_STATUS_MTYPE, "{\"#{Process.pid}\":\"idle\"}")

      begin
        @inotify.each_event do |ev|

          begin
            
            FileUtils.move(File.join($options.mail_incoming_path, ev.name), @mail_filename = File.join($options.mail_being_processed_path, ev.name))

            while (File.size?(@mail_filename) == nil) do
              
            end

            @msg_text = IO.read(@mail_filename)

            LOG.debug("PID:#{Process.pid} accepted a new connection")
            @msg_queue.send(WORKER_STATUS_MTYPE, "{\"#{Process.pid}\":\"busy\"}")

            if (!@msg_text.nil?)

              LOG.debug("message not nil...")
              process_email
              #send_to_msg_queue if $options.send_to_amqp
              defer_links_to_outgoing_amqp_msgs_folder if $options.send_to_amqp
              free
            end

            if !@running
              break
            end

          rescue Errno::ENOENT
            # swallow, another process grabbed the mail file to handle...
          rescue Exception => e
            LOG.error("#{e.class} : '#{e.message}\n#{e.backtrace.join("\n")}")
          ensure
            @msg_queue.send(WORKER_STATUS_MTYPE, "{\"#{Process.pid}\":\"idle\"}")
          end

          LOG.debug("back to waiting to be notified")

        end
      rescue Errno::EBADF
        # swallow, process recieved HUP signal
      end

      puts("#{Process.pid} expiring...")
      exit
    end

    def free
      @links = []
      @recipients = []
      @msg_text = nil
      @x_count = nil

      begin
        FileUtils.remove_file(@mail_filename)
      rescue Exception
        #swallow
      end

      @mail_filename = nil
    end

    private

    def md5sum(file_name)
      if File.exists?(file_name)
        Digest::MD5.hexdigest(IO.read(file_name))
      end
    end

    def urls_from_db(checksum)
      urls = @db.list_range(checksum, 0, -1)

      @links = @links + urls

      LOG.debug(" => returning #{urls} from db for #{checksum}".blue) # if $options.verbose

      urls
    end

    def urls_to_db(checksum, urls)
      LOG.debug(" => db storing #{urls} for #{checksum}".blue) if $options.verbose

      @db.delete checksum

      urls.each { |url|
        @db.push_tail checksum, url
      }
    end

    # Record the error for posterity
    def record_error(e)
      if ((!@message_id.nil?) && (!@message_id.empty?))
        begin
          LOG.warn("#{e.class} : '#{e.message} for message '#{@message_id}'\n#{e.backtrace.join("\n")}")

          @message_id = @message_id.gsub('<', '').gsub('>','')
          folder_name = File.join($options.bad_msg_path, @message_id)
          FileUtils.mkdir_p(folder_name)

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
        LOG.warn("#{e.class} : #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end

    # Process the email, pulling out all the unique links and send to AMQP
    # server to be later be processed
    def process_email

      #LOG.debug("#{@msg_text}")

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

        LOG.debug("sending msg #{@message_id} to sendmail...")
        IO.popen("#{sendmail_cmd}", "w") { |sendmail| sendmail << "#{@msg_text}" }

      end

      if (message.multipart?)
        message.each_part { |part|

          header = part.header

          doc = (header['Content-Transfer-Encoding'] == 'quoted-printable') ? part.body.unpack('M')[0] : part.body

          LOG.debug('====================')

          if ((header['Content-Type'].downcase.include? 'text/plain') && (!header.has_key?('Content-Disposition')))

            LOG.debug('handling plain text part...')

            get_links_with_uri(doc)

          elsif ((header['Content-Type'].downcase.include? 'text/html') && (!header.has_key?('Content-Disposition')))
            LOG.debug('handling html part...')

            get_links(doc)

          elsif ((header.has_key?('Content-Disposition')) && (header['Content-Disposition'].downcase.include? 'attachment') && (!$options.ignore_attachments))

            if (header['Content-Transfer-Encoding'].downcase.include? 'base64')

              LOG.debug('handling base64 attachment...')

              # create unique directory to hold the file for processing, and allow for easy cleanup
              folder_name = $options.tmp_folder_for_attachments + "/" + Guid.new.to_s
              FileUtils.mkdir_p(folder_name)

              file_name = File.join(folder_name, header['Content-Type'].chomp.split(/;\s*/)[1].split(/\s*=\s*/)[1].gsub(/\"/, ""))

              file = File.new(file_name, 'w')
              file.syswrite(base_64_decode = doc.unpack('m')[0]) # base64 decode and write out
              file.close

              begin
                #Timeout::timeout($options.timeout) {

                checksum = Digest::MD5.hexdigest(base_64_decode)
                urls_to_db(checksum, process_file(file_name)) if urls_from_db(checksum).empty?
                #}
                #rescue Timeout::Error
                #
                #                  LOG.info(' => Processing of attachments has timed out.')
              rescue Exception => e

                record_error(e)
              ensure
                FileUtils.rm_rf(folder_name) #unless folder_name.nil?
              end
            else
              LOG.warn(" => Unhandled content-transfer-encoding #{header['Content-Transfer-Encoding']}")
            end

          elsif (header['Content-Type'].downcase.include? 'message/rfc822')

            LOG.debug('handling forwarded email...')

            process_email(doc)

          else # handle unknown content-type

            log(:warn,"Unhandled content-type #{header['Content-Type']}")

          end if ((doc.class != NilClass) && (doc.strip != ''))
        }
      else
        get_links_with_uri(message.body)
      end
    rescue Exception => e
      record_error(e)
    end

    # Process the file
    def process_file(file_name, part_of_archive = false)

      return_links = []

      LOG.debug(" => writing file #{file_name}...")

      info = mime_shared_info(file_name)

      checksum = md5sum(file_name)
      if (part_of_archive)
        urls = urls_from_db(checksum)
        return urls unless urls.empty?
      end

      LOG.debug(" => info = #{info}")

      if (info[0] == 'application/pdf')
        out = nil
        IO.popen("pdftotext #{file_name} /dev/stdout") {|stdout|
          out = stdout.read
        }

        return_links = get_links_with_uri(out)

      elsif ('application/rtf, text/plain, text/csv'.include?(info[0]))
         return_links = get_links_with_uri(File.open(file_name).read)

      elsif ('text/html, application/xml'.include?(info[0]))
         return_links = get_links(File.open(file_name).read)

      elsif (info[0] == 'application/zip')
         return_links = process_compressed(file_name, 'application/zip')

      elsif ('application/x-compressed-tar, application/x-gzip'.include?(info[0]) || info[0].include?('application/x-gz'))
         return_links = process_compressed(file_name, 'application/x-gzip')

      elsif (info[0].include?('application/x-bz'))
         return_links = process_compressed(file_name, 'application/x-bzip')

      elsif (info[0] == 'application/x-tar')
         return_links = process_compressed(file_name, 'application/x-tar')

      elsif (info[1].include?('openoffice.org-calc'))
        # calc/excel docs need to first be converted to a csv, then
        # the urls pulled from

        csv_file_name = temp_file(file_name, 'csv')

        return_links = get_links_with_uri(File.open(csv_file_name).read) if @ooo_conversion_srvc_client.process_office_file(file_name, csv_file_name)

      elsif (info[1].include?('openoffice.org-impress'))
        # presentation/powerpoint docs cannot be convert straight away, but
        # instead need a two step process of first being converted to
        # pdf and then to text
        # TODO: try another way, now that we are using JODconvert 3.0

        pdf_file_name = temp_file(file_name, 'pdf')

        if (@ooo_conversion_srvc_client.process_office_file(file_name, pdf_file_name))
          
          out = nil
          IO.popen("pdftotext #{pdf_file_name} /dev/stdout") {|stdout|
            out = stdout.read
          }

           return_links = get_links_with_uri(out)
        end

      elsif (info[1].include?('openoffice'))

        html_file_name = temp_file(file_name, 'html')

        html = File.open(html_file_name).read if @ooo_conversion_srvc_client.process_office_file(file_name, html_file_name)

        LOG.debug(" => service returned : #{html}") if $options.verbose

        return_links = get_links(html)

      else
        raise UnsupportedDocumentType.new("Unhandled file type of '#{info}'.")
      end

      urls_to_db(checksum, return_links) if part_of_archive && !return_links.empty?

      return_links

    rescue Exception => e
      record_error(e)
    end

    def temp_file(file_name, extension)

      LOG.debug("the source filen_name: #{file_name} ")
      LOG.debug("desired output extensions: #{extension}")

      temp_file_name = nil
      path, base = File.split(file_name)

      #base.slice!(base.rindex('.'), base.length)
      
      loop do
        temp_file_name = File.join(path, "#{Guid.new.to_s}.#{extension}")
        break if !File.exists?(temp_file_name)
      end

      LOG.debug("the converted file is outputed to: #{temp_file_name}")

      return temp_file_name
    end

    # Process the compressed file using a particular compression
    def process_compressed(file_name, compression)

      return_links = []

      dst = File.dirname(file_name)

      LOG.debug(" => processing #{compression} compressed #{file_name}...")

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
        raise UnhandledFormOfCompression.new("'#{compression}' unhandled form of compression.")
      end

      # process contents, drilling into sub-folders if they exist
      Find.find(dst) { |contents|
        if File.file? contents
          LOG.debug(" => from #{File.basename(file_name)}, processing #{contents}")
          return_links = return_links + process_file(contents, true)
        end
      }

      return_links
    rescue Exception => e
      record_error(e)
    end

    # Send the links off to AMQP exchange/queue
    # TODO: untested code
    def send_to_msg_queue

      # strip off dupes
      LOG.debug("URL count before compact #{@links.size}")
      @links = @links.uniq.compact

      if (@links.size > 0)

        client_socket = TCPSocket.new('localhost', $options.port)

        client_socket.write("inc count #{@links.size}")
        client_socket.flush

        value = client_socket.read
        client_socket.close

        if (value.match(/[0-9].*/)[0].to_i <= $options.max_count)
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

          #TODO: why do i have this commented out?
          #job['job_alerts'] = job_alerts

          wrapper = {}
          wrapper['job'] = job

          LOG.info("Publishing #{@links.size} links to AMQP server :: #{@links}...")

          begin
            EM.run do
              connection = AMQP.connect(:host => $options.amqp_host, :port => $options.amqp_port,:user => $options.amqp_user, :pass => $options.amqp_password, :vhost => $options.amqp_vhost, :logging => $options.amqp_logging)
              channel = MQ.new(connection)
              exchange = MQ::Exchange.new(channel, :topic, $options.amqp_exchange, {:key=> $options.amqp_routing_key, :passive => false, :durable => true, :auto_delete => false, :internal => false, :nowait => false})
              #      queue = MQ::Queue.new(channel, 'events', :durable => true)
              #      queue.bind(exchange)
              #      queue.publish(JSON.pretty_generate job, {:routing_key => $options.amqp_routing_key, :persistent => true})
              #      exchange.publish(JSON.pretty_generate job, {:routing_key => $options.amqp_routing_key, :persistent => true})
              exchange.publish(JSON.pretty_generate(wrapper), {:persistent => true})
              connection.close{ EM.stop }
            end
          rescue Exception => e
            LOG.error("#{e.class} : #{e.message}; Problem sending message to AMQP server")
          end
        else
          LOG.info("Not publishing  #{@links.size} links to AMQP server :: #{@links}...")
        end
      end
    rescue Exception => e
      record_error(e)
    end

    def defer_links_to_outgoing_amqp_msgs_folder
      # strip off dupes
      LOG.debug("URL count before compact #{@links.size}")
      @links = @links.uniq.compact

      if (@links.size > 0)

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

        #TODO: why do i have this commented out?
        #job['job_alerts'] = job_alerts

        wrapper = {}
        wrapper['job'] = job

        LOG.info("Writing AMQP message containing #{@links.size} links to outgoing folder:: #{@links}...")

        begin
          File.open(File.join($options.outgoing_amqp_msgs_path, @message_id), 'w') { |f| f.write(JSON.pretty_generate(wrapper))}
        rescue Exception => e
          LOG.error("#{e.class} : #{e.message}; Problem writing AMQP message to outgoing folder.")
        end
      end
    rescue Exception => e
      record_error(e)
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
        LOG.error(" => Unknown parser #{$options.use} requested!");
      end
    end

    # Retrieves all links in the text described by $options.uri_schema
    def get_links_with_uri(text)

      # cleanup encoding...
      ic = Iconv.new("#{text.encoding.name}//IGNORE", "#{text.encoding.name}")
      text = ic.iconv(text + ' ')[0..-2]

      return_links = []

      if ((!text.nil?) && (!text.strip.empty?))
        URI.extract(text, $options.uri_schemes) {|url|
          url = url.gsub(/\/$/,'').gsub(/\)$/, '').gsub(/\>/,'') #TODO: need a better regex
          return_links.push(url)
        }

        LOG.debug(" => URI adds #{return_links} containing #{return_links.size} URLs to count")

        @links = @links + return_links
      else
        LOG.debug(' => text is empty')
      end

      return_links
    rescue Exception => e
      record_error(e)
    end

    # Get the links from the text using the Hpricot XML/HTML parser
    def get_links_with_hpricot(text)

      return_links = []

      if ((!text.nil?) && (!text.strip.empty?))
        # the version of hpricot I developed against
        # is not attribute case insensitive
        text = text.gsub(/\sHREF/, ' href')
        text = text.gsub(/\sSRC/, ' src')

        # parse HTML content after fixing up content
        html = Hpricot(text, :fixup_tags => true)

        # pull URLs from anchor tags
        html.search('//a').map { |href|
          if (href['href'] != nil)
            url = URI.extract(href['href'], $options.uri_schemes)[0]
            return_links.push(url.gsub(/\/$/,'')) if url
          end
        }

        # pull URLs from img tags
        html.search('//img').map { |img|
          if (img['src'] != nil)
            url = URI.extract(img['src'], $options.uri_schemes)[0]
            return_links.push(url.gsub(/\/$/,''))  if url
          end
        }

        LOG.debug(" => hpricot adds #{return_links} containing #{return_links.size} URLs to count")

        @links = @links + return_links
      end

      return_links
    rescue Exception => e
      record_error(e)
    end

    # Get the links from the text using the Nokogiri XML/HTML parser
    def get_links_with_nokogiri(text)

      return_links = []

      if ((!text.nil?) && (!text.strip.nil?))
        html = Nokogiri::HTML(text)

        # pull URLs from anchor tags
        html.xpath('//a').map { |href|
          if (href['href'] != nil)
            url = URI.extract(href['href'], $options.uri_schemes)[0]
            return_links.push(url.gsub(/\/$/,'')) if url
          end
        }

        # pull URLs from img tags
        html.xpath('//img').map { |img|
          if (img['src'] != nil)
            url = URI.extract(img['src'], $options.uri_schemes)[0]
            LOG.debug("  src url is #{url}")
            return_links.push(url.gsub(/\/$/,''))  if url
          end
        }

        LOG.debug(" => nokogiri adds #{return_links} containing #{return_links.size} URLs to count")

        @links = @links + return_links
      end

      return_links
    rescue Exception => e
      record_error(e)
    end
  end # Worker

  def initialize(arguments)
    @arguments = arguments

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
    $options.tmp_folder_for_attachments = '/var/spool/mail/filter/tmp'
    $options.bad_msg_path = '/var/spool/mail/filter/bad_msg'
    $options.mail_incoming_path = '/var/spool/mail/filter/mail_incoming'
    $options.mail_being_processed_path = '/var/spool/mail/filter/being_processed'
    $options.outgoing_amqp_msgs_path = '/var/spool/mail/filter/outgoing_amqp_msgs'
    $options.sysv_ipc_msg_queue_path = '/tmp/postfix_url_msg_queue'
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
          LOG.info("Start at #{start_time} by #{username}")

          output_options
        end

        process_arguments

      else
        LOG.error("invalid arguments")
        SystemExit.new(-1)
      end
    else
      LOG.error("invalid options")
      SystemExit.new(-1)
    end

    FileUtils.mkdir_p($options.mail_incoming_path) unless Dir.exist?($options.mail_incoming_path)

    FileUtils.mkdir_p($options.mail_being_processed_path) unless Dir.exist?($options.mail_being_processed_path)

    FileUtils.mkdir_p($options.outgoing_amqp_msgs_path) unless Dir.exist?($options.outgoing_amqp_msgs_path)

    FileUtils.touch($options.sysv_ipc_msg_queue_path) unless File.exist?($options.sysv_ipc_msg_queue_path)

    @key = ftok($options.sysv_ipc_msg_queue_path, 1)
    @msg_queue = MessageQueue.new(@key, IPC_CREAT | MODE)

    @workers = Hash.new

    $options.workers.times {|i|
      worker = Worker.new

      pid = fork do
        worker.run
      end

      Process.detach(pid)
    }

    @connections_mutex = Mutex.new
    @count_mutex = Mutex.new

    @inotify = Inotify.new

    @count = 0

  end

  def run()

    @ooo_conversion_srvc_client = OOoConversionSrvcClient.new()
   
    exit if (!@ooo_conversion_srvc_client.start)

    kick_off_workers_monitor_thread
    kick_off_throttle_amqp_sends_thread
    kick_off_send_amqp_msgs_thread

    server = TCPServer.open($options.port)
    server_hostname = Socket.gethostname

    connections = 1
    shutdown = false

    Thread.abort_on_exception=true

    LOG.info("Running HoneyClient POSTFIX URL daemon on #{$options.port}...")

    until (shutdown != false)
      LOG.debug("listening...")

      Thread.start(server.accept) do |socket|

        begin

          @connections_mutex.synchronize { connections += 1 }

          LOG.info("Handling connection from #{socket.peeraddr[2]}:#{socket.peeraddr[1]}...")

          if (socket.peeraddr[2].match(server_hostname))
            text = socket.read if not socket.closed?

            if (text.match(/^shutdown/i))
              LOG.debug("Recieved shutdown command...")

              shutdown = true

              @inotify.close

              @workers.each { |pid, status|
                Process.kill('HUP', pid)
              }

              @msg_queue.rm

              socket.write("Shutting down...")
              socket.flush

              socket.close unless socket.closed?

              shutdown = true
              server.shutdown(2)

              exit
            elsif (text.match(/^get count/i))

              LOG.debug("Writing count to client...")

              begin

                value = 0
                
                @count_mutex.synchronize {
                  value = @count
                }

                if value >= ($options.max_count - ($options.max_count/3))
                  value = "#{value}".red
                elsif value >= ($options.max_count - ($options.max_count * 2/3))
                  value = "#{value}".yellow
                elsif value < ($options.max_count - ($options.max_count * 2/3))
                  value = "#{value}".green
                end

                socket.write(value)
                socket.flush

                socket.close
              end unless socket.closed?

            elsif (text.match(/^inc count/i))

              value = text.match(/[0-9].*/)[0].to_i

              LOG.debug("Incrementing count by #{value}...")

              begin
                @count_mutex.synchronize {
                  @count += value
                  socket.write("#{@count}")
                }
              
                socket.flush
                socket.close
              end unless socket.closed?

            elsif (text.match(/^get pool/i))
              begin

                @workers.each_pair {|pid, status|
                  if (status == 'idle')
                    socket.write("#{pid} -- #{status}\n".green)
                  else
                    socket.write("#{pid} -- #{status}\n".red)
                  end
                }

                socket.flush
                socket.close
              end unless socket.closed?
            elsif (text.match(/^get connections/i))

              LOG.debug("Writing connection count to client...")

              @connections_mutex.synchronize { connections -= 1 }

              begin
                socket.write("#{@connections_mutex.synchronize {connections}}\n")
                socket.close
              end unless socket.closed?
          
            else
              LOG.error("Unexpected data!")
              LOG.error("=========\n#{text}\n=========\n")
              socket.close unless socket.closed?
            end

            LOG.debug("Connection handler done...")
          end
        rescue Errno::EPIPE => e
          puts "#{e.class} : #{e.message}\n"
          puts "calling log.warn"
          LOG.warn("#{e.class} : #{e.message}")
        ensure
          socket.close unless socket.closed?
        end
      end
    end
  end

  private

  def kick_off_workers_monitor_thread()

    #TODO mutex locking around worker has may or may not be needed

    Thread.new() do
      loop do
        begin
          status_msg = @msg_queue.receive(WORKER_STATUS_MTYPE, MSGMAX)

          @workers[status_msg.match(/[0-9].*/)[0].to_i] = status_msg.match(/idle|busy/)[0]

        rescue Errno::EINVAL
          # swallow
        rescue Exception => e
          LOG.error("#{e.class} : '#{e.message}\n#{e.backtrace.join("\n")}")
        end
      end
    end
  end

  def kick_off_throttle_amqp_sends_thread()
    # Kick off a thread to reset count. the count is used to limit the number
    # of AMQP messages sent in an $options.seconds_to_hold_count, typically
    # 3600 seconds.
    Thread.new() do
      loop do
        sleep $options.count_period
        @log.debug("Awaking to reset the count to 0...")
        @count_mutex.synchronize {
          @count = 0
        }
      end
    end
  end

  def kick_off_send_amqp_msgs_thread()

    @inotify.add_watch($options.outgoing_amqp_msgs_path, Inotify::CREATE)

    Thread.new() do
      begin
        @inotify.each_event do |ev|

          begin
            begin

              msg_text = IO.read(amqp_msg_filename = File.join($options.mail_being_processed_path, ev.name))

              FileUtils.remov_file(amqp_msg_filename)

            rescue Errno::ENOENT
              # swallow
            rescue Exception => e
              LOG.error("#{e.class} : '#{e.message}\n#{e.backtrace.join("\n")}")
            end

            url_size = (JSON.parse(msg_text))['job']['urls'].size
            send_msg = false

            @count_mutex.synchronize {
              if (url_size + @count <= $options.max_count)
                @count += url_size
                send_msg = true
              end
            }
          
            if (send_msg)
              begin
                EM.run do
                  connection = AMQP.connect(:host => $options.amqp_host, :port => $options.amqp_port,:user => $options.amqp_user, :pass => $options.amqp_password, :vhost => $options.amqp_vhost, :logging => $options.amqp_logging)
                  channel = MQ.new(connection)
                  exchange = MQ::Exchange.new(channel, :topic, $options.amqp_exchange, {:key=> $options.amqp_routing_key, :passive => false, :durable => true, :auto_delete => false, :internal => false, :nowait => false})
                  #      queue = MQ::Queue.new(channel, 'events', :durable => true)
                  #      queue.bind(exchange)
                  #      queue.publish(JSON.pretty_generate job, {:routing_key => $options.amqp_routing_key, :persistent => true})
                  #      exchange.publish(JSON.pretty_generate job, {:routing_key => $options.amqp_routing_key, :persistent => true})
                  exchange.publish(msg_text, {:persistent => true})
                  connection.close{ EM.stop }
                end
              rescue Exception => e
                LOG.error("#{e.class} : #{e.message}; Problem sending message to AMQP server")
              end
            else
              LOG.info("Not publishing  #{@links.size} links to AMQP server :: #{@links}...")
            end
          ensure
            begin
              FileUtils.remove_file(amqp_msg_filename)
            rescue Exception
              # swallow
            end
          end
        end
      rescue Errno::EBADF
        # swallow
      end
    end
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

# Create and run the URL parsing service

filter = UrlParsingSrvc.new(ARGV)

if $options.daemonize
  fork do
    daemonize
    filter.run
  end
else
  filter.run
end
