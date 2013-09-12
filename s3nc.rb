#!/usr/bin/env ruby
# 
#  @@@@@@   @@@@@@   @@@  @@@   @@@@@@@
# @@@@@@@   @@@@@@@  @@@@ @@@  @@@@@@@@
# !@@           @@@  @@!@!@@@  !@@     
# !@!           @!@  !@!!@!@!  !@!     
# !!@@!!    @!@!!@   @!@ !!@!  !@!     
#  !!@!!!   !!@!@!   !@!  !!!  !!!     
#      !:!      !!:  !!:  !!!  :!!     
#     !:!       :!:  :!:  !:!  :!:     
# :::: ::   :: ::::   ::   ::   ::: :::
# :: : :     : : :   ::    :    :: :: :
# 
# Command line tool to synchronize two buckets by copying all modified objects
# from one bucket to another in parallel for blazing speed (or around 300 
# objects/s on my machine using 100 threads).
# 
# Usage: s3nc.rb [options] SRC DST
#     -n, --threads NUMBER             Use NUMBER of threads to copy (default 20)
#     -p, --prefix PREFIX              Copy objects prefixed with PREFIX (default "")
#     -a, --act ACL                    Copy objects with ACL [private,public-read,public-read-write,authenticated-read,bucket-owner-read,bucket-owner-full-control] (default public-read)
#     -k, --key KEY                    Set Amazon Access KEY (default ENV['S3_KEY'])
#     -s, --secret SECRET              Sets the Amazon Access SECRET (default ENV['S3_SECRET'])
#     -u, --unsafe                     Use http (fast) instead of https (secure)
#     -r, --reduced                    Use reduced redundancy storage (cheap) instead of standard (reliable)
#     -c, --create                     Create the destination bucket if it does not already exist
#     -y, --yes                        Don't ask to continue (useful for cron-jobs)
#     -q, --quieter                    Not interested in the progress
# 
# Examples:
#
#   $ s3nc myfrombucket mytobucket 
#
#   $ s3nc -n 100 myfrombucket mytobucket
#
#   $ s3nc -n 100 -p /to-copy myfrombucket mytobucket
#
#
# Dependencies:
#
#   * https://github.com/appoxy/aws
#   * https://github.com/grosser/parallel
#
#  $ gem install aws parallel
#
#

require 'optparse'
require 'logger'

options = {
  :threads => 20,
  :prefix => '',
  :quiet => false,
  :acl => 'public-read',
  :key => ENV['S3_KEY'],
  :secret => ENV['S3_SECRET'],
  :unsafe => false,
  :create => false,
  :storage_class => 'STANDARD',
  :ask => true
}

AMAZON_ACL = %w{private public-read public-read-write authenticated-read bucket-owner-read bucket-owner-full-control}

puts ''                                       
puts ' @@@@@@   @@@@@@   @@@  @@@   @@@@@@@'  
puts '@@@@@@@   @@@@@@@  @@@@ @@@  @@@@@@@@'  
puts '!@@           @@@  @@!@!@@@  !@@     '  
puts '!@!           @!@  !@!!@!@!  !@!     '  
puts '!!@@!!    @!@!!@   @!@ !!@!  !@!     '  
puts ' !!@!!!   !!@!@!   !@!  !!!  !!!     '  
puts '     !:!      !!:  !!:  !!!  :!!     '  
puts '    !:!       :!:  :!:  !:!  :!:     '  
puts ':::: ::   :: ::::   ::   ::   ::: :::'  
puts ':: : :     : : :   ::    :    :: :: :'
puts ''

opts = OptionParser.new do |opts|
  opts.banner = "Usage: s3nc.rb [options] SRC DST"

  opts.on("-n", "--threads NUMBER", "Use NUMBER of threads to copy (default #{options[:threads]})") do |n|
    options[:threads] = n.to_i
  end

  opts.on("-p", "--prefix PREFIX", "Copy objects prefixed with PREFIX (default \"\")") do |p|
    options[:prefix] = p
  end

  opts.on("-a", "--act ACL", AMAZON_ACL, "Copy objects with ACL [#{AMAZON_ACL.join(',')}] (default #{options[:acl]})") do |acl|
    options[:acl] = acl
  end

  opts.on("-k", "--key KEY", "Set Amazon Access KEY (default ENV['S3_KEY'])") do |key|
    options[:key] = key
  end

  opts.on("-s", "--secret SECRET", "Sets the Amazon Access SECRET (default ENV['S3_SECRET'])") do |secret|
    options[:secret] = secret
  end

  opts.on("-u", "--unsafe", "Use http (fast) instead of https (secure)") do |v|
    options[:unsafe] = v
  end

  opts.on("-r", "--reduced", "Use reduced redundancy storage (cheap) instead of standard (reliable)") do |r|
    options[:storage_class] = 'REDUCED_REDUNDANCY'
  end

  opts.on("-c", "--create", "Create the destination bucket if it does not already exist") do |create|
    options[:create] = create
  end

  opts.on("-y", "--yes", "Don't ask to continue (useful for cron-jobs)") do |y|
    options[:ask] = !y
  end

  opts.on("-q", "--quieter", "Not interested in the progress") do |v|
    options[:quiet] = v
  end

  opts.separator ""
