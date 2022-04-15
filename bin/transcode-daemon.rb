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
FileUtils.mkdir_p(BASE_DIR / 'queue')
FileUtils.mkdir_p(BASE_DIR / 'running')
FileUtils.mkdir_p(BASE_DIR / 'done')

def run_job(abs_path)
  start_time = Time.now
  pathname = Pathname.new(abs_path)
  puts pathname
  job_options = {}
  # Read the File contents
  pathname.open do |f|
    # JSON parse to hash
    text = f.read
    $logger.debug "text: #{text}"
    begin
      job_options = JSON.parse(text)
    rescue JSON::JSONError => e
      $logger.error e
    end
  end

  # TODO: Verify job structure
  # Needs
  #   'output'
  #   'input'
  #   'markers'
  #   'encoder'
  #   'title'

  # Check for errors

  begin
    # Move the file to the "/running" dir
    job_file = pathname.basename
    dest = BASE_DIR / 'running' / job_file
    $logger.debug "Moving from '#{pathname}' to '#{dest}'"
    FileUtils.mv pathname, dest

    transcode(job_options)

    finished = BASE_DIR / 'done' / job_file
    $logger.debug "Moving from '#{dest}' to '#{finished}'"
    FileUtils.mv dest, finished
  rescue => e
    # Move the job file to the failed dir
    $logger.error "Failed transcode of #{job_file}"
    faildir = BASE_DIR / 'failed' / job_file
    $logger.debug "Moving from '#{dest}' to '#{faildir}'"
    raise e
  end

  $logger.info "Completed: #{job_options['output']}"
  seconds = (Time.now - start_time).round
  hours   = seconds / (60 * 60)
  minutes = (seconds / 60) % 60
  seconds = seconds % 60
  $logger.info format("Elapsed time: %02d:%02d:%02d\n\n", hours, minutes, seconds)
end

def transcode(job_options)
  puts("Transcoding: #{job_options}")

  adjust_metadata(job_options['output'])
end

def adjust_metadata(output_filepath)
  puts("Adjusting metadata for #{output_filepath}")
end

listener = Listen.to(BASE_DIR / 'queue', only: /\.json$/) do |modified, added, _removed|
  # For each new file, run a job on it
  added.each do |path|
    run_job(path)
  end

  modified.each do |path|
    run_job(path)
  end

  # Ignore removed files
end

puts 'Starting watching for new job files'
listener.start
sleep
puts 'transcode job processor exiting'
