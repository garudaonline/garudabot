#!/usr/bin/ruby

require "logger"
require "./garudabot.rb"
require "./nexus"

Owner = /^HEX_Aspect7!~jason@jasonw.jasonw.org.uk$/

log = Logger.new(STDOUT)
log.level = Logger::DEBUG

config = ARGV[0] || "garudabot.config"

begin
	(Server,Port,Nick,Realname,Username,AnnounceChannel) = File.open(config) { |f| f.read.chomp.split(",") }
rescue => e
	log.fatal("MAIN/readconfig #{e.inspect}")
	$stderr.puts "ERROR: Create a file called garudabot.config with a single line containing comma-separated server,port,nick,realname,username,announcechannel"
  
	exit(1)
end

log.debug [Server,Port,Nick,Realname,Username,AnnounceChannel].inspect

nexus = Nexus.from_file(".nexusid",log)

garuda = Garuda_bot.new(Server,Port,{:nick => Nick,:real => Realname, :user => Username,:logger => log,:nexus => nexus})
garuda.start