end

opts.parse!

if (src = ARGV.shift).nil?
  puts 'Missing SRC bucket'
  puts ''
  puts opts.to_s
  exit 1
end

if (dst = ARGV.shift).nil?
  puts 'Missing DST bucket'
  puts ''
  puts opts.to_s
  exit 1
end

if options[:key].to_s.empty?
  puts 'Missing Amazon Key'
  puts ''
  puts opts.to_s
  exit 1
end

if options[:secret].to_s.empty?
  puts 'Missing Amazon Secret'
  puts ''
  puts opts.to_s
  exit 1
end

missing = []
begin; require 'aws'; rescue Exception => e; missing << 'aws'; end
begin; require 'parallel'; rescue Exception => e; missing << 'parallel'; end
if missing.any?
  puts 'Missing dependencies: '+missing.join(', ')
  puts ''
  puts "  `gem install #{missing.join(' ')}`"
  puts ''
  puts opts.to_s
  exit 1
end

# Silence the AWS gem
logger = Logger.new(STDERR)
logger.level = Logger::ERROR

puts "Preparing to copy objects from #{src} to #{dst} " + (options[:prefix].empty? ? '' : "prefixed with \"#{options[:prefix]}\"")
puts '(this might take a while if the buckets are huge)'
puts ''

# Create S3 connection
s3 = Aws::S3.new(options[:key],options[:secret],{
  :port => options[:unsafe] ? 80 : 443, 
  :protocol => options[:unsafe] ? 'http' : 'https', 
  :connection_mode => :per_thread,
  :logger => logger
})

# See if we have write access to destination
begin
  key = s3.bucket(dst).key('_s3nc')
  key.put ''
  key.delete
rescue Aws::AwsError => e
  if e.include?(/AccessDenied/)
    puts "AccessDenied: Cannot write to destination bucket #{dst}."
    puts ''
    exit 1
  else
    raise
  end
end

# Fetch all keys of the source
begin
  dst_map = s3.bucket(dst,options[:create]).keys(:prefix => options[:prefix]).inject({}) {|m,k| m[k.name] = k; m }
rescue Aws::AwsError => e
  if e.include?(/AccessDenied/)
    puts "AccessDenied: Cannot read from destination bucket #{dst}."
    puts ''
    exit 1
  end
  raise
end

begin
  src_map = s3.bucket(src).keys(:prefix => options[:prefix]).inject({}) {|m,k| m[k.name] = k; m }
rescue Aws::AwsError => e
  if e.include?(/AccessDenied/)
    puts "AccessDenied: Cannot read from source bucket #{src}."
    puts ''
    exit 1
  end
  raise
end

# Not needed anymore (new connections is in copy threads)
s3.close_connection 

# Diff the two trees
diff = src_map.reject {|key,obj| dst_map.has_key?(key) && dst_map[key].last_modified > obj.last_modified }

# No need to fire up more threads than objects
options[:threads] = [diff.size,options[:threads]].min

puts "Found #{src_map.size} source objects and #{dst_map.size} destination objects." 
unless diff.empty?
  puts "#{diff.size} to copy using #{options[:threads]} threads." 
else
  puts 'Nothing to copy.'
end
puts ''

exit if diff.empty?

# Prompt to continue (c), list the diff (l) or quit 
while options[:ask] do
  print 'Do you want to [c]ontinue, [l]ist the files to be copied or quit (any other key)? '
  case gets.chomp[0]
    when 'c'; puts "\n"; break;
    when 'l'; puts "\n"; diff.each {|k,o| puts "[#{o.last_modified}] #{o.name}"}; puts "\n";
  else
    puts "\n"
    puts 'Please come again!'
    puts '' 
    exit
  end
end

# Keep track of time
start_time = Time.now

# Copy them on subprocesses
results = Parallel.map_with_index(diff.values, :in_threads => options[:threads]) do |key,i|
  print "#{(i+1).to_s.rjust(diff.size.to_s.size)}/#{diff.size} [#{key.last_modified}] #{key.name}\n" unless options[:quiet]
  begin
    s3.interface.copy(src,key.name,dst,key.name,:replace,{
      'x-amz-acl' => options[:acl],
      'x-amz-copy-source-if-modified-since' => key.last_modified,
      'x-amz-storage-class' => options[:storage_class]
    })
  rescue Exception => e
    e
  end
end

end_time = Time.now

# Results
failed, copied = results.partition{|r| r.kind_of? Exception }
puts ''
puts "Completed in #{end_time - start_time} seconds. Copied #{copied.size} objects successfully while #{failed.size} failed#{" (listed below)" unless options[:quiet] || failed.empty?}."
puts ''
failed.each {|e| puts e} unless options[:quiet]

