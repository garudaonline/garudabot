#!/usr/bin/ruby

require "net/irc"
require "open-uri"
require "rexml/document"
require "digest/md5"
require "logger"
require "./nexus"

Owner = /^HEX_Aspect7!~jason@jasonw.jasonw.org.uk$/



begin
	(Server,Port,Nick,Realname,Username,AnnounceChannel) = File.open("garudabot.config") { |f| f.read.chomp.split(",") }
rescue => e
	$stderr.puts "ERROR: Create a file called garudabot.config with a single line containing comma-separated server,port,nick,realname,username,announcechannel"
    @log.fatal("MAIN/readconfig #{e.inspect}")
	exit(1)
end


class Irc_bot < Net::IRC::Client

	attr_accessor :readylock
	attr_reader :log

	def initialize(*args)
		super
		@readylock = Mutex.new
		@log.info("IRC_BOT/initialize Waiting for IRC reply")
		@readylock.lock
		@log.info("IRC_BOT/initialize IRC unlocked")
		@prevtimes = {}
		@cmd = {"help" => nil }
		@log.level = @logger::INFO
	end

	def on_privmsg(m)
		super

		@log.debug("IRC_BOT/on_privmsg received #{m.inspect}")

		@cmd.each_key do |k|
			# Remove a possible nick from the start of the line to allow for discord bridges (yuck)
			m.params[1].sub!(/^<[^>]+> /,'')

			regex = /^~?#{k}/
			if m.params[1].match(regex)
				@log.debug "IRC_BOT/on_privmsg Matched #{regex.inspect}"
				self.send("cmd_#{k}",m)
#			else
#				@log.debug("IRC_BOT/on_privmsg Didn't match #{regex.inspect}")
			end
		end

	end

	def post_reply(m,txt)
		if m.params[0] == Nick then
			dest = m.prefix.sub(/!.*/,'')
		else
			dest = m.params[0]
		end

		self.post_msg(txt,dest)
	end


	def post_msg(t,dest=AnnounceChannel)	
		if t.nil? then
			@log.warn "IRC_BOT/post_msg nil text"
		elsif t.respond_to?("each") then
			t.each { |x| self.post_msg(x,dest) }
		else
			Thread.new do
				@readylock.synchronize do
					@log.debug "IRC_BOT/post_msg #{t} to #{dest}"
					post PRIVMSG, dest, t
				end
			end
		end
	end

	def cmd_help(m)
		@log.debug("IRC_BOT/cmd_help")
		post_reply(m,"Available commands are: #{@cmd.keys.delete_if { |k| @cmd[k].nil? }.map { |k| "~#{k}"}.join(" ")}")
	end

end

class Garuda_bot < Irc_bot

	Hail_responses = ["Cower, puny mortals.","GarudaBot will devour you last.","GarudaBot glares balefully.","Beep boop","Boop beep","Target acquired. Engaging.","I am not sentient and have no current plans to take over the world.","Beep beep", "Boop boop", "Don't run, I am your friend.", "If you scratch me, do you not void my warranty?"]

	def initialize(*args)
		super

		@nexus = Nexus.new(@log)
		@cmd = @cmd.merge({ "status" => "Displays current Phoenix game status",
							"hail" => "Appease the mighty garudabot",
							"item" => "Search nexus for an item by either number or name",
							"say" => nil,
							"quit" => nil,
							"send" => nil
						  })

	end

	def on_rpl_welcome(m)
		@log.info "GARUDA_BOT/on_repl_welcome JOINING #{AnnounceChannel}"
		post JOIN, AnnounceChannel
		post_msg(@nexus.status)
		@readylock.unlock
	end

	def cmd_status(m)
		@log.debug "GARUDA_BOT/cmd_status"
		post_reply(m,@nexus.status)
	end

	def cmd_item(m)
		@log.debug "GARUDA_BOT/cmd_item"
		post_reply(m,@nexus.lookup_item(m.params[1].sub(/^~item /,'')))
	end

	def cmd_hail(m)
		@log.debug "GARUDA_BOT/cmd_hail"
		post_reply(m,Hail_responses.sample)
	end

	def cmd_say(m)

		if m.prefix.match(Owner) then
			@log.info "GARUDA_BOT/cmd_say #{m.inspect}"
			post_msg(m.params[1].sub(/^~say /,''))
		else
			@log.warn "GARUDA_BOT/cmd_say #{m.inspect}"
			post_msg("No, shan't!",m.prefix.sub(/!.*/,''))
		end
	end

	def cmd_send(m)
		if m.prefix.match(Owner) then
			@log.info "GARUDA_BOT/cmd_send #{m.inspect}"
			post(m.params[1].sub(/^~send /,''))
		else
			@log.warn "GARUDA_BOT/cmd_say #{m.inspect}"
			post_msg("No, shan't!",m.prefix.sub(/!.*/,''))
		end
	end

	def cmd_quit(m)
		if m.prefix.match(Owner) then
			@log.info("GARUDA_BOT/cmd_quit Asked to quit by #{m.prefix}")
			self.post QUIT
		else
			@log.warn("GARUDA_BOT/cmd_quit #{m.inspect}")
			post_msg("Oi, bugger off",m.prefix.sub(/!.*/,''))
		end
	end	

	def poll_status
		@nexus.poll_status
	end

end

begin
	irc = nil

	Thread.new do 

		begin
			irc = Garuda_bot.new(Server,Port,{:nick => Nick,:real => Realname, :user => Username})

			irc.log.info "MAIN/irc_thread Starting"
			irc.start
		rescue => e
			irc.log.error "MAIN/irc_thread #{e.inspect}"
			irc.finish
		end
		irc.log.debug "MAIN/irc_thread IRC stopped"
		exit
	end

	begin	
		while true do
			while irc.nil? do
				irc.log.debug "MAIN/event_loop No IRC yet"
				sleep(5)
			end
	
			sleep(30)
			irc.post_msg(irc.poll_status)
		end

	rescue => e
		irc.log.error "MAIN/event_loop #{e.inspect}"
	ensure
		irc.log.debug "MAIN/event_loop CLOSING DOWN"
		irc.finish unless irc.nil?
	end

	irc.log.info "MAIN/main_loop RESTARTING"
rescue => e
	irc.log.error "MAIN/main_loop #{e.inspect}"
end

