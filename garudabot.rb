#!/usr/bin/ruby

require "net/irc"
require "rexml/document"
require "./nexus"
require "./ashesirc"

class Garuda_bot < Ashes_IRC

	Hail_responses = ["Cower, puny mortals.","GarudaBot will devour you last.","GarudaBot glares balefully.","Beep boop","Boop beep","Target acquired. Engaging.","I am not sentient and have no current plans to take over the world.","Beep beep", "Boop boop", "Don't run, I am your friend.", "If you scratch me, do you not void my warranty?"]

	def initialize(server,port,opts)
		super(server,port,opts)

		@nexus = opts[:nexus]
		@nexus.get_items
		@nexus.get_status
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
		post_msg(status_text)
		@readylock.unlock
		@log.info "GARUDA_BOT/on_repl_welcome irc ready"
	end

	def status_text
		@nexus.current_status.map { |s| s[0] + ": " + s[1].strftime("%H:%M") }.    join(" | ")
	end

	def cmd_status(m)
		@log.info "GARUDA_BOT/cmd_status"
		post_reply(m,status_text)
	end

	def cmd_item(m)
		@log.info "GARUDA_BOT/cmd_item"
		q = m.params[1].sub(/^~item /,'')
		if q.to_i > 0 then
			@log.debug "GARUDA_BOT/cmd_item searching for number #{q.to_i}"
			items = @nexus.items.find_all { |i| i["Number"] == q }
		else
			items = @nexus.items.find_all { |i| i["Name"] =~ Regexp.new(q,Regexp::IGNORECASE) }
		end

		if items.empty? then
			reply = "No items found."
		elsif items.length > 5 then
			reply = "#{items.length} results: " + items.map { |i| i.to_s }.join(", ")
			if reply.length > 300 then
				reply = reply[0..297] + "..."
			end
		else
			reply = items.map { |i| i.description + " " + "https://phoenixbse.com/index.php?a=game&sa=items&id=" + i["Number"] }
		end		

		
		@log.info "GARUDA_BOT/cmd_item reply #{reply.inspect}"
		post_reply(m,reply)
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




