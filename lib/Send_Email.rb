# == Author
#   Michael Joseph Walsh
#
# == Copyright
#   Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.

require 'mime/types'
require 'rmail'
require 'net/smtp'
require 'logger'

class Send_Email
  VERSION = '0.0.1'

  def initialize
    @log = Logger.new(STDOUT)
    @log.level = Logger::DEBUG
    @log.datetime_format = "%H:%M:%S"

    @log.debug("initialized...")
  end

  def send(from, to, filepaths)

    subject = "Sending "

    @log.debug("Creating message object...")
    message =RMail::Message::new
    message.header['From'] = "<#{from}>"
    message.header['To'] = "<#{to}>"
    message.header['Date'] = Time::new.rfc2822

    @log.debug("Creating text part...")
    text_part = RMail::Message::new
    text_part.header['Content-Type'] = 'TEXT/PLAIN; format=flowed; charset=US-ASCII'
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
    @log.debug("Sending message...")
    smtp.send_message message.to_s, from, to
    smtp.finish
  end

  def send_all(from, to, path, sleep_ms = 0, attach_max = 1)

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
          send(from, to, filepaths)
          if (sleep_ms == -1)
            sleep(rand())
          else
            sleep(sleep_ms)
          end
          @log.debug("===========================")
          
          filepaths = Array.new
        end
      else
        @log.debug("not sending #{filepath}")
      end
    }
  end

  def keep_sending(from, to, path, sleep_ms = 0, attach_max = 1)
    l = 0
    loop do
      @log.debug("starting interation #{l}")
      send_all(from, to, path, sleep_ms, attach_max)
      l += 1
    end
  end

end

sender = Send_Email.new
#sender.send_all('walsh@localhost.localdomain', 'walsh@localhost.localdomain', '../sample')
sender.keep_sending('walsh@localhost.localdomain', 'walsh@localhost.localdomain', '../sample', -1, 4)


