require 'fileutils'
require 'tmpdir'
require 'json'
require 'video_transcoding/cli'

module VideoTranscoding
  class Command
    include CLI

    MAX_WIDTH   = 4096
    MAX_HEIGHT  = 2304

    def about
      <<-HERE
transcode-video #{VERSION}
#{COPYRIGHT}
HERE
    end

    def usage
      <<-HERE
Transcode video file or disc image directory into format and size similar to
popular online downloads. Works best with Blu-ray or DVD rip.

Automatically determines target video bitrate, number of audio tracks, etc.
WITHOUT ANY command line options.

Usage: #{$PROGRAM_NAME} [OPTION]... [FILE|DIRECTORY]...

Input options:
    --scan          list title(s) and tracks in video media and exit
    --title INDEX   select indexed title in video media
                      (default: main feature or first listed)
    --chapters CHAPTER[-CHAPTER]
                    select chapters, single or range (default: all)

Output options:
-o, --output FILENAME|DIRECTORY
                    set output path and filename, or just path
                      (default: input filename with output format extension
                        in current working directory)
    --mp4           output MP4 instead of Matroska `.mkv` format
    --m4v             "     "  with `.m4v` extension instead of `.mp4`
    --chapter-names FILENAME
                    import chapter names from `.csv` text file
                      (in NUMBER,NAME format, e.g. "1,Intro")
    --no-log        don't write log file
-n, --dry-run       don't transcode, just show `HandBrakeCLI` command and exit

Quality options:
    --encoder NAME  use named video encoder (default: x264)
                      (refer to `HandBrakeCLI --help` for available encoders)
    --abr           use constrained average bitrate (ABR) ratecontrol
                      (predictable size with different quality than default)
    --simple        use simple constrained ratecontrol
                      (limited size with different quality than default)
    --avbr          use average variable bitrate (AVBR) ratecontrol
                      (size near target with different quality than default)
                      (only available with x264 and x264_10bit encoders)
    --target big|small
                    apply video bitrate target macro for all input resolutions
                      (`big` trades some size for increased quality)
                      (`small` trades some quality for reduced size)
    --target [2160p=|1080p=|720p=|480p=]BITRATE
                    set video bitrate target (default: based on input)
                      or target for specific input resolution
                      (can be exceeded to maintain video quality)
                      (can be used multiple times)
    --quick         increase encoding speed by 70-80%
                      with no easily perceptible loss in video quality
                      (avoids quality problems with some encoder presets)
    --veryquick     increase encoding speed by 90-125%
                      with little easily perceptible loss in video quality
                      (unlike `--quick`, output size is larger than default)
    --preset veryfast|faster|fast|slow|slower|veryslow
                    apply video encoder preset

Video options:
    --crop T:B:L:R  set video crop values (default: 0:0:0:0)
                      (use `--crop detect` for `detect-crop` behavior)
                      (use `--crop auto` for `HandBrakeCLI` behavior)
    --constrain-crop
                    constrain `--crop detect` to optimal shape
    --fallback-crop handbrake|ffmpeg|minimal|none
                    select fallback crop values if `--crop detect` fails
                      (`minimal` uses the smallest possible crop values
                        combining results from `HandBrakeCLI` and `ffmpeg`)
    --720p          fit video within 1280x720 pixel bounds
    --max-width WIDTH, --max-height HEIGHT
                    fit video within horizontal and/or vertical pixel bounds
    --pixel-aspect X:Y
                    set pixel aspect ratio (default: 1:1)
                      (e.g.: make X larger than Y to stretch horizontally)
    --force-rate FPS
                    force constant video frame rate
                      (`23.976` applied automatically for some inputs)
    --limit-rate FPS
                    set peak-limited video frame rate
    --filter NAME[=SETTINGS]
                    apply `HandBrakeCLI` video filter with optional settings
                      (`deinterlace` applied automatically for some inputs)
                      (refer to `HandBrakeCLI --help` for more information)
                      (can be used multiple times)

Audio options:
    --main-audio TRACK[=NAME]|LANGUAGE[=NAME]
                    select main track by number or first with language code
                      assigning it an optional name
                      (default: first track, i.e. 1)
                      (language code must be ISO 639-2 format, e.g.: `eng`)
                      (default output can be two audio tracks,
                        both surround and stereo, i.e. width is `double`)
    --add-audio TRACK[=NAME]|LANGUAGE[,LANGUAGE,...]|all
                    add track selected by number assigning it an optional name
                      or add tracks selected with one or more language codes
                      or add all tracks
                      (language code must be ISO 639-2 format, e.g.: `eng`)
                      (multiple languages are separated by commas)
                      (default output is single AAC audio track,
                        i.e. width is `stereo`)
                      (can be used multiple times)
    --audio-width TRACK|main|other|all=double|surround|stereo
                    set audio output width for specific track by number
                      or main track or other non-main tracks or all tracks
                      with `double` to allow room for two output tracks
                      with `surround` to allow single surround or stereo track
                      with `stereo` to allow only single stereo track
                      (can be used multiple times)
    --reverse-double-order
                    reverse order of `double` width audio output tracks
    --audio-format surround|stereo|all=ac3|aac
                    set audio format for specific or all output tracks
                      (default for surround: ac3; default for stereo: aac)
    --keep-ac3-stereo
                    copy rather than transcode AC-3 stereo or mono audio tracks
                      even when the current stereo format is AAC
    --ac3-encoder ac3|eac3
                    set AC-3 audio encoder (default: ac3)
    --ac3-bitrate 384|448|640|768|1536
                    set AC-3 surround audio bitrate (default: 640)
    --pass-ac3-bitrate 384|448|640|768|1536
                    set AC-3 surround pass-through bitrate (default: 640)
    --copy-audio TRACK|all
                    try to copy track selected by number in its original format
                      falling back to surround format if original not allowed
                      or try to copy all tracks in same manner
                      (only applies to main and explicitly added audio tracks)
                      (can be used multiple times)
    --copy-audio-name TRACK|all
                    copy original track name selected by number
                      unless the name is specified with another option
                      or try to copy all track names in same manner
                      (only applies to main and explicitly added audio tracks)
                      (can be used multiple times)
    --aac-encoder NAME
                    use named AAC audio encoder (default: platform dependent)
    --mixdown stereo|dpl2
                    set mixdown for stereo audio output tracks
                      to regular stereo or Dolby Pro Logic II format
                      (default: stereo)
    --no-audio      disable all audio output

