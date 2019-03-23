#!/usr/bin/ruby

require "logger"
require "./garudabot.rb"
require "./nexus"
require "yaml" 


VERSION = "garuda-1.0-iss7"

config_template = { "Ashes_IRC" => { "server" => "example.com", "port" => 6667, "nick" => "ashbot", 
                                                             "realname" => "Ashes Bot", "user" => "ashbot", "channel" =>"##test", 
                                                              "owner" => "owner!~owner@example.com"}, 
                                   "Garuda_bot" => {}, 
                                   "Nexus" => { "uid" => "1", "code" => "abcd" }, 
                                   "Logger" => { "level" => "DEBUG" } 
                                  } 
config_fname = ARGV[0] || "garudabot.config"

if File.exists?(config_fname) then
     config = YAML.load(File.open(config_fname).read)
else
     puts "ERROR: No config found. Creating a template config file #{config_fname}" 
     File.open(config_fname, "w") {}
end

log = Logger.new(STDOUT)

log.level = Logger::DEBUG
log.debug [Server,Port,Nick,Realname,Username,AnnounceChannel].inspect

nexus = Nexus.from_file(".nexusid",log)

garuda = Garuda_bot.new(Server,Port,{:nick => Nick,:real => Realname, :user => Username,:logger => log,:nexus => nexus})
garuda.start



