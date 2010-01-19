#!/usr/local/bin/ruby19

# == Synopsis
#   Unit tests for the Java-baased OOo Conversion Service
#
# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2010 The MITRE Corporation.  All Rights Reserved.
# License:: GNU GENERAL PUBLIC LICENSE


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

    assert(((!response['outputBase64FileContents'].nil?)  && (response['msg'].downcase.index('success') != nil)), true)
    
  end

  def test_send_request_with_filepaths

    request = {}

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

    assert(((File.exists?('/home/walsh/samples/537aaf39-9416-80ac-ce45-0bd6ff531a88.txt')) && (response['msg'].downcase.index('success') != nil)), true)

  end

end
