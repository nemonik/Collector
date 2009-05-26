# == Author
#   Michael Joseph Walsh
#
# == Copyright
#   Copyright (c) 2009 The MITRE Corporation.  All Rights Reserved.

require 'archive/tar/minitar'
require 'zip/zipfilesystem'
require 'zlib'
require 'fileutils'
require 'logger'

module Compression

  @log = Logger.new(STDOUT)
  @log.level = Logger::DEBUG
  @log.datetime_format = "%H:%M:%S"

  def self.zip(dst, names)
    Zip::ZipOutputStream.open(dst) { |zos|
      names.each { |name|
        zos.put_next_entry(File.basename(name))
        zos.print(IO.read(name))
        @log.debug("adding #{name} to #{dst}")
      }
    }
  end

  def self.unzip(zip_name, dst)
    Zip::ZipFile.open(zip_name) { |zipfile|
      zipfile.each { |file|
        file_name= File.join(dst, file.name)
        FileUtils.mkdir_p(File.dirname(file_name))
        zipfile.extract(file, file_name) unless File.exists?(file_name)
        @log.debug("unzipped #{file} to #{dst}")
      }
    }
  end

  def self.gzip(names)

    names.each { |name|

      Zlib::GzipWriter.open(name + '.gz') { |gzip|
        gzip.write(File.open(name).read)
      }

      @log.debug("gzipped #{name}")

      FileUtils.rm(name) # to model cmd-line behavior
    }

  end

  def self.gunzip(names)

    names.each { |name|

      Zlib::GzipReader.open(name) { |gzip|
        File.open(File.basename(name) - 'gzip', "w") { |file|
          file.write(gzip.read)
        }
      }

      @log.debug("guzipped #{name}")

      FileUtils.rm(name) # to model cmd-line behavior
    }

  end

  def self.bzip2(names)
    names.each { |name|
      `bzip2 #{name}`
      @log.debug("bzip2ed #{name}")
    }
  end

  def self.bunzip2(names)
    names.each { |name|
      `bunzip2 #{name}`
      @log.debug("bunzip2ed #{name}")
    }
  end

  def self.tar(dst_name, names)
    out = Archive::Tar::Minitar::Output.new(dst_name)
    names.each { |name|
      Archive::Tar::Minitar.pack_file(name, out)
      @log.debug("adding #{name} to #{dst_name}")
    }
    out.close
  end

  def self.untar(tar_name, dst)
    Archive::Tar::Minitar.Minitar.unpack(tar_name, dst)
    @log.debug("untared #{tar_name} to #{dst}")
  end
  
end
