hb_out = ""
IO.popen([
  "HandBrakeCLI",
  "--title=0",
  "--scan",
  "--input=#{ARGV[0]}"
], :err=>[:child, :out]) do |io|
  hb_out = io.readlines.filter { |line| line.match(/^\s*\+ (?!(autocrop|support))/) }.join("")

end
     
puts hb_out
