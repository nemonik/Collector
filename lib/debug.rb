#!/bin/usr/local/ruby19

require 'mq'
require 'pp'
require 'json'

# read JSON message off AMQP exchange/queue
EM.run do
  connection = AMQP.connect(:host => 'localhost', :port => 5672,
                            :user => 'guest', :password => 'quest',
                            :vhost => '/honeyclient.org', :logging => false)
  channel = MQ.new(connection)
  exchange = MQ::Exchange.new(channel, :topic, 'events',
                              {:passive => false, :durable => true,
                               :auto_delete => false, :internal => false,
                               :nowait => false})

  queue = MQ::Queue.new(channel, 'events', :durable => true)
  queue.bind(exchange, :key => '1.job.create.job.urls')
  queue.subscribe(:ack => true, :nowait => false) do |header, msg|
    puts header
    puts msg
  end
end