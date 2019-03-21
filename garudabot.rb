#!/usr/bin/ruby

require "net/irc"
require "open-uri"
require "rexml/document"
require "digest/md5"
require "logger"
require "./nexus"
require "./garudabot"


class Irc_bot < Net::IRC::Client

	attr_accessor :readylock
	attr_reader :log

	def initialize(*args)
		super
		@readylock = Mutex.new
		@readylock.lock
		@prevtimes = {}
		@cmd = {"help" => nil }
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

	def on_ping(*args)
		super
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
		@log.info("IRC_BOT/cmd_help")
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
		post_msg(@nexus.status_text)
		@readylock.unlock
		@log.info "GARUDA_BOT/on_repl_welcome irc ready"
	end

	def cmd_status(m)
		@log.info "GARUDA_BOT/cmd_status"
		post_reply(m,@nexus.status_text)
	end

	def cmd_item(m)
		@log.info "GARUDA_BOT/cmd_item"
		post_reply(m,@nexus.search_item(m.params[1].sub(/^~item /,'')))
	end

	def cmd_hail(m)
		@log.info "GARUDA_BOT/cmd_hail"
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
			post QUIT
		else
			@log.warn("GARUDA_BOT/cmd_quit #{m.inspect}")
			post_msg("Oi, bugger off",m.prefix.sub(/!.*/,''))
		end
	end	

	def get_status
		@nexus.get_status
	end

	def start
		@log.debug("GARUDA_BOT/start starting event thread")
		Thread.new do
			while true do
				sleep(60)
				if @readylock.locked? then 
					@log.info("GARUDA_BOT/start event thread waiting for ready lock") 
				end
				@readylock.synchronize do
					@log.debug("GARUDA_BOT/start event thread polling")
					post_msg get_status
				end

			end
		end

		@log.debug("GARUDA_BOT/start starting irc")
		super
	end

end




