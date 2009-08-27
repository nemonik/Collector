#!/usr/local/bin/ruby19

# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

require 'mq'
require 'pp'
require 'json'
require 'optparse'
require 'ostruct'
require 'logger'

class DEBUG
  VERSION = '0.0.1'
  
  attr_reader :options
    
  # Initialize the filter
  def initialize(arguments)
    @arguments = arguments
      
    #@log = Logger.new('/home/walsh/Development/workspace/postfixUrlParsing/lib/debug.log') 
    @log = Logger.new(STDOUT)
    @log.level = Logger::DEBUG #ERROR 
                
    # Set defaults
    @options = OpenStruct.new
    @options.amqp_host = 'localhost'
    @options.amqp_port =  5672
    @options.amqp_vhost = '/honeyclient.org'
    @options.amqp_routing_key = '1.job.create.#'
    @options.amqp_user = 'guest'
    @options.amqp_password = 'guest'
    @options.amqp_exchange = 'events'
  end
                                                                                              
  # Parse options, check arguments, then process the email
  def run
    if parsed_options?
      if arguments_valid?              
        output_options                                      
        process_arguments

        puts 'starting'
        # read JSON message off AMQP exchange/queue
        EM.run do
          connection = AMQP.connect(:host => @options.amqp_host, :port => @options.amqp_port,
                                    :user => @options.amqp_user, :pass => @options.amqp_password,
                                    :vhost => @options.amqp_vhost, :logging => false)                                                        
 
          channel = MQ.new(connection)
          exchange = MQ::Exchange.new(channel, :topic, @options.amqp_exchange,
                                      {:passive => false, :durable => true,
                                       :auto_delete => false, :internal => false,
                                       :nowait => false})

          queue = MQ::Queue.new(channel, 'debug', {:durable => false, :auto_delete => true})
          queue.bind(exchange, :key => @options.amqp_routing_key) 
        
          queue.subscribe(:ack => true, :nowait => false) do |header, msg|
            header.ack
            puts '==============================================================================='          
            pp header
            puts '==============================================================================='                      
            puts msg
            puts '-------------------------------------------------------------------------------'            
          end
        
        end
        
      end    
    end
  rescue Interrupt => e
    puts("Debugger exiting...")
    SystemExit.new(0)
  end  
  
  protected
  
  # Have the options been parsed
  def parsed_options?
    # Specify options
    option_parser = OptionParser.new { |opts|
            
      opts.banner = "Usage:  #$0 [options]"
                  
      explanation = <<-EOE
    
A script to subscribe to a RabbitMQ exchange and print out JSON messages for
debug purposes.

Examples:
      DEBUGrb --host drone.honeyclient.org --port 5672 \\\\
        --vhost /collector.testing --user guest --password guest \\\\
        --exchange events --routing_key 1.job.create.job.urls.job_alerts \\\\\
                                                                                                      
      DEBUG.rb -h   
      EOE
                                                                                                                           
      opts.separator(explanation)
      opts.separator('')
      opts.separator('Common options:')
      
      opts.on('-v', '--version', 'display version number and exit.') {output_version ; exit 0 }

      opts.on('-h', '--help', 'display this help and exit.') do
        puts opts
       exit
      end                
                                                                                                                                                   
      opts.separator('')
      opts.separator('AMQP server options:')
                  
      opts.on('-H', '--host HOST', String, 'set host to HOST.') { |host|
        @options.amqp_host = host
      }
                                      
      opts.on('-P', '--port PORT', Integer, 'set port to PORT.') { |port|
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
                                              
    } 
    
    option_parser.parse!(@arguments) rescue return false
    
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

debug = DEBUG.new(ARGV)
debug.run                      
                                                                                                                                                                                       