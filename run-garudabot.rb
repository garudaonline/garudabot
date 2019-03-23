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
     File.open(config_fname, "w") { |f| f.puts config_template.to_yaml }
     exit(1)
end

c_logger = config["Logger"] 
log = Logger.new(STDOUT)

log.level = Logger.const_get(c_logger["level"])
log.debug config.inspect

c_nexus = config["Nexus"] 
nexus = Nexus.new(c_nexus["uid"] , c_nexus["code"]) 

c_irc = config["Ashes_IRC"] 

garuda = Garuda_bot.new(c_irc["server"] ,c_irc["port"] ,{:nick => c_irc["nick"] ,:real => c_irc["realname"] , :user => c_irc["user"] , :channel => c_irc["channel"], :logger => log,:nexus => nexus})
garuda.start