Subtitle options:
    --burn-subtitle TRACK|scan
                    burn track selected by number into video
                      or `scan` to find forced track in main audio language
    --force-subtitle TRACK|scan
                    add track selected by number and set forced flag
                      or scan for forced track in same language as main audio
    --add-subtitle TRACK|LANGUAGE[,LANGUAGE,...]|all
                    add track selected by number
                      or add tracks selected with one or more language codes
                      or add all tracks
                      (language code must be ISO 639-2 format, e.g.: `eng`)
                      (multiple languages are separated by commas)
                      (can be used multiple times)
    --no-auto-burn  don't automatically burn first forced subtitle

External subtitle options:
    --burn-srt FILENAME
                    burn SubRip-format text file into video
    --force-srt FILENAME
                    add subtitle track from SubRip-format text file
                      and set forced flag
    --add-srt FILENAME
                    add subtitle track from SubRip-format text file
                      (can be used multiple times)
    --bind-srt-language CODE
                    bind ISO 639-2 language code (default: und)
                      to previously forced or added subtitle
                      (can be used multiple times)
    --bind-srt-encoding FORMAT
                    bind character set encoding (default: latin1)
                      to previously burned, forced or added subtitle
                      (can be used multiple times)
    --bind-srt-offset MILLISECONDS
                    bind +/- offset in milliseconds (default: 0)
                      to previously burned, forced or added subtitle
                      (can be used multiple times)

Advanced options:
-E, --encoder-option NAME=VALUE|_NAME
                    pass video encoder option by name with value
                      or disable use of option by prefixing name with "_"
                      (e.g.: `-E vbv-bufsize=8000`)
                      (e.g.: `-E _crf-max`)
                      (can be used multiple times)
-H, --handbrake-option NAME[=VALUE]|_NAME
                    pass `HandBrakeCLI` option by name or by name with value
                      or disable use of option by prefixing name with "_"
                      (e.g.: `-H stop-at=duration:30`)
                      (e.g.: `-H _markers`)
                      (refer to `HandBrakeCLI --help` for more information)
                      (some options are not allowed)
                      (can be used multiple times)

Diagnostic options:
-v, --verbose       increase diagnostic information
-q, --quiet         decrease     "           "

Other options:
-h, --help          display this help and exit
    --version       output version information and exit

