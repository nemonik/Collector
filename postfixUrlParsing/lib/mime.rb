# To change this template, choose Tools | Templates
# and open the template in the editor.

module Mime
  # Determine the mimetype of the file
  def mime_shared_info(file_name)
    #Name              : Sample.doc
    #Type              : Regular
    #MIME type         : application/msword
    #Default app       : openoffice.org-writer.desktop

    info = []

    IO.popen("gnomevfs-info \"#{file_name}\"") { |stdout|

      if (out = stdout.read)
        out.split(/\n/).each {|line|
          pair = line.split(':')
          name = pair[0].strip!;
          if ('MIME type, Default app'.include?(name))
            info.push(pair[1].strip!)
            break if name == 'Default app'
          end
        }
      end
    }

    return info
  end
end
