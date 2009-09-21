# Author::    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
# Copyright:: Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.
# License::

require 'archive/tar/minitar'
require 'zip/zipfilesystem'
require 'zlib'
require 'fileutils'
require 'logger'

module Compression

  def zip(dst, names)
    Zip::ZipOutputStream.open(dst) { |zos|
      names.each { |name|
        zos.put_next_entry(File.basename(name))
        zos.print(IO.read(name))
        @log.debug("adding #{name} to #{dst}")
      }
    }
  end

  def unzip(zip_name, dst)
    Zip::ZipFile.open(zip_name) { |zipfile|
      zipfile.each { |file|
        file_name= File.join(dst, file.name)
        FileUtils.mkdir_p(File.dirname(file_name))
        zipfile.extract(file, file_name) unless File.exists?(file_name)
        @log.debug("unzipped #{file} to #{dst}")
      }
    }
  end

  def gzip(names)

    names.each { |name|

      Zlib::GzipWriter.open(name + '.gz') { |gzip|
        gzip.write(File.open(name).read)
      }

      @log.debug("gzipped #{name}")

      FileUtils.rm(name) # to model cmd-line behavior
    }

  end

  def gunzip(name)
    Zlib::GzipReader.open(name) { |gzip|
      dst = name.gsub(/\.gz$/,'')
      @log.debug("uncompressing gzip to #{dst}")
      File.open(dst, "w") { |file|
        file.write(gzip.read)
      }
    }

    @log.debug("guzipped #{name}")

    FileUtils.rm(name) # to model cmd-line behavior
  end

  def bzip2(names)
    names.each { |name|
      `bzip2 #{name}`
      @log.debug("bzip2ed #{name}")
    }
  end

  def bunzip2(name)
    `bunzip2 #{name}`
    @log.debug("bunzip2ed #{name}")
  end

  def tar(dst_name, names)
    out = Archive::Tar::Minitar::Output.new(dst_name)
    names.each { |name|
      Archive::Tar::Minitar.pack_file(name, out)
      @log.debug("adding #{name} to #{dst_name}")
    }
    out.close
  end

  def untar(tar_name, dst)
    Archive::Tar::Minitar.unpack(tar_name, dst)
    @log.debug("untared #{tar_name} to #{dst}")
  end
  
end
