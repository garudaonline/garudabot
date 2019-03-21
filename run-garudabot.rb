#!/usr/bin/ruby

require "logger"
require "./garudabot.rb"
require "./nexus"

Owner = /^HEX_Aspect7!~jason@jasonw.jasonw.org.uk$/

log = Logger.new(STDOUT)
log.level = Logger::INFO

config = ARGV[0] || "garudabot.config"

begin
	(Server,Port,Nick,Realname,Username,AnnounceChannel) = File.open(config) { |f| f.read.chomp.split(",") }
rescue => e
	$stderr.puts "ERROR: Create a file called garudabot.config with a single line containing comma-separated server,port,nick,realname,username,announcechannel"
    @log.fatal("MAIN/readconfig #{e.inspect}")
	exit(1)
end

garuda = Garuda_bot.new(Server,Port,{:nick => Nick,:real => Realname, :user => Username,:logger => log})
garuda.start



