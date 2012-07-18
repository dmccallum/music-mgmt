ORIG_SRC_BASE = ENV["ORIG_SRC_BASE"] || "/home/dmccallum/Music"
SRC_BASE = ENV["SRC_BASE"] || "/home/dmccallum/Music_Work"
DEST_BASE = ENV["DEST_BASE"] || "/home/dmccallum/drobo"
FLAC_DEST_BASE = ENV["FLAC_DEST_BASE"] || "#{DEST_BASE}/Music_Lossless"
MP3_DEST_BASE = ENV["MP3_DEST_BASE"] || "#{DEST_BASE}/Music_Lossy"

$encoded_cnt = 0
$cp_cnts = {}
$rm_skips = {}

task :all => [:init_src,:encode_mp3s,:copy_mp3s,:copy_flacs,:safe_rm_mp3s,:safe_rm_flacs,:safe_rm_wavs]
task :no_rm => [:init_src,:encode_mp3s,:copy_mp3s,:copy_flacs]
task :cp => [:copy_mp3s,:copy_flacs]
task :cp_and_rm => [:copy_mp3s,:copy_flacs,:safe_rm_mp3s,:safe_rm_flacs,:safe_rm_wavs]
task :rm => [:safe_rm_mp3s,:safe_rm_flacs,:safe_rm_wavs]

#task :multiall do |t|
#  puts DirList["#{DEST_BASE}}/**"]
#end

#task :spawn do |t|
#  Process.spawn ("rake hw[Cruel]")
#  Process.spawn ("rake hw[Nice-ish\\ World]")
#  Process.spawn ("rake hw[World]")
#  Process.waitall
#end

task :processing_order do |t,args|
  with_each_src_file ".wav" do |f, idx, of|
    puts f
  end
end

task :offset_tracks, [:in_dir, :offset] do |t,args|
  FileList["#{args.in_dir}/**"].each do |f|
    file_name = File.basename(f)
    offset_file_name = "%02d" % (file_name[0,2].to_i + args.offset.to_i) + file_name[2, file_name.length]
    puts "Renaming #{f} to #{File.dirname(f)}/#{offset_file_name}"
    FileUtils.mv f, "#{File.dirname(f)}/#{offset_file_name}"
  end
end

task :init_src do |t|
  FileUtils.mkdir_p SRC_BASE unless File.exists? SRC_BASE
  FileUtils.mv Dir.glob("#{ORIG_SRC_BASE}/*"), "#{SRC_BASE}" unless !(File.exists? ORIG_SRC_BASE) || ORIG_SRC_BASE == SRC_BASE
end

task :encode_mp3s do |t|
  log "Encoding mp3s..."
  elapsed_secs = time do
    with_each_src_file ".wav" do |f, idx, of|
      mp3 = encode_mp3 f, idx, of
    end
  end
  log "Encoded #{$encoded_cnt} tracks in #{format_secs(elapsed_secs)}"
end

task :copy_mp3s do |t|
  log "Copying mp3s..."
  elapsed_secs = time do
    cp_tracks_by_ext ".mp3", MP3_DEST_BASE
  end
  log "Copied #{$cp_cnts['.mp3']} mp3s in #{format_secs(elapsed_secs)}"
end

task :copy_flacs do |t|
  log "Copying flacs..."
  elapsed_secs = time do
    cp_tracks_by_ext ".flac", FLAC_DEST_BASE
  end
  log "Copied #{$cp_cnts['.flac']} flacs in #{format_secs(elapsed_secs)}"
end

task :safe_rm_mp3s do |t|
  log "Cleaning up mp3s..."
  rm_by_ext ".mp3", if_dest_track_exists(MP3_DEST_BASE, ".mp3")
  log "WARNING: Skipped cleanup of #{$rm_skips['.mp3'].size} mp3s... #{$rm_skips['.mp3']}"  unless $rm_skips['.mp3'] == nil
end

task :safe_rm_flacs do |t|
  log "Cleaning up flacs..."
  rm_by_ext ".flac", if_dest_track_exists(FLAC_DEST_BASE, ".flac")
  log "WARNING: Skipped cleanup of #{$rm_skips['.flac'].size} flacs... #{$rm_skips['.flac']}" unless $rm_skips['.flac'] == nil
end

task :safe_rm_wavs do |t|
  log "Cleaning up wavs..."
  rm_by_ext ".wav", if_dest_track_exists(FLAC_DEST_BASE, ".flac")
  log "WARNING: Skipped cleanup of #{$rm_skips['.wav'].size} wavs... #{$rm_skips['.wav']}" unless $rm_skips['.wav'] == nil
