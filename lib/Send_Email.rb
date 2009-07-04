#!/usr/local/bin/ruby19

# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

require 'mime/types'
require 'rmail'
require 'net/smtp'
require 'logger'
require 'guid'
require 'fileutils'
require 'Compression'

class Send_Email
  VERSION = '0.0.1'

  def initialize
    @log = Logger.new(STDOUT)
    @log.level = Logger::DEBUG
    @log.datetime_format = "%H:%M:%S"

    @msg_count = 0

    @log.debug("initialized...")
  end

  def send(from, to, filepaths, compress = false)

    subject = "Sending "

    @log.debug("Creating message object...")
    message =RMail::Message::new
    message.header['From'] = "<#{from}>"
    message.header['To'] = "<#{to}>"
    message.header['Date'] = Time::new.rfc2822

    @log.debug("Creating text part...")
    text_part = RMail::Message::new
    text_part.header['Content-Type'] = 'TEXT/PLAIN; format=flowed; charset=utf-8'
    text_part.body = <<-EOE
Lorem ipsum dolor sit amet, consectetur adipiscing elit. http://github.com/search?q=rmail&type=Everything&repo=&langOverride=&start_value=1 Nullam tempus vulputate orci a ornare. Aliquam erat volutpat. Duis feugiat ligula quis nunc adipiscing pulvinar. Donec odio libero, lobortis eget condimentum vel, sodales et erat. In hac habitasse platea dictumst. Integer lorem nunc, tempor in iaculis at, interdum a nisl.

Curabitur suscipit quam massa, sed egestas quam. http://www.hulu.com/videos/search?query=steve+jobs Proin eget purus eros, sit amet porta enim. Vivamus in velit sit amet ligula rutrum placerat. Sed tincidunt varius fringilla. Praesent sit amet nunc magna, vel rhoncus orci. Nulla vel odio mauris. Cras non orci id arcu dictum tincidunt et sit amet quam. Suspendisse vitae blandit lorem. Phasellus consectetur ullamcorper tempor. In eu lectus in massa varius luctus. Vivamus ac massa lacus, ut dignissim turpis. Phasellus hendrerit, quam a mollis viverra, lectus arcu egestas est, sit amet auctor lectus justo vel turpis.

Fusce quis dui quis orci mattis venenatis vel in dolor.

-Michael
EOE
    @log.debug("Creating html part...")
    html_part = RMail::Message::new
    html_part.header['Content-Type'] = 'text/html, charset=utf-8'
    html_part.body = "<html><body><p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. <a href=\"http://github.com/search?q=rmail&type=Everything&repo=&langOverride=&start_value=1\">http://github.com/search?q=rmail&type=Everything&repo=&langOverride=&start_value=1</a> Nullam tempus vulputate orci a ornare. Aliquam erat volutpat. Duis feugiat ligula quis nunc adipiscing pulvinar. Donec odio libero, lobortis eget condimentum vel, sodales et erat. In hac habitasse platea dictumst. Integer lorem nunc, tempor in iaculis at, interdum a nisl.</p><p>Curabitur suscipit quam massa, sed egestas quam. <a gref=\"http://www.hulu.com/videos/search?query=steve+jobs\">http://www.hulu.com/videos/search?query=steve+jobs</a> Proin eget purus eros, sit amet porta enim. Vivamus in velit sit amet ligula rutrum placerat. Sed tincidunt varius fringilla. Praesent sit amet nunc magna, vel rhoncus orci. Nulla vel odio mauris. Cras non orci id arcu dictum tincidunt et sit amet quam. Suspendisse vitae blandit lorem. Phasellus consectetur ullamcorper tempor. In eu lectus in massa varius luctus. Vivamus ac massa lacus, ut dignissim turpis. Phasellus hendrerit, quam a mollis viverra, lectus arcu egestas est, sit amet auctor lectus justo vel turpis.</p><p>Fusce quis dui quis orci mattis venenatis vel in dolor.</p><p>-Michael</p></body></html>"

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

  def send_all(from, to, path, sleep_sec = 0, attach_max = 1, compress = false)

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
          send(from, to, filepaths, compress)
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

  def keep_sending(from, to, path, sleep_sec = 0, attach_max = 1, compress = false)
    l = 0
    loop do
      @log.debug("starting interation #{l}")
      send_all(from, to, path, sleep_sec, attach_max, compress)
      l += 1
    end
  end

end

sender = Send_Email.new
#sender.send_all('walsh@localhost.localdomain', 'walsh@localhost.localdomain', '../sample')
#sender.send_all('walsh@localhost.localdomain', 'walsh@localhost.localdomain', '../sample-bad')
sender.keep_sending('walsh@localhost.localdomain', 'walsh@localhost.localdomain', '../sample', 10, 4, true)