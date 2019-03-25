#!/usr/bin/ruby

require "net/irc"
require "logger"

class Ashes_IRC < Net::IRC::Client

	attr_accessor :readylock
	attr_reader :log

	def initialize(*args)
		super
		@readylock = Mutex.new
		@readylock.lock
		@prevtimes = {}
		@cmd = {"help" => nil }
		@msghandlers = []
		@channel = opts[:channel] 
	end

	def on_privmsg(m)
		super

		@log.debug("ASHES_IRC/on_privmsg received #{m.inspect}")

		@cmd.each_key do |k|
			# Remove a possible nick from the start of the line to allow for discord bridges (yuck)
			m.params[1].sub!(/^<[^>]+> /,'')

			regex = /^~#{k}/
			if m.params[1].match(regex)
				@log.debug "ASHES_IRC/on_privmsg Matched #{regex.inspect}"
				self.send("cmd_#{k}",m)
#			else
#				@log.debug("ASHES_IRC/on_privmsg Didn't match #{regex.inspect}")
			end
		end

		@msghandlers.each do |h|
			self.send(h,m)
		end

	end

	def post_reply(m,txt)
		if m.params[0] == self.nick then
			dest = m.prefix.sub(/!.*/,'')
		else
			dest = m.params[0]
		end

		self.post_msg(txt,dest)
	end

	def on_ping(*args)
		super
	end

	def post_msg(t,dest=@channel)	
		if t.nil? then
			@log.warn "ASHES_IRC/post_msg nil text"
		elsif t.respond_to?("each") then
			t.each { |x| self.post_msg(x,dest) }
		else
			Thread.new do
				@readylock.synchronize do
					@log.debug "ASHES_IRC/post_msg #{t} to #{dest}"
					post PRIVMSG, dest, t
				end
			end
		end
	end

	def cmd_help(m)
		@log.info("ASHES_IRC/cmd_help")
		post_reply(m,"Available commands are: #{@cmd.keys.delete_if { |k| @cmd[k].nil? }.map { |k| "~#{k}"}.join(" ")}")
	end

end
