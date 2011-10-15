SRC_BASE = ENV["SRC_BASE"] || "/home/dmccallum/Music"
DEST_BASE = ENV["DEST_BASE"] || "/home/dmccallum/drobo"
FLAC_DEST_BASE = ENV["FLAC_DEST_BASE"] || "#{DEST_BASE}/Music_Lossless"
MP3_DEST_BASE = ENV["MP3_DEST_BASE"] || "#{DEST_BASE}/Music_Lossy"

$encoded_cnt = 0
$cp_cnts = {}
$rm_skips = {}

task :all => [:encode_mp3s,:copy_mp3s,:copy_flacs,:safe_rm_mp3s,:safe_rm_flacs,:safe_rm_wavs]

task :encode_mp3s do |t|
  puts "Encoding mp3s..."
  with_each_src_file ".wav" do |f|
    mp3 = encode_mp3 f
  end
  puts "Encoded #{$encoded_cnt} tracks."
end

task :copy_mp3s do |t|
  puts "Copying mp3s..."
  cp_tracks_by_ext ".mp3", MP3_DEST_BASE
  puts "Copied #{$cp_cnts['.mp3']} mp3s."
end

task :copy_flacs do |t|
  puts "Copying flacs..."
  cp_tracks_by_ext ".flac", FLAC_DEST_BASE
  puts "Copied #{$cp_cnts['.flac']} flacs."
end

task :safe_rm_mp3s do |t|
  puts "Cleaning up mp3s..."
  rm_by_ext ".mp3", if_dest_track_exists(MP3_DEST_BASE, ".mp3")
  puts "WARNING: Skipped cleanup of #{$rm_skips['.mp3'].size} mp3s... #{$rm_skips['.mp3']}"  unless $rm_skips['.mp3'] == nil
end

task :safe_rm_flacs do |t|
  puts "Cleaning up flacs..."
  rm_by_ext ".flac", if_dest_track_exists(FLAC_DEST_BASE, ".flac")
  puts "WARNING: Skipped cleanup of #{$rm_skips['.flac'].size} flacs... #{$rm_skips['.flac']}" unless $rm_skips['.flac'] == nil
end

task :safe_rm_wavs do |t|
  puts "Cleaning up wavs..."
  rm_by_ext ".wav", if_dest_track_exists(FLAC_DEST_BASE, ".flac")
  puts "WARNING: Skipped cleanup of #{$rm_skips['.wav'].size} wavs... #{$rm_skips['.wav']}" unless $rm_skips['.wav'] == nil
end

def with_each_src_file(ext, &action)
  FileList["#{SRC_BASE}/**/*#{ext}"].each &action
end

def rm_by_ext(ext, predicate=nil)
  with_each_src_file ext do |f|
    if predicate == nil || predicate.call(f,ext) then
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
  with_each_src_file ext do |f|
    dir_and_file = dir_and_track_file_for(f, ext, dest, ext)
    dir = dir_and_file[:album_dir]
    FileUtils.mkdir_p dir unless File.exists? dir
    FileUtils.cp f, "#{dir_and_file[:path]}"
    $cp_cnts[ext] = $cp_cnts[ext] == nil ? 1 : $cp_cnts[ext] + 1
  end
end

def dir_and_track_file_for(file, ext, dest, dest_ext)
  track_info = track_info_for(file, ext)
  album_dir = "#{dest}/#{track_info[:artist]}/#{track_info[:album]}"
  track_file = "#{track_info[:track]} - #{track_info[:artist]} - #{track_info[:song]}#{dest_ext}"
  { :album_dir => album_dir, :track_file => track_file, :path => "#{album_dir}/#{track_file}" }  
end

def encode_mp3(in_wav)
  in_wav = File.expand_path(in_wav)
  out_mp3 = in_wav.gsub(/\.wav$/, ".mp3")
  track_info = track_info_for(in_wav, ".wav")
  cmd = "lame --quiet -h --vbr-old -V 4 --tt '#{track_info[:song]}' --ta '#{track_info[:artist]}' --tl '#{track_info[:album]}' --ty '#{track_info[:year]}' --tn '#{track_info[:track]}' '#{in_wav}' '#{out_mp3}'"
  puts "Encoding... #{track_info[:artist]} - #{track_info[:song]}"
  $encoded_cnt += 1
  system cmd
  out_mp3
end

def track_info_for(track, ext)
  dir = File.dirname(track)
  file = File.basename(track, ext)
  dir_parts = dir.split("__-__")
  file_parts = file.split("__-__")
  info = { :artist => File.basename(dir_parts[0]).gsub("_", " "),
         :album => dir_parts[1].gsub("_", " "),
         :year => dir_parts[2],
         :track => file_parts[0],
         :song => file_parts[2].gsub("_", " ") }
  info
end