Requires `HandBrakeCLI`, `mp4track`, `ffmpeg` and `mkvpropedit`.
HERE
    end

    def initialize
      super
      @scan                       = false
      @title                      = nil
      @output                     = nil
      @format                     = :mkv
      @log                        = true
      @dry_run                    = false
      @ratecontrol                = :special
      @target_bitrate_2160p       = 12000
      @target_bitrate_1080p       = 6000
      @target_bitrate_720p        = 3000
      @target_bitrate_480p        = 1500
      @quick                      = false
      @veryquick                  = false
      @crop                       = {:top => 0, :bottom => 0, :left => 0, :right => 0}
      @constrain_crop             = false
      @fallback_crop              = nil
      @target_bitrate             = nil
      @main_audio                 = nil
      @main_audio_language        = nil
      @extra_audio                = []
      @audio_name                 = {}
      @audio_language             = []
      @audio_width                = {:main => :double, :other => :stereo}
      @reverse_double_order       = false
      @surround_format            = 'ac3'
      @stereo_format              = 'aac'
      @keep_ac3_stereo            = false
      @ac3_encoder                = 'ac3'
      @ac3_bitrate                = 640
      @pass_ac3_bitrate           = 640
      @copy_audio                 = []
      @copy_audio_name            = []
      @aac_encoder                = nil
      @mixdown                    = 'stereo'
      @burn_subtitle              = nil
      @force_subtitle             = nil
      @extra_subtitle             = []
      @subtitle_language          = []
      @auto_burn                  = true
      @burn_srt                   = nil
      @force_srt                  = nil
      @srt_file                   = []
      @srt_language               = {}
      @srt_encoding               = {}
      @srt_offset                 = {}
      @encoder_options            = {}
      @disable_encoder_options    = []
      @handbrake_options          = {}
      @disable_handbrake_options  = []
      @temporary                  = nil
      @use_job_queue              = false
    end

    def define_options(opts)
      opts.on('--scan')               { @scan = true }
      opts.on('--title ARG', Integer) { |arg| @title = arg }

      opts.on '--chapters ARG' do |arg|
        unless arg =~ /^[1-9][0-9]*(?:-[1-9][0-9]*)?$/
          fail UsageError, "invalid chapters argument: #{arg}"
        end

        force_handbrake_option 'chapters', arg
      end

      opts.on '-o', '--output ARG' do |arg|
        unless File.directory? arg
          @format = case File.extname(arg)
          when '.mkv'
            :mkv
          when '.mp4'
            :mp4
          when '.m4v'
            :m4v
          else
            fail UsageError, "unsupported filename extension: #{arg}"
          end
        end

        @output = arg
      end

      opts.on '--mp4' do
        @output = filter_output_option(@output, '.mp4')
        @format = :mp4
      end

      opts.on '--m4v' do
        @output = filter_output_option(@output, '.m4v')
        @format = :m4v
      end

      opts.on '--chapter-names ARG' do |arg|
        fail "chapter names file does not exist: #{arg}" unless File.exist? arg
        force_handbrake_option 'markers', arg
      end

      opts.on('--no-log')             { @log = false }
      opts.on('-n', '--dry-run')      { @dry_run = true }

      opts.on '--encoder ARG' do |arg|
        force_handbrake_option 'encoder', arg
      end

      opts.on '--abr' do
        @ratecontrol = :abr
      end

      opts.on '--simple' do
        @ratecontrol = :simple
      end

      opts.on '--avbr' do
        @ratecontrol = :avbr
      end

      opts.on '--raw' do
        @ratecontrol = :raw
      end

      opts.on '--target ARG' do |arg|
        case arg
        when 'big'
          @target_bitrate_2160p = 16000
          @target_bitrate_1080p = 8000
          @target_bitrate_720p  = 4000
          @target_bitrate_480p  = 2000
        when 'small'
          @target_bitrate_2160p = 8000
          @target_bitrate_1080p = 4000
          @target_bitrate_720p  = 2000
          @target_bitrate_480p  = 1000
        when /^([0-9]+p)=([1-9][0-9]*)$/
          bitrate = $2.to_i

          case $1
          when '2160p'
            @target_bitrate_2160p = bitrate
          when '1080p'
            @target_bitrate_1080p = bitrate
          when '720p'
            @target_bitrate_720p = bitrate
          when '480p'
            @target_bitrate_480p = bitrate
          else
            fail UsageError, "invalid target video bitrate resolution: #{$1}"
          end

          @target_bitrate = nil
        else
          unless arg =~ /^[1-9][0-9]*$/
            fail UsageError, "invalid bitrate argument: #{arg}"
          end

          @target_bitrate = arg.to_i
        end
      end

      opts.on '--quick' do
        @quick = true
        @veryquick = false
        @handbrake_options.delete 'encoder'
        @handbrake_options.delete 'encoder-preset'
      end

      opts.on '--veryquick' do
        @veryquick = true
        @quick = false
        @handbrake_options.delete 'encoder'
        @handbrake_options.delete 'encoder-preset'
      end

      opts.on '--preset ARG' do |arg|
        case arg
        when 'ultrafast', 'superfast', 'veryfast', 'faster', 'fast', 'medium',
        'slow', 'slower', 'veryslow', 'placebo'
          force_handbrake_option 'encoder-preset', arg
        else
          fail UsageError, "unsupported preset name: #{arg}"
        end

        @quick = false
        @veryquick = false
      end

      opts.on '--crop ARG' do |arg|
        @crop = case arg
        when /^([0-9]+):([0-9]+):([0-9]+):([0-9]+)$/
          {:top => $1.to_i, :bottom => $2.to_i, :left => $3.to_i, :right => $4.to_i}
        when 'detect'
          :detect
        when 'auto'
          :auto
        else
          fail UsageError, "invalid crop values: #{arg}"
        end
      end

      opts.on '--constrain-crop' do
        @constrain_crop = true
      end

      opts.on '--fallback-crop ARG' do |arg|
        @fallback_crop = case arg
        when 'handbrake', 'ffmpeg', 'mplayer', 'minimal', 'none'
          arg.to_sym
        else
          fail UsageError, "invalid fallback crop argument: #{arg}"
        end
      end

      opts.on '--720p' do
        force_handbrake_option 'maxWidth', '1280'
        force_handbrake_option 'maxHeight', '720'
        @handbrake_options.delete 'width'
        @handbrake_options.delete 'height'
      end

      opts.on '--max-width ARG', Integer do |arg|
        fail UsageError, "invalid maximum width argument: #{arg}" if arg < 0 or arg > MAX_WIDTH
        force_handbrake_option 'maxWidth', arg.to_s
        @handbrake_options.delete 'width'
      end

      opts.on '--max-height ARG', Integer do |arg|
        fail UsageError, "invalid maximum height argument: #{arg}" if arg < 0 or arg > MAX_HEIGHT
        force_handbrake_option 'maxHeight', arg.to_s
        @handbrake_options.delete 'height'
      end

      opts.on '--pixel-aspect ARG' do |arg|
        if arg =~ /^[1-9][0-9]*:[1-9][0-9]*$/
          force_handbrake_option 'pixel-aspect', arg
          force_handbrake_option 'custom-anamorphic', nil
          @handbrake_options.delete 'display-width'
          @handbrake_options.delete 'non-anamorphic'
          @handbrake_options.delete 'auto-anamorphic'
          @handbrake_options.delete 'strict-anamorphic'
          @handbrake_options.delete 'loose-anamorphic'
        else
          fail UsageError, "invalid pixel aspect argument: #{arg}"
        end
      end

      opts.on '--force-rate ARG' do |arg|
        unless arg =~ /^[1-9][0-9]*(?:\.[0-9]+)?$/
          fail UsageError, "invalid force rate argument: #{arg}"
        end

        force_handbrake_option 'rate', arg
        force_handbrake_option 'cfr', nil
        @handbrake_options.delete 'vfr'
        @handbrake_options.delete 'pfr'
      end

      opts.on '--limit-rate ARG' do |arg|
        unless arg =~ /^[1-9][0-9]*(?:\.[0-9]+)?$/
          fail UsageError, "invalid limit rate argument: #{arg}"
        end

        force_handbrake_option 'rate', arg
        force_handbrake_option 'pfr', nil
        @handbrake_options.delete 'vfr'
        @handbrake_options.delete 'cfr'
      end

      opts.on '--filter ARG' do |arg|
        if arg =~ /^([a-z0-9-]+)(?:=(.+))?$/
          force_handbrake_option filter_handbrake_option($1), $2
        else
          fail UsageError, "invalid filter argument: #{arg}"
        end
      end

      opts.on '--main-audio ARG' do |arg|
        if arg =~ /^(?:([1-9][0-9]*)(?:=(.+))?|([a-z]{3})(?:=(.+))?)$/
          if $3.nil?
            track = $1.to_i
            @main_audio = track
            @audio_name[track] = $2 unless $2.nil?
            @main_audio_language = nil
          else
            @main_audio_language = $3
            @audio_name[:main] = $4 unless $4.nil?
            @main_audio = nil
          end
        else
          fail UsageError, "invalid main audio argument: #{arg}"
        end
      end

      opts.on '--add-audio ARG' do |arg|
        if arg =~ /^(?:([1-9][0-9]*)(?:=(.+))?|([a-z]{3}(?:,[a-z]{3})*))$/
          if $3.nil?
            track = $1.to_i
            @extra_audio << track unless @extra_audio.first.is_a? Symbol
            @audio_name[track] = $2 unless $2.nil?
          elsif $3 == 'all'
            @extra_audio = [:all]
            @audio_language = []
          elsif @extra_audio.first != :all
            @extra_audio = [:language]
            @audio_language = $3.split(',')
          end
        else
          fail UsageError, "invalid add audio argument: #{arg}"
        end
      end

      opts.on '--audio-width ARG' do |arg|
        if arg =~ /^([1-9][0-9]*|main|other|all)=(double|surround|stereo)$/
          width = $2.to_sym

          case $1
          when 'main'
            @audio_width[:main] = width
          when 'other'
            @audio_width[:other] = width
          when 'all'
            @audio_width[:main] = width
            @audio_width[:other] = width
          else
            @audio_width[$1.to_i] = width
          end
        else
          fail UsageError, "invalid audio width argument: #{arg}"
        end
      end

      opts.on('--reverse-double-order') { @reverse_double_order = true }

      opts.on '--audio-format ARG' do |arg|
        if arg =~ /^(surround|stereo|all)=(ac3|aac)$/
          case $1
          when 'surround'
            @surround_format = $2
          when 'stereo'
            @stereo_format = $2
          else
            @surround_format = $2
            @stereo_format = $2
          end
        else
          fail UsageError, "invalid audio format argument: #{arg}"
        end
      end

      opts.on '--keep-ac3-stereo' do
        @keep_ac3_stereo = true
      end

      opts.on '--prefer-ac3' do
        Console.warn '**********'
        Console.warn 'Using deprecated option: --prefer-ac3'
        Console.warn "Replace with: --audio-width all=surround --audio-format all=ac3"
        Console.warn '**********'
        @audio_width[:main] = :surround
        @audio_width[:other] = :surround
        @surround_format = 'ac3'
        @stereo_format = 'ac3'
      end

      opts.on '--ac3-encoder ARG' do |arg|
        @ac3_encoder = case arg
        when 'ac3', 'eac3'
          arg
        else
          fail UsageError, "invalid AC-3 audio encoder: #{arg}"
        end
      end

      opts.on '--ac3-bitrate ARG', Integer do |arg|
        @ac3_bitrate = case arg
        when 384, 448, 640, 768, 1536
          arg
        else
          fail UsageError, "unsupported AC-3 audio bitrate: #{arg}"
        end
      end

      opts.on '--pass-ac3-bitrate ARG', Integer do |arg|
        @pass_ac3_bitrate = case arg
        when 384, 448, 640, 768, 1536
          arg
        else
          fail UsageError, "unsupported AC-3 audio pass-through bitrate: #{arg}"
        end
      end

      opts.on '--copy-audio ARG' do |arg|
        if arg =~ /^[1-9][0-9]*|all$/
          if $MATCH == 'all'
            @copy_audio = [:all]
          else
            @copy_audio << $MATCH.to_i unless @copy_audio.first == :all
          end
        end
      end

      opts.on '--copy-audio-name ARG' do |arg|
        if arg =~ /^[1-9][0-9]*|all$/
          if $MATCH == 'all'
            @copy_audio_name = [:all]
          else
            @copy_audio_name << $MATCH.to_i unless @copy_audio_name.first == :all
          end
        end
      end

      opts.on '--aac-encoder ARG' do |arg|
        if arg =~/_aac$/
          @aac_encoder = arg
        else
          fail UsageError, "invalid aac encoder argument: #{arg}"
        end
      end

      opts.on '--mixdown ARG' do |arg|
        @mixdown = case arg
        when 'stereo', 'dpl2'
          arg
        else
          fail UsageError, "invalid mixdown: #{arg}"
        end
      end

      opts.on('--no-audio')           { force_handbrake_option 'audio', 'none' }

      opts.on '--burn-subtitle ARG' do |arg|
        if arg =~ /^[1-9][0-9]*|scan$/
          if $MATCH == 'scan'
            @burn_subtitle = :scan
          else
            track = $MATCH.to_i
            @burn_subtitle = track
            @extra_subtitle << track
          end

          @force_subtitle = nil
          @burn_srt = nil
          @force_srt = nil
          @auto_burn = false
        else
          fail UsageError, "invalid burn subtitle argument: #{arg}"
        end
      end

      opts.on '--force-subtitle ARG' do |arg|
        if arg =~ /^[1-9][0-9]*|scan$/
          if $MATCH == 'scan'
            @force_subtitle = :scan
          else
            track = $MATCH.to_i
            @force_subtitle = track
            @extra_subtitle << track
          end

          @burn_subtitle = nil
          @burn_srt = nil
          @force_srt = nil
          @auto_burn = false
        else
          fail UsageError, "invalid force subtitle argument: #{arg}"
        end
      end

      opts.on '--add-subtitle ARG' do |arg|
        if arg =~ /^(?:([1-9][0-9]*)|([a-z]{3}(?:,[a-z]{3})*))$/
          if $2.nil?
            @extra_subtitle << $1.to_i unless @extra_subtitle.first.is_a? Symbol
          elsif $2 == 'all'
            @extra_subtitle = [:all]
            @subtitle_language = []
          elsif @extra_subtitle.first != :all
            @extra_subtitle = [:language]
            @subtitle_language = $2.split(',')
          end
        else
          fail UsageError, "invalid add subtitle argument: #{arg}"
        end
      end

      opts.on('--no-auto-burn')       { @auto_burn = false }

      opts.on '--burn-srt ARG' do |arg|
        fail "subtitle file does not exist: #{arg}" unless File.exist? arg
        index = @srt_file.index(arg)

        if index.nil?
          @burn_srt = @srt_file.size
          @srt_file << arg
        else
          @burn_srt = index
        end

        @force_srt = nil
        @burn_subtitle = nil
        @force_subtitle = nil
        @auto_burn = false
      end

      opts.on '--force-srt ARG' do |arg|
        fail "subtitle file does not exist: #{arg}" unless File.exist? arg
        index = @srt_file.index(arg)

        if index.nil?
          @force_srt = @srt_file.size
          @srt_file << arg
        else
          @force_srt = index
        end

        @burn_srt = nil
        @burn_subtitle = nil
        @force_subtitle = nil
        @auto_burn = false
      end

      opts.on '--add-srt ARG' do |arg|
        fail "subtitle file does not exist: #{arg}" unless File.exist? arg
        @srt_file << arg unless @srt_file.include? arg
      end

      opts.on '--bind-srt-language ARG' do |arg|
        fail UsageError, "invalid subtitle language argument: #{arg}" unless arg =~ /^[a-z]{3}$/
        fail UsageError, "subtitle file missing for language: #{arg}" if @srt_file.empty?
        @srt_language[@srt_file.size - 1] = arg
      end

      opts.on '--bind-srt-encoding ARG' do |arg|
        fail UsageError, "subtitle file missing for encoding: #{arg}" if @srt_file.empty?
        @srt_encoding[@srt_file.size - 1] = arg
      end

      opts.on '--bind-srt-offset ARG', Integer do |arg|
        fail UsageError, "subtitle file missing for offset: #{arg}" if @srt_file.empty?
        @srt_offset[@srt_file.size - 1] = arg
      end

      opts.on '-E', '--encoder-option ARG' do |arg|
        if arg =~ /^([a-z0-9][a-z0-9_-]+)=([^ :]+)$/
          @encoder_options[$1] = $2
          @disable_encoder_options.delete $1
        elsif arg =~ /^_([a-z0-9][a-z0-9_-]+)$/
          @disable_encoder_options << $1
          @encoder_options.delete $1
        else
          fail UsageError, "invalid encoder option: #{arg}"
        end
      end

      opts.on '-H', '--handbrake-option ARG' do |arg|
        if arg =~ /^([a-zA-Z][a-zA-Z0-9-]+)(?:=(.+))?$/
          force_handbrake_option filter_handbrake_option($1), $2
        elsif arg =~ /^_([a-zA-Z][a-zA-Z0-9-]+)$/
          name = filter_handbrake_option($1)
          @disable_handbrake_options << name
          @handbrake_options.delete name
        else
          fail UsageError, "invalid HandBrakeCLI option: #{arg}"
        end
      end
    end

    def force_handbrake_option(name, value)
      @handbrake_options[name] = value
      @disable_handbrake_options.delete name
    end

    def filter_output_option(path, ext)
      if path.nil? or File.directory? path
        path
      else
        File.dirname(path) + File::SEPARATOR + File.basename(path, '.*') + ext
      end
    end

    def filter_handbrake_option(name)
      case name
      when 'help', 'update', /^preset/, 'queue-import-file', 'input',
      'title', 'scan', 'main-feature', 'previews', 'output', 'format',
      'encoder-preset-list', 'encoder-tune-list', 'encoder-profile-list',
      'encoder-level-list'
        fail UsageError, "unsupported HandBrakeCLI option name: #{name}"
      when 'qsv-preset', 'x264-preset', 'x265-preset'
        'encoder-preset'
      when 'x264-tune', 'x265-tune'
        'encoder-tune'
      when 'x264-profile', 'h264-profile', 'h265-profile'
        'encoder-profile'
      when 'h264-level', 'h265-level'
        'encoder-level'
      else
        name
      end
    end

    def configure
      @pass_ac3_bitrate = @ac3_bitrate if @pass_ac3_bitrate < @ac3_bitrate
      @extra_audio.uniq!
      @copy_audio.uniq!
      @copy_audio_name.uniq!
      @extra_subtitle.uniq!
      @disable_encoder_options.uniq!
      @disable_handbrake_options.uniq!
      HandBrake.setup
      MP4track.setup
      FFmpeg.setup
      MKVpropedit.setup
    end

    def process_input(arg)
      Console.info "Processing: #{arg}..."

      if @scan
        media = Media.new(path: arg, title: @title)
        Console.debug media.info.inspect
        puts media.summary
        return
      end

      seconds = Time.now.tv_sec
      media = Media.new(path: arg, title: @title, autocrop: @crop == :detect)
      Console.debug media.info.inspect
      handbrake_options = {
        'input' => arg,
        'output' => resolve_output(media),
        'markers' => nil,
        'encoder' => 'x264'
      }
      title = media.info[:title]
      handbrake_options['title'] = title.to_s unless title == 1
      encoder_options = {}
      prepare_video(media, handbrake_options, encoder_options)
      prepare_audio(media, handbrake_options)
      prepare_subtitle(media, handbrake_options)
      prepare_srt(media, handbrake_options)
      prepare_options(handbrake_options, encoder_options)
      return if @dry_run

      if @use_job_queue
        # If running a separate daemon,
        # add the command to the queue of jobs
        # /var/spool/ripper/queue/*.json
        File.open("/var/spool/ripper/queue/#{handbrake_options['output']}.json", 'w') do |f|
          f.write(handbrake_options.to_json)
        end
        return
      end

      ### TODO From here until....
      # Create the HandBrakeCLI command from the options
      transcode(handbrake_options)
      adjust_metadata(handbrake_options['output'])

      unless @dry_run
        puts "Completed: #{handbrake_options['output']}"
        seconds = Time.now.tv_sec - seconds
        hours   = seconds / (60 * 60)
        minutes = (seconds / 60) % 60
        seconds = seconds % 60
        printf "Elapsed time: %02d:%02d:%02d\n\n", hours, minutes, seconds
      end
      ### .... Here run this as a background daemon
    end

    def resolve_output(media)
      output = File.basename(media.path, '.*') + '.' + @format.to_s

      unless @output.nil?
        path = File.absolute_path(@output)

        if File.directory? @output
          output = path + File::SEPARATOR + output
        else
          output = path
        end
      end

      fail "output file exists: #{output}" if File.exist? output
      output
    end

    def prepare_video(media, handbrake_options, encoder_options)
      crop = resolve_crop(media)
      width, height = media.info[:width], media.info[:height]

      unless crop.nil?
        handbrake_options['crop'] = Crop.handbrake_string(crop)
        width -= crop[:left] + crop[:right]
        height -= crop[:top] + crop[:bottom]

        unless width > 0 and height > 0
          fail UsageError, "invalid crop values: #{Crop.handbrake_string(crop)}"
        end
      end

      width       = @handbrake_options.fetch('width', width).to_i
      height      = @handbrake_options.fetch('height', height).to_i
      max_width   = @handbrake_options.fetch('maxWidth', MAX_WIDTH).to_i
      max_height  = @handbrake_options.fetch('maxHeight', MAX_HEIGHT).to_i

      if width > max_width or height > max_height
        anamorphic = 'loose-anamorphic'
        adjusted_height = (height * (max_width.to_f / width)).to_i
        adjusted_height -= 1 if adjusted_height.odd?

        if adjusted_height > max_height
          width = (width * (max_height.to_f / height)).to_i
          width -= 1 if width.odd?
          height = max_height
        else
          width = max_width
          height = adjusted_height
        end
      else
        anamorphic = 'auto-anamorphic'
      end

      handbrake_options[anamorphic] = nil unless @handbrake_options.has_key? 'custom-anamorphic'

      unless @handbrake_options.has_key? 'rate'
        rate = nil
        fps = media.info[:fps]

        if fps == 29.97
          if media.info[:mpeg2]
            rate = '23.976'
          else
            unless  @handbrake_options.has_key? 'deinterlace' or
                    @handbrake_options.has_key? 'decomb' or
                    @handbrake_options.has_key? 'detelecine'
              handbrake_options['deinterlace'] = nil
            end
          end
        elsif media.info[:mpeg2]
          case fps
          when 23.976, 24.0, 25.0
            rate = fps.to_s
          end
        end

        unless rate.nil?
          handbrake_options['rate'] = rate
          handbrake_options['cfr'] = nil
        end
      end

      if width > 1920 or height > 1080
        encoder_level = '5.1'
        bitrate = @target_bitrate_2160p
      elsif width > 1280 or height > 720
        encoder_level = '4.0'
        bitrate = @target_bitrate_1080p
      elsif width * height > 720 * 576
        encoder_level = '3.1'
        bitrate = @target_bitrate_720p
      else
        encoder_level = '3.0'
        bitrate = @target_bitrate_480p
      end

      if @target_bitrate.nil?
        unless media.info[:directory]
          media_bitrate = ((((media.info[:size] * 8) / media.info[:duration]) / 1000) / 1000) * 1000

          if media_bitrate < bitrate
            min_bitrate = bitrate / 2

            if media_bitrate < min_bitrate
              bitrate = min_bitrate
            else
              bitrate = media_bitrate
            end
          end
        end
      else
        bitrate = @target_bitrate
      end

      encoder = @handbrake_options.fetch('encoder', 'x264')

      if encoder =~ /_h26[45]$/ and not @handbrake_options.has_key? 'quality'
        handbrake_options['vb'] = bitrate.to_s
      end

      return unless encoder =~ /^x264(?:_10bit)?$/ or encoder =~ /^x265(?:_1[02]bit)?$/

      case encoder
      when 'x264'
        handbrake_options['encoder-profile'] = 'high'
      when 'x264_10bit'
        handbrake_options['encoder-profile'] = 'high10'
      when 'x265'
        handbrake_options['encoder-profile'] = 'main'
      when 'x265_10bit', 'x265_12bit'
        handbrake_options['encoder-profile'] = 'main10'
      end

      if encoder =~ /^x264(?:_10bit)?$/ and @handbrake_options.fetch('rate', '30').to_f <= 30.0
          handbrake_options['encoder-level'] = encoder_level
      end

      signal_hrd = false

      case @ratecontrol
      when :special
        handbrake_options['quality']    = '1'
        encoder_options['vbv-maxrate']  = bitrate.to_s
        encoder_options['vbv-bufsize']  = ((bitrate * 2).to_i).to_s
        encoder_options['crf-max']      = '25'
        encoder_options['qpmax']        = '34'
      when :abr
        handbrake_options['vb']         = bitrate.to_s
        encoder_options['vbv-maxrate']  = ((bitrate * 1.5).to_i).to_s
        encoder_options['vbv-bufsize']  = ((bitrate * 2).to_i).to_s
        signal_hrd                      = true
      when :simple
        handbrake_options['quality']    = '1'
        encoder_options['vbv-maxrate']  = bitrate.to_s
        encoder_options['vbv-bufsize']  = bitrate.to_s
        signal_hrd                      = true
      when :avbr
        handbrake_options['vb']         = bitrate.to_s

        if encoder =~ /^x264(?:_10bit)?$/
          encoder_options['ratetol']    = 'inf'
          encoder_options['mbtree']     = '0'
        else
          fail UsageError, "`--avbr` not available with the `#{encoder}` encoder"
        end
      when :raw
        handbrake_options['vb']         = bitrate.to_s unless @handbrake_options.has_key? 'quality'
      end

      if signal_hrd
        encoder_options['nal-hrd']      = 'vbr' if encoder =~ /^x264(?:_10bit)?$/
        encoder_options['hrd']          = '1'   if encoder =~ /^x265(?:_1[02]bit)?$/
      end

      if  (@quick or @veryquick) and
          @handbrake_options.fetch('encoder-preset', 'medium') == 'medium' and
          encoder =~ /^x264(?:_10bit)?$/
        encoder_options['analyse']      = 'none'
        encoder_options['ref']          = '1'
        encoder_options['bframes']      = '1'     if @veryquick
        encoder_options['rc-lookahead'] = '30'
        encoder_options['me']           = 'dia'   if @veryquick
      end
    end

    def resolve_crop(media)
      if @crop == :detect
        width, height = media.info[:width], media.info[:height]
        hb_crop = media.info[:autocrop]
        hb_crop = Crop.constrain(hb_crop, width, height) if @constrain_crop
        crop = hb_crop

        unless media.info[:directory]
          ff_crop = Crop.detect(media.path, media.info[:duration], width, height)
          ff_crop = Crop.constrain(ff_crop, width, height) if @constrain_crop

          if hb_crop != ff_crop
            crop = case @fallback_crop
            when :handbrake
              hb_crop
            when :ffmpeg, :mplayer
              ff_crop
            when :minimal
              {
                :top    => [hb_crop[:top],    ff_crop[:top]].min,
                :bottom => [hb_crop[:bottom], ff_crop[:bottom]].min,
                :left   => [hb_crop[:left],   ff_crop[:left]].min,
                :right  => [hb_crop[:right],  ff_crop[:right]].min
              }
            when :none
              {:top => 0, :bottom => 0, :left => 0, :right => 0}
            else
              Console.error 'Results differ...'
              Console.error "From HandBrakeCLI: #{Crop.handbrake_string(hb_crop)}"
              Console.error "From ffmpeg:       #{Crop.handbrake_string(ff_crop)}"
              fail "crop detection failed: #{media.path}"
            end
          end
        end

        crop
      elsif @crop == :auto
        nil
      else
        @crop
      end
    end

    def prepare_audio(media, handbrake_options)
      return if @handbrake_options.fetch('audio', '') == 'none' or media.info[:audio].empty?
      main_track = resolve_main_audio(media)
      @audio_width[main_track] ||= @audio_width[:main]
      track_order = [main_track]

      case @extra_audio.first
      when :all
        media.info[:audio].each { |track, _| track_order << track unless track == main_track }
      when :language
        media.info[:audio].each do |track, info|
          if track != main_track and @audio_language.include? info[:language]
            track_order << track
          end
        end
      else
        @extra_audio.each do |track|
          track_order << track if track != main_track and media.info[:audio].include? track
        end
      end

      tracks, encoders, bitrates, mixdowns, names = [], [], [], [], []
      @aac_encoder ||= HandBrake.aac_encoder
      surround_encoder = @surround_format == 'ac3' ? @ac3_encoder : @aac_encoder
      stereo_encoder = @stereo_format == 'ac3' ? @ac3_encoder : @aac_encoder

      add_surround = ->(info, copy) do
        bitrate = info[:bps].nil? ? 640 : info[:bps] / 1000

        if copy or
            (@surround_format == 'ac3' and
            ((@ac3_encoder == 'ac3' and info[:format] =~ /AC3/i) or
            (@ac3_encoder == 'eac3' and info[:format] =~ /^(?:E-)?AC3$/i)) and
            bitrate <= @pass_ac3_bitrate) or
            (@surround_format == 'aac' and info[:format] =~ /^AAC/i)
          encoders << 'copy'
          bitrates << ''
          mixdowns << ''
        else
          encoders << surround_encoder

          if @surround_format == 'ac3'
            if  (@ac3_encoder == 'ac3'  and @ac3_bitrate >= 640) or
                (@ac3_encoder == 'eac3' and @ac3_bitrate == 1536)
              bitrates << ''
            else
              bitrates << @ac3_bitrate.to_s
            end

            mixdowns << ''
          else
            bitrates << ''
            mixdowns << '5point1'
          end
        end
      end

      add_stereo = ->(info, copy) do
        if copy or
            (info[:channels] <= 2.0 and
              ((@stereo_format == 'aac' and info[:format] =~ /^AAC/i) or
              (((@ac3_encoder == 'ac3' and info[:format] =~ /AC3/i) or
              (@ac3_encoder == 'eac3' and info[:format] =~ /^(?:E-)?AC3$/i)) and
              (@keep_ac3_stereo or @stereo_format == 'ac3'))))
          encoders << 'copy'
          bitrates << ''
          mixdowns << ''
        else
          encoders << stereo_encoder

          if stereo_encoder == 'eac3'
            if @ac3_bitrate == 1536
              bitrates << ''
            else
              if (info[:channels] > 1.0)
                if @ac3_bitrate == 768
                  bitrates << '384'
                else
                  bitrates << '224'
                end
              else
                if @ac3_bitrate == 768
                  bitrates << '192'
                else
                  bitrates << '96'
                end
              end
            end
          else
            bitrates << ''
          end

          mixdowns << (info[:channels] > 2.0 ? @mixdown : '')
        end
      end

      track_order.each do |track|
        tracks << track
        info = media.info[:audio][track]
        copy = (@copy_audio.first == :all or @copy_audio.include? track)

        if @copy_audio_name.first == :all or @copy_audio_name.include? track
          name = info.fetch(:name, '')
          name ||= ''
        else
          name = ''
        end

        name = @audio_name.fetch(track, name).gsub(/,/, '","')
        names << name

        case @audio_width.fetch(track, @audio_width[:other])
        when :double
          if info[:channels] > 2.0
            tracks << track
            names << name

            if @format == :mkv ? !@reverse_double_order : @reverse_double_order
              add_surround.call info, copy
              add_stereo.call info, false
            else
              add_stereo.call info, false
              add_surround.call info, copy
            end
          else
            add_stereo.call info, copy
          end
        when :surround
          if (info[:channels] > 2.0)
            add_surround.call info, copy
          else
            add_stereo.call info, copy
          end
        when :stereo
          add_stereo.call info, copy and info[:channels] <= 2.0
        end
      end

      handbrake_options['audio'] = tracks.join(',')
      encoders = encoders.join(',')
      handbrake_options['aencoder'] = encoders if encoders.gsub(/,/, '') != ''
      handbrake_options['audio-fallback'] = surround_encoder unless @copy_audio.empty?
      bitrates = bitrates.join(',')
      handbrake_options['ab'] = bitrates if bitrates.gsub(/,/, '') != ''
      mixdowns = mixdowns.join(',')
      handbrake_options['mixdown'] = mixdowns if mixdowns.gsub(/,/, '') != ''
      names = names.join(',')
      handbrake_options['aname'] = names if names.gsub(/,/, '') != ''
    end

    def resolve_main_audio(media)
      track = @main_audio

      if track.nil?
        unless @main_audio_language.nil?
          track, _ = media.info[:audio].find do |_, info|
            @main_audio_language == info[:language]
          end

          unless track.nil?
            @audio_name[track] = @audio_name[:main] if @audio_name.include? :main
          end
        end

        track ||= 1
      end

      track
    end

    def prepare_subtitle(media, handbrake_options)
      return if media.info[:subtitle].empty?

      if @auto_burn and not media.info[:mp4]
        burn_track, _ = media.info[:subtitle].find { |_, info| info[:forced] }
      else
        burn_track = @burn_subtitle
      end

      if burn_track == :scan or @force_subtitle == :scan
        track_order = ['scan']
        scan = true
      else
        track_order = []
        track_order << burn_track.to_s unless burn_track.nil?
        track_order << @force_subtitle.to_s unless @force_subtitle.nil?
        scan = false
      end

      case @extra_subtitle.first
      when :all
        media.info[:subtitle].each do |track, _|
          track_order << track unless track == burn_track or track == @force_subtitle
        end
      when :language
        media.info[:subtitle].each do |track, info|
          unless track == burn_track or track == @force_subtitle
            track_order << track if @subtitle_language.include? info[:language]
          end
        end
      else
        @extra_subtitle.each do |track|
          unless track == burn_track or track == @force_subtitle
            track_order << track if media.info[:subtitle].include? track
          end
        end
      end

      unless track_order.empty?
        track_order = track_order.join(',')
        handbrake_options['subtitle'] = track_order if track_order.gsub(/,/, '') != ''
        handbrake_options['subtitle-forced'] = nil if scan
        handbrake_options['subtitle-burned'] = nil unless burn_track.nil?
        handbrake_options['subtitle-default'] = nil unless @force_subtitle.nil?
      end
    end

    def prepare_srt(media, handbrake_options)
      files, encodings, offsets, languages = [], [], [], []

      @srt_file.each_with_index do |file, index|
        if file =~ /,/
          @temporary ||= Dir.mktmpdir
          link = @temporary + File::SEPARATOR + "subtitle_#{media.hash}_#{index}.srt"
          File.symlink File.absolute_path(file), link
          file = link
        end

        encoding  = @srt_encoding.fetch(index, '')
        offset    = @srt_offset.fetch(index, '').to_s
        language  = @srt_language.fetch(index, '')

        if index > 0 and (index == @burn_srt or index == @force_srt)
          files.unshift     file
          encodings.unshift encoding
          offsets.unshift   offset
          languages.unshift language
        else
          files     << file
          encodings << encoding
          offsets   << offset
          languages << language
        end
      end

      unless files.empty?
        files = files.join(',')
        handbrake_options['srt-file'] = files
        encodings = encodings.join(',')
        handbrake_options['srt-codeset'] = encodings if encodings.gsub(/,/, '') != ''
        offsets = offsets.join(',')
        handbrake_options['srt-offset'] = offsets if offsets.gsub(/,/, '') != ''
        languages = languages.join(',')
        handbrake_options['srt-lang'] = languages if languages.gsub(/,/, '') != ''
        handbrake_options['srt-burn'] = nil unless @burn_srt.nil?
        handbrake_options['srt-default'] = nil unless @force_srt.nil?
      end
    end

    def prepare_options(handbrake_options, encoder_options)
      encoder_options.merge! @encoder_options
      @disable_encoder_options.each { |name| encoder_options.delete name }

      unless encoder_options.empty?
        encopts = ''
        encoder_options.each { |name, value| encopts += "#{name}=#{value}:" }
        handbrake_options['encopts'] = encopts.chop
      end

      handbrake_options.merge! @handbrake_options
      @disable_handbrake_options.each { |name| handbrake_options.delete name }
    end

    def prepare_command(handbrake_options)
      handbrake_command = [HandBrake.command_name]

      Console.debug handbrake_options
      handbrake_options.each do |name, value|
        if value.nil?
          handbrake_command << "--#{name}"
        elsif @dry_run and name != 'encopts'
          handbrake_command << "--#{name}=#{value.shellescape}"
        else
          handbrake_command << "--#{name}=#{value}"
        end
      end

      if @dry_run
        puts handbrake_command.join(' ')
      end

      return handbrake_command
    end

    # Runs the transcode command.
    def transcode(handbrake_options)
      handbrake_command = prepare_command(handbrake_options)
      Console.debug handbrake_command.inspect
      log_file_path = handbrake_options['output'] + '.log'
      log_file = @log ? File.new(log_file_path, 'wb') : nil
      Console.info 'Transcoding with HandBrakeCLI...'

      begin
        IO.popen(handbrake_command, 'rb', :err=>[:child, :out]) do |io|
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
    end

    def adjust_metadata(output)
      return if @dry_run
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
          ], 'rb', :err=>[:child, :out]) do |io|
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

    def terminate
      FileUtils.remove_entry @temporary unless @temporary.nil?
    end
  end
end
