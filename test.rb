$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__) + '/lib')

require 'video_transcoding'
require 'pp'

m = VideoTranscoding::Media.new(path: ARGV[0])

#pp m.info
puts m.info

mapped = VideoTranscoding::Media.language_code('per')
puts mapped
