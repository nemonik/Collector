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

  def send(from, to, filepath)

    if File.file? filepath # ignore '.', and '..'
      @log.debug("Creating message object...")
      message =RMail::Message::new
      message.header['From'] = "<#{from}>"
      message.header['To'] = "<#{to}>"
      message.header['Date'] = Time::new.rfc2822

      @log.debug("Creating text part...")
      text_part = RMail::Message::new
      text_part.header['Content-Type'] = 'TEXT/PLAIN; format=flowed; charset=US-ASCII'
      text_part.body = <<-EOE
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam tempus vulputate orci a ornare. Aliquam erat volutpat. Duis feugiat ligula quis nunc adipiscing pulvinar. Donec odio libero, lobortis eget condimentum vel, sodales et erat. In hac habitasse platea dictumst. Integer lorem nunc, tempor in iaculis at, interdum a nisl.

Curabitur suscipit quam massa, sed egestas quam. Proin eget purus eros, sit amet porta enim. Vivamus in velit sit amet ligula rutrum placerat. Sed tincidunt varius fringilla. Praesent sit amet nunc magna, vel rhoncus orci. Nulla vel odio mauris. Cras non orci id arcu dictum tincidunt et sit amet quam. Suspendisse vitae blandit lorem. Phasellus consectetur ullamcorper tempor. In eu lectus in massa varius luctus. Vivamus ac massa lacus, ut dignissim turpis. Phasellus hendrerit, quam a mollis viverra, lectus arcu egestas est, sit amet auctor lectus justo vel turpis.

Fusce quis dui quis orci mattis venenatis vel in dolor.

-Michael
EOE
      @log.debug("Creating html part...")
      html_part = RMail::Message::new
      html_part.header['Content-Type'] = 'text/html, charset=utf-8'
      html_part.body = "<html><body><p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam tempus vulputate orci a ornare. Aliquam erat volutpat. Duis feugiat ligula quis nunc adipiscing pulvinar. Donec odio libero, lobortis eget condimentum vel, sodales et erat. In hac habitasse platea dictumst. Integer lorem nunc, tempor in iaculis at, interdum a nisl.</p><p>Curabitur suscipit quam massa, sed egestas quam. Proin eget purus eros, sit amet porta enim. Vivamus in velit sit amet ligula rutrum placerat. Sed tincidunt varius fringilla. Praesent sit amet nunc magna, vel rhoncus orci. Nulla vel odio mauris. Cras non orci id arcu dictum tincidunt et sit amet quam. Suspendisse vitae blandit lorem. Phasellus consectetur ullamcorper tempor. In eu lectus in massa varius luctus. Vivamus ac massa lacus, ut dignissim turpis. Phasellus hendrerit, quam a mollis viverra, lectus arcu egestas est, sit amet auctor lectus justo vel turpis.</p><p>Fusce quis dui quis orci mattis venenatis vel in dolor.</p><p>-Michael</p></body></html>"

      attachment_part = nil


      attachment_part = RMail::Message::new

      mime_type = MIME::Types.of(filepath).first
      content_type = (mime_type ? mime_type.content_type : 'application/binary')
      filename = File.split(filepath)[1]

      @log.debug("Creating attachment part for #{filename}")
            
      message.header['Subject'] = "Sending #{filename}"

      attachment_part.header['Content-Type'] = "#{content_type}; name=#{filename}"
      attachment_part.header['Content-Transfer-Encoding'] = 'BASE64'
      attachment_part.header['Content-Disposition:'] = "attachment; filename=#{filename}"
      attachment_part.body = [File.open(filepath).read].pack('m')

      message.add_part(text_part)
      message.add_part(html_part)
      message.add_part(attachment_part) if (!attachment_part.nil?)

      smtp = Net::SMTP.start("localhost.localdomain", 25)
      @log.debug("Sending message...")
      smtp.send_message message.to_s, from, to
      smtp.finish
    else
      @log.debug("Skipping #{filepath}")
    end

  end

  def send_all(from, to, path)
    Dir.foreach(path) { |filename|

      filepath = File.join(path, filename)

      if File.file? filepath
        @log.debug("===========================")
        send(from, to, filepath)
        @log.debug("===========================")
      end
    }
  end
end

sender = Send_Email.new
sender.send_all('walsh@localhost.localdomain', 'walsh@localhost.localdomain', '../sample')


