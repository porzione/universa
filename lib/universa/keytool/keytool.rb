require 'optparse'
require 'ostruct'
require 'ansi/code'
require 'universa/tools'

include Universa

class MessageException < Exception;
end

def error message
  raise MessageException, message
end

using Universa

def seconds_to_hms seconds
  mm, ss = seconds.divmod(60)
  hh, mm = mm.divmod(60)
  "%d:%02d:%02d" % [hh, mm, ss]
end

class KeyTool

  def initialize
    @require_password = true
    @autogenerate_password = false
    @tasks = []
    init_parser()
  end

  def task &block
    @tasks << block
  end

  def session_password
    @require_password or return nil
    @session_password ||= begin
      if @autogenerate_password
        psw = 29.random_alnums
        puts "Autogenerated password: #{ANSI.bold {psw}}"
        psw
      else
        puts "\nPlease enter password for key to be generated"
        psw1 = STDIN.noecho(&:gets).chomp
        puts "Please re-enter the password"
        psw2 = STDIN.noecho(&:gets).chomp
        psw1 == psw2 or error "passwords do not match"
        psw1.length < 8 and error "password is too short"
        psw1
      end
    end
  end

  def output_file(extension = nil)
    name = @output_file or error "specify ouput file with -o / --output"
    extension && !name.end_with?(extension) ? "#{name}#{extension}" : name
  end

  def init_parser
    opt_parser = OptionParser.new {|opts|
      opts.banner = "Universa Key tool #{Universa::VERSION}"
      opts.separator ""

      # opts.on("-k", "--key KEY_FILE",
      #         "load the access key from the specified file. By default, looks in", "#{options.key_path}") do |file_name|
      #   options.key_path = File.expand_path(file_name)
      # end
      #
      # opts.on("-n", "--node name", "node to connect, without protocol, e.g. 'node-7-com.universa.io'") do |node|
      #   options.node = node
      # end
      #
      opts.on("--[no-]password", "require password from console on subsequent operations (default: require)") {|x|
        @require_password = x
      }

      opts.on("-a", "--[no-]autogenerate_password") {|x|
        @autogenerate_password = x
      }

      opts.on("-o FILE", "--output FILE", "file name for the output file") {|f|
        @output_file = f
      }

      opts.on("-F", "force overwrite file") {
        @overwrite = true
      }

      opts.on("-g SIZE", "--generate SIZE", "generate new private key of the specified bis size") {|s|
        strength = s.to_i
        case strength
          when 2048, 4096
            task {
              # check we have all to generate...
              output = output_file(".private.unikey")
              error "File #{output} already exists"if File.exists?(output) && !@overwrite
              key = PrivateKey.new(strength)
              open(output, 'wb') {|f|
                f << if @require_password
                       key.pack_with_password(session_password)
                     else
                       key.pack()
                     end
              }
              puts "\nNew private key is generated: #{output}"
            }
          else
            error "Only supported key sizes are 2048, 4096"
        end
      }

      opts.on("--show FILE", "show key information") {|name|
        task {
          packed = open(name, 'rb') {|f| f.read} rescue error("can't read file: #{name}")
          key = begin
            PrivateKey.from_packed(packed)
          rescue Exception => e
            if e.message.include?('PasswordProtectedException')
              puts "\nThe key is password-protected"
              while (true)
                puts "enter password for #{name}:"
                password = STDIN.noecho(&:gets).chomp
                key = PrivateKey.from_packed(packed, password: password) rescue nil
                key and break key
              end
            end
          end
          puts "\n------------------------------------------------------------------"
          puts "Private key, #{key.info.getKeyLength()*8} bits\n"
          puts "Short address : #{ANSI.bold{key.short_address.to_s}}"
          puts "Long  address : #{ANSI.bold{key.long_address.to_s}}"
        }
      }

      opts.separator ""

      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end

      opts.on_tail("-v", "--version", "Show versions") do
        puts "Universa core version: #{Service.umi.core_version}"
        puts "UMI version          : #{Service.umi.version}"
        client = Universa::Client.new
        puts "Connected nodes      : #{client.size}"
        exit
      end
    }

    ## D_TIsYOfFQ2WejhG3
    begin
      opt_parser.order!
      @tasks.each {|t| t.call}
    rescue MessageException, OptionParser::ParseError => e
      STDERR.puts ANSI.red {ANSI.bold {"\nError: #{e}\n"}}
      exit(1000)
    rescue Interrupt
      exit(1010)
    rescue
      STDERR.puts ANSI.red {"\n#{$!.backtrace.reverse.join("\n")}\n"}
      STDERR.puts ANSI.red {ANSI.bold {"Error: #$! (#{$!.class.name})"}}
      exit(2000)
    end
  end
end

KeyTool.new()
