#!/usr/bin/env -S ruby -W
# transcode-daemon

$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__) + '/../lib')

require 'listen'
require 'fileutils'
require 'json'
require 'pathname'
require 'logger'
require 'optparse'
require 'video_transcoding/transcode'

module VideoTranscoding
  # Contains a logger and a queue used for running the transcode daemon
  class TranscodeDaemon
    class TranscodeJobError < RuntimeError
    end

    def initialize
      update_work_dirs(Pathname.new('/tmp/spool/ripper'))
      @logger = Logger.new($stdout, level: Logger::INFO)
      @queue = Queue.new
    end

    def update_work_dirs(base)
      @work_dirs = {
        queue: base / 'queue',
        running: base / 'running',
        failed: base / 'failed',
        succeeded: base / 'succeeded'
      }
    end

    def read_job_options(pathname)
      # the options for running the transcode job, specified by the JSON file
      job_options = {}
      # Read the File contents
      pathname.open do |f|
        # JSON parse to hash
        text = f.read
        @logger.debug "JSON file text:\n#{text}"
        begin
          job_options = JSON.parse(text)
        rescue JSON::JSONError
          @logger.error "Failed to parse JSON job file '#{pathname}'."
          move_job_file(pathname, @work_dirs[:failed])
          raise TranscodeJobError, "Failed to parse JSON job file '#{pathname}'."
        end
      end

      job_options
    end

    def verify_options(job_options)
      ['output', 'input', 'markers', 'encoder', 'title'].each do |key|
        raise TranscodeJobError, "Required option '#{key}' not specified in JSON job" unless job_options.key?(key)
      end
    end

    def move_job_file(src_file, dest_dir)
      name = src_file.basename
      dest_file = dest_dir / name
      @logger.debug "Moving from '#{src_file}' to '#{dest_file}'"
      FileUtils.mv src_file, dest_file
      dest_file
    end

    def run_job(abs_path)
      start_time = Time.now
      pathname = Pathname.new(abs_path)
      current_file = pathname

      unless pathname.exist?
        @logger.warn "Job file no longer exists: '#{pathname}' (Maybe it was already done?)"
        return
      end

      @logger.info "Starting job '#{pathname}'"

      begin
        job_options = read_job_options(pathname)
        verify_options(job_options)
        current_file = move_job_file(current_file, @work_dirs[:running])
        transcode(job_options)
      rescue RuntimeError => e
        @logger.error "Failed transcode of #{pathname}: " + e.message

        move_job_file(current_file, @work_dirs[:failed])
      else
        move_job_file(current_file, @work_dirs[:succeeded])
        @logger.info "Completed job: #{job_options['output']}"
        seconds = (Time.now - start_time).round
        hours   = seconds / (60 * 60)
        minutes = (seconds / 60) % 60
        seconds = seconds % 60
        @logger.info format("Elapsed time: %02d:%02d:%02d\n\n", hours, minutes, seconds)
      end
    end

    def transcode(job_options)
      @logger.info "Transcoding: #{job_options['input']}"
      VideoTranscoding.transcode(job_options)
      @logger.info "Finished transcoding: #{job_options['input']}"
    end

    def main
      OptionParser.new do |opts|
        opts.on('-b', '--base DIRECTORY',
                'Base directory for job directories (default /tmp/spool/ripper') do |base|
          update_work_dirs(Pathname.new(base))
        end
        opts.on('-v', '--verbose', 'Output verbosity') do |v|
          @logger.level = Logger::DEBUG if v
        end
      end.parse!

      # Make sure the dirs exist
      @work_dirs.each_value do |dir|
        FileUtils.mkdir_p dir
      end

      # Add existing files to the queue, so they don't get ignored
      Dir.glob('*.json', base: @work_dirs[:queue]) { |job| @queue.push @work_dirs[:queue] / job }

      # Create a file watcher for the queue directory.
      # This will watch for new or modified *.json files in the queue
      listener = Listen.to(@work_dirs[:queue], only: /\.json$/) do |modified, added, _removed|
        # For each new file, run a job on it
        added.each do |path|
          @queue.push path
        end

        modified.each do |path|
          @queue.push path
        end
      end

      job_runner = Thread.new do
        while (job = @queue.pop)
          run_job(job)
        end
      end

      @logger.info "Starting watching for new job files in '#{@work_dirs[:queue]}'"
      listener.start

      sleep

      @logger.info 'Transcode job processor exiting'
      listener.stop
      @queue.close
      job_runner.join
    end
  end
end

VideoTranscoding::TranscodeDaemon.new.main
