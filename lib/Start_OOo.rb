#!/usr/local/bin/ruby19

# == Synopsis
#   A POSTFIX script to start/stop OpenOffice headless server
#
# == Usage:  Start_OOo.rb {start/stop}
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

require 'fileutils'

class Start_OOo
  def initialize
  end

  def run
    cmd = ARGV[0]
    pid = '/var/run/openoffice-server.pid'

    if (cmd == 'start')

      if (File.exist?(pid))
        puts 'OpenOffice headless server already started.'
        exit
      else
        puts 'OpenOffice headless server starting...'
        IO.popen('/usr/lib64/openoffice.org3/program/soffice -headless -nologo -nofirststartwizard -accept="socket,host=localhost,port=8100;urp;" & > /dev/null 2>&1') {
          File.open(pid, 'w') {|f| f.write("#{$$}") }
        }
      end

    elsif (cmd == 'stop')

      if (File.exist?(pid))
        puts 'Stopping OpenOffice headless server...'
        `killall -9 soffice && killall -9 soffice.bin`
        FileUtils.rm(pid)
        exit
      else
        puts 'Openoffice headless server not running.'
        exit
      end

    else

      puts 'Usage: Start.OOo.rb {start|stop}'
      exit 1

    end
    exit 0
  end

start_ooo = Start_OOo.new
start_ooo.run

end