end

def with_each_src_file(ext, &action)
  file_list = FileList["#{SRC_BASE}/**/*#{ext}"]
  idx = 0
  file_list.each do |f|
    action.call(f, idx+=1, file_list.length)
  end
end

def rm_by_ext(ext, predicate=nil)
  with_each_src_file ext do |f, idx, of|
    if predicate == nil || predicate.call(f,ext) then
      #log "Removing #{File.basename(f)}. #{idx} of #{of}."
      FileUtils.rm f
    else
      if $rm_skips[ext] == nil then
        $rm_skips[ext] = [ f ]
      else
        $rm_skips[ext] << f
      end
    end
  end
end

def if_dest_track_exists(dest_base, dest_ext)
  return lambda { | src_file, src_ext |
    dir_and_file = dir_and_track_file_for(src_file, src_ext, dest_base, dest_ext)
    return File.exists? dir_and_file[:path]
  }
end

def cp_tracks_by_ext(ext, dest)
  with_each_src_file ext do |f, idx, of|
    dir_and_file = dir_and_track_file_for(f, ext, dest, ext)
    dir = dir_and_file[:album_dir]
    FileUtils.mkdir_p dir unless File.exists? dir
    log_partial "Copying #{File.basename(f)} (#{idx} of #{of})... "
    elapsed_secs = time do
      FileUtils.cp f, "#{dir_and_file[:path]}"
    end
    log_append_and_eol format_secs(elapsed_secs)
    $cp_cnts[ext] = $cp_cnts[ext] == nil ? 1 : $cp_cnts[ext] + 1
  end
end

def dir_and_track_file_for(file, ext, dest, dest_ext)
  track_info = track_info_for(file, ext)
  album_dir = "#{dest}/#{track_info[:album_artist]}/#{track_info[:album]}"
  track_file = "#{track_info[:track]} - #{track_info[:artist]} - #{track_info[:song]}#{dest_ext}"
  { :album_dir => album_dir, :track_file => track_file, :path => "#{album_dir}/#{track_file}" }  
end

def encode_mp3(in_wav, idx, of)
  in_wav = File.expand_path(in_wav)
  out_mp3 = in_wav.gsub(/\.wav$/, ".mp3")
  track_info = track_info_for(in_wav, ".wav")
  cmd = "lame --quiet -h --vbr-old -V 4 --tt '#{track_info[:song]}' --ta '#{track_info[:artist]}' --tl '#{track_info[:album]}' --ty '#{track_info[:year]}' --tn '#{track_info[:track]}' --tv 'TPE2=#{track_info[:album_artist]}' '#{in_wav}' '#{out_mp3}'"
  log_partial "Encoding #{track_info[:artist]} - #{track_info[:song]} (#{idx} of #{of})... "
  $encoded_cnt += 1
  elapsed_secs = time do
    system cmd
  end
  log_append_and_eol "#{format_secs(elapsed_secs)}"
  out_mp3
end

def track_info_for(track, ext)
  dir = File.dirname(track)
  file = File.basename(track, ext)
  dir_parts = dir.split("__-__")
  file_parts = file.split("__-__")
  info = { :artist => file_parts[1].gsub("_", " "),
         :album_artist => File.basename(dir_parts[0]).gsub("_", " "),
         :album => dir_parts[1].gsub("_", " "),
         :year => dir_parts[2],
         :track => file_parts[0],
         :song => file_parts[2].gsub("_", " ") }
  info
end

def time
  start = Time.new
  yield
  stop = Time.new
  stop - start
end

def format_secs(elapsed_secs)
  days,secs = elapsed_secs.divmod(60*60*24)
  hours,secs = elapsed_secs.divmod(60*60)
  mins,secs = elapsed_secs.divmod(60)
  msecs = (elapsed_secs - elapsed_secs.truncate) * 1000
  rtn = ""
  rtn << "#{days}d " unless days == 0
  rtn << "#{hours}h " unless hours == 0
  rtn << "#{mins}m " unless mins == 0
  rtn << "#{secs.floor}s " unless secs.floor == 0
  rtn << "#{msecs.round}ms"
  rtn.strip
end

def log_partial(msg)
  print "#{format_ts_for_log} #{msg}"
end

def log_append_and_eol(msg)
  puts msg
end

def log(msg)
  puts "#{format_ts_for_log} #{msg}"
end

def format_ts_for_log
  "#{Time.new.strftime('%Y-%m-%d %H:%M:%S.%L')}"
end
