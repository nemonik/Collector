#!/usr/local/bin/ruby19

require "test/unit"
require 'json'
require 'socket'

class TestOOoConversionServer < Test::Unit::TestCase

  def setup

  end

  def teardown

  end

  def test_send_request_with_base64_content

    request = {}

    request['outputFormat'] = 'text'
    request['outputFilename'] = '537aaf39-9416-80ac-ce45-0bd6ff531a88.txt'
    request['inputFilename'] = '537aaf39-9416-80ac-ce45-0bd6ff531a88.doc'
    request['inputBase64FileContents'] = [IO.read('/home/walsh/samples/537aaf39-9416-80ac-ce45-0bd6ff531a88.doc')].pack("m")

    client_socket = TCPSocket.new('localhost', 8080)

    start = Time.now

    client_socket.write(JSON.generate(request))
    client_socket.flush

    buffer = client_socket.read

    response = JSON.parse(buffer)
    client_socket.close

    finished = Time.now - start

    puts "response in #{finished} seconds"

    assert(!response['outputBase64FileContents'].nil?, true)
    
  end

  def test_send_request_with_filepaths

    request = {}

    request['outputFormat'] = 'text'
    request['outputFilename'] = '/home/walsh/samples/537aaf39-9416-80ac-ce45-0bd6ff531a88.txt'
    request['inputFilename'] = '/home/walsh/samples/537aaf39-9416-80ac-ce45-0bd6ff531a88.doc'
    request['inputBase64FileContents'] = nil

    client_socket = TCPSocket.new('localhost', 8080)

    start = Time.now

    client_socket.write(JSON.generate(request))
    client_socket.flush

    buffer = client_socket.read

    response = JSON.parse(buffer)
    client_socket.close

    finished = Time.now - start

    puts "response in #{finished} seconds"

    assert(File.exists?('/home/walsh/samples/537aaf39-9416-80ac-ce45-0bd6ff531a88.txt'), true)

  end
end
