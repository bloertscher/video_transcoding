#!/usr/bin/env ruby -W
#
# transcode-daemon

require 'listen'
require 'fileutils'
require 'json'
require 'pathname'
require 'logger'
require 'video_transcoding/transcode'

module VideoTranscoding
  module TranscodeDaemon
    class TranscodeJobError < RuntimeError
    end

    BASE_DIR = Pathname.new '/tmp/spool/ripper'
    WORK_DIRS = {
      queue: BASE_DIR / 'queue',
      running: BASE_DIR / 'running',
      failed: BASE_DIR / 'failed',
      succeeded: BASE_DIR / 'succeeded'
    }.freeze

    def initialize
      @logger = Logger.new($stdout)
      @queue = Queue.new
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
          @logger.debug "Moving job file to '#{WORK_DIRS[:failed]}'"
          FileUtils.mv pathname, WORK_DIRS[:failed]
          raise TranscodeJobError, "Failed to parse JSON job file '#{pathname}'."
        end
      end
    end

    def verify_options(job_options)
      ["output", "input", "markers", "encoder", "title"].each do |key|
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
      @logger.info "Starting job '#{pathname}'"

      begin
        job_options = read_job_options(pathname)
        verify_options(job_options)
        current_file = move_job_file(current_file, WORK_DIRS[:running])
        transcode(job_options)
      rescue RuntimeError => e
        @logger.error "Failed transcode of #{pathname}: " + e.message

        move_job_file(current_file, WORK_DIRS[:failed])
      else
        move_job_file(current_file, WORK_DIRS[:succeeded])
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

      adjust_metadata(job_options['output'])
    end

    def adjust_metadata(output_filepath)
      @logger.info "Adjusting metadata for #{output_filepath}"
    end

    def main()
      # Make sure the dirs exist
      WORK_DIRS.each_value do |dir|
        FileUtils.mkdir_p dir
      end
      # Add existing files to the queue, so they don't get ignored
      Dir.glob("*.json", base: WORK_DIRS[:queue]) { |job| @queue.push WORK_DIRS[:queue] / job }

      listener = Listen.to(WORK_DIRS[:queue], only: /\.json$/) do |modified, added, _removed|
        # For each new file, run a job on it
        added.each do |path|
          @queue.push path
        end

        modified.each do |path|
          @queue.push path
        end
      end

      job_runner = Thread.new do
        while job = @queue.pop
          run_job(job)
        end
      end

      @logger.info "Starting watching for new job files in '#{WORK_DIRS[:queue]}'"
      listener.start

      sleep

      @logger.info 'Transcode job processor exiting'
      listener.stop
      @queue.close
      job_runner.join
    end
  end
end

VideoTranscoding::TranscodeDaemon.main
