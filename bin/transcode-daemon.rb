#!/usr/bin/env ruby -W
#
# transcode-daemon

require 'listen'
require 'fileutils'
require 'json'
require 'pathname'
require 'logger'

$logger = Logger.new($stdout)
BASE_DIR = Pathname.new '/tmp/spool/ripper'
WORK_DIRS = {
  queue: BASE_DIR / 'queue',
  running: BASE_DIR / 'running',
  failed: BASE_DIR / 'failed',
  succeeded: BASE_DIR / 'succeeded'
}

# Make sure the dirs exist
WORK_DIRS.each_value do |dir|
  FileUtils.mkdir_p dir
end

class TranscodeJobError < RuntimeError
end

def read_job_options(pathname)
  # the options for running the transcode job, specified by the JSON file
  job_options = {}
  # Read the File contents
  pathname.open do |f|
    # JSON parse to hash
    text = f.read
    $logger.debug "JSON file text:\n#{text}"
    begin
      job_options = JSON.parse(text)
    rescue JSON::JSONError
      $logger.error "Failed to parse JSON job file '#{pathname}'."
      $logger.debug "Moving job file to '#{WORK_DIRS[:failed]}'"
      FileUtils.mv pathname, WORK_DIRS[:failed]
      raise
    end
  end
end

def move_to(src_file, dest_dir)
  name = src_file.basename
  dest_file = dest_dir / name
  $logger.debug "Moving from '#{src_file}' to '#{dest_file}'"
  FileUtils.mv src_file, dest_file
  dest_file
end

def run_job(abs_path)
  start_time = Time.now
  pathname = Pathname.new(abs_path)
  $logger.debug "Starting job '#{pathname}'"

  job_options = read_job_options(pathname)

  # TODO: Verify job structure
  # Needs
  #   'output'
  #   'input'
  #   'markers'
  #   'encoder'
  #   'title'

  # Check for errors

  running = move_to(pathname, WORK_DIRS[:running])

  begin
    transcode(job_options)

    move_to(running, WORK_DIRS[:succeeded])
  rescue StandardError
    # Move the job file to the failed dir
    $logger.error "Failed transcode of #{job_file}"
    move_to(running, WORK_DIRS[:failed])
    raise
  end

  $logger.info "Completed: #{job_options['output']}"
  seconds = (Time.now - start_time).round
  hours   = seconds / (60 * 60)
  minutes = (seconds / 60) % 60
  seconds = seconds % 60
  $logger.info format("Elapsed time: %02d:%02d:%02d\n\n", hours, minutes, seconds)
end

def transcode(job_options)
  $logger.info "Transcoding: #{job_options['input']}"

  adjust_metadata(job_options['output'])
end

def adjust_metadata(output_filepath)
  $logger.info "Adjusting metadata for #{output_filepath}"
end

listener = Listen.to(WORK_DIRS[:queue], only: /\.json$/) do |modified, added, _removed|
  # For each new file, run a job on it
  added.each do |path|
    run_job(path)
  rescue RuntimeError
  end

  modified.each do |path|
    run_job(path)
  rescue RuntimeError
  end
end

$logger.info "Starting watching for new job files in '#{WORK_DIRS[:queue]}'"
listener.start

sleep

$logger.info 'Transcode job processor exiting'
