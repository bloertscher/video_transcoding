require 'video_transcoding'

module VideoTranscoding
  # @param handbrake_options [Hash] CLI options for HandBrake
  # @param dry_run [bool] Whether to perform a dry run
  # @param log_on [bool] Whether to log to a file or not
  def self.transcode(handbrake_options, dry_run: false, log_on: true)
    handbrake_command = prepare_command(handbrake_options, dry_run)
    if dry_run
      puts handbrake_command.join(' ')
      return
    end

    Console.debug handbrake_command.inspect
    log_file_path = handbrake_options['output'] + '.log'
    log_file = log_on ? File.new(log_file_path, 'wb') : nil
    Console.info 'Transcoding with HandBrakeCLI...'

    begin
      IO.popen(handbrake_command, 'rb', :err => [:child, :out]) do |io|
        Signal.trap 'INT' do
          Process.kill 'INT', io.pid
        end

        buffer = ''

        io.each_char do |char|
          if (char.bytes[0] & 0x80) != 0
            buffer << char
          else
            if not buffer.empty?
              print buffer
              buffer = ''
            end

            print char
          end

          log_file.print char unless log_file.nil?
        end

        if not buffer.empty?
          print buffer
        end
      end
    rescue SystemCallError => e
      raise "transcoding failed: #{e}"
    end

    log_file.close unless log_file.nil?
    fail "transcoding failed: #{handbrake_options['input']}" unless $CHILD_STATUS.exitstatus == 0

    unless log_file.nil?
      timestamp = File.mtime(log_file_path)
      content = ''

      begin
        File.foreach(log_file_path) do |line|
          content += line
        end
      rescue SystemCallError => e
        raise "reading failed: #{e}"
      end

      log_file = File.new(log_file_path, 'wb')
      log_file.print content.gsub(/^.*\r(.)/, '\1')
      log_file.close
      FileUtils.touch log_file_path, :mtime => timestamp
    end

    adjust_metadata(handbrake_options['output']) unless dry_run
  end

  def self.adjust_metadata(output)
    media = Media.new(path: output, allow_directory: false)
    Console.debug media.info.inspect

    if  media.info[:mkv] and
        media.info[:subtitle].include? 1 and
        media.info[:subtitle][1][:default] and
        not media.info[:subtitle][1][:forced]
      Console.info 'Forcing subtitle with mkvpropedit...'

      begin
        IO.popen([
                   MKVpropedit.command_name,
                   '--edit', 'track:s1',
                   '--set', 'flag-forced=1',
                   output,
                 ], 'rb', :err => [:child, :out]) do |io|
          io.each do |line|
            Console.debug line
          end
        end
      rescue SystemCallError => e
        raise "forcing subtitle failed: #{e}"
      end

      fail "forcing subtitle: #{output}" if $CHILD_STATUS.exitstatus == 2
    end
  end

  # Prepares the actual HandBrakeCLI command, with all the options
  #
  # @param handbrake_options [Hash] CLI options for HandBrake
  # @param dry_run [bool] If true, makes sure to shell escape args
  def self.prepare_command(handbrake_options, dry_run)
    handbrake_command = [HandBrake.command_name]

    Console.debug handbrake_options
    handbrake_options.each do |name, value|
      if value.nil?
        handbrake_command << "--#{name}"
      elsif dry_run and name != 'encopts'
        # Don't need to shellescape encopts I guess
        handbrake_command << "--#{name}=#{value.shellescape}"
      else
        handbrake_command << "--#{name}=#{value}"
      end
    end

    return handbrake_command
  end
end
