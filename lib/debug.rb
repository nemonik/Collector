#!/bin/usr/local/ruby19

require 'mq'
require 'pp'
require 'json'

AMQP.start(:host => 'localhost') { MQ.queue('jobs', :durable => true).subscribe{ |job| puts job } }
