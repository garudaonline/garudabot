#!/usr/bin/ruby

require "net/irc"
require "rexml/document"
require_relative "nexus"
require_relative "ashesirc"
require_relative "callandresponse"
require "date"

class Garuda_bot < Ashes_IRC

	Hail_responses = ["Cower, puny mortals.","GarudaBot will devour you last.","GarudaBot glares balefully.","Beep boop","Boop beep","Target acquired. Engaging.","I am not sentient and have no current plans to take over the world.","Beep beep", "Boop boop", "Don't run, I am your friend.", "If you scratch me, do you not void my warranty?"]

	Holidays = [ "2019-04-19","2019-04-22",
				 "2019-05-06","2019-05-27","2019-08-26",
				"2019-12-25","2019-12-26","2020-01-01","2020-04-10","2020-04-13",
				"2020-05-04","2020-05-25","2020-08-31","2020-12-25","2020-12-28"].map { |d| Date.parse(d) }
	def initialize(server,port,opts)
		super(server,port,opts)

		@nexus = opts[:nexus]
		@owner = Regexp.new(opts[:owner])
		@cmd = @cmd.merge({ "status" => "Displays current Phoenix game status",
							"item" => "Search nexus for an item by either number or name",	
							"holidays" => "Show dates of upcoming UK public holidays",
							"stardate" => "Convert between stardate and real dates",
							"say" => nil,
							"quit" => nil,
							"send" => nil,
							"time" => nil
						  })

		@hail_handler = CallAndResponse.new({ 	1 => Hail_responses,
												2 => Hail_responses,
												3 => ["Beep boop, battery low."]},
											300)

		@blame_handler = CallAndResponse.new({   1 => ["I blame Bridge."],
												2 => ["I *still* blame Bridge."],
												3 => ["From now on, assume I blame Bridge for everything."]},
											300)

		@msghandlers += [:msghandler_hail,:msghandler_blame]
	end

	def on_rpl_welcome(m)
		@log.info "GARUDA_BOT/on_repl_welcome JOINING #{@channel}"
		post JOIN, @channel
		post_msg(status_text)
		@readylock.unlock
		@log.info "GARUDA_BOT/on_repl_welcome irc ready"
	end

	def msghandler_hail(m)
		if m.params[1] =~ /garudabot/i then
			response = @hail_handler.call
			if not response.nil? then
				post_reply(m,response)
				@log.info "GARUDA_BOT/msghandler_hail responding #{response}"
			else
				@log.info "GARUDA_BOT/msghandler_hail timed out"
			end
		end
	end

	def msghandler_blame(m)
		if m.params[1] =~ /bridge/ then
			response = @blame_handler.call
			if not response.nil? then
				post_reply(m,response)
				@log.info "GARUDA_BOT/msghandler_blame responding #{response}"
			else
				@log.info "GARUDA_BOT/msghandler_blame timed out"
			end
		end
	end


	def status_text
		response = "Phoenix | Current time: #{Time.now().strftime("%H:%M")} | "
		response += @nexus.current_status.map { |s| s[0] + ": " + s[1].strftime("%H:%M") }.join(" | ")

	end

	def cmd_time(m)
		cmd_status(m)
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
			reply = "Nothing found - it might be private knowledge, sorry"
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

	def cmd_say(m)

		if m.prefix.match(@owner) then
			@log.info "GARUDA_BOT/cmd_say #{m.inspect}"
			post_msg(m.params[1].sub(/^~say /,''))
		else
			@log.warn "GARUDA_BOT/cmd_say #{m.inspect}"
			post_msg("No, shan't!",m.prefix.sub(/!.*/,''))
		end
	end

	def cmd_send(m)
		if m.prefix.match(@owner) then
			@log.info "GARUDA_BOT/cmd_send #{m.inspect}"
			post(m.params[1].sub(/^~send /,''))
		else
			@log.warn "GARUDA_BOT/cmd_say #{m.inspect}"
			post_msg("No, shan't!",m.prefix.sub(/!.*/,''))
		end
	end

	def cmd_quit(m)
		if m.prefix.match(@owner) then
			@log.info("GARUDA_BOT/cmd_quit Asked to quit by #{m.prefix}")
			post QUIT
		else
			@log.warn("GARUDA_BOT/cmd_quit #{m.inspect}")
			post_msg("Oi, bugger off",m.prefix.sub(/!.*/,''))
		end
	end	

	def get_status
		@nexus.get_status.map { |s| s[0] + ": " + s[1].strftime("%H:%M") }
	end

	def date_to_stardate(date)
		(date.strftime("%G").to_i-1800).to_s +
		date.strftime(".%-V.%u")
	end

	def cmd_stardate(m)
		begin
			q = m.params[1].sub(/^~stardate /,'')

			(y,w,d) = q.split(".").map { |x| x.to_i }

			if y.nil? or y < 100 or y > 999 or
			w.nil? or w < 1 or w > 53 or
			d.nil? or d < 1 or d > 5 then
				@log.info("GARUDA_BOT/cmd_stardate Parsing date #{q}")
				date = Date.parse(q)
				if date.wday==6 then date -= 1 end
				if date.wday==0 then date += 1 end
			else
				@log.info("GARUDA_BOT/cmd_stardate stardate #{q}")
				y = y + 1800
				date = Date.commercial(y,w,d)
			end

			response = date_to_stardate(date) + " is " + date.strftime("%-d %b %Y")

			if date.cweek >= 51 or date.cweek <= 2 then
				response += " (ish - beginning/end of the year is a bit iffy)"
			end 
		rescue => e
			response = "I need either a stardate or a recognisable date"
			@log.info("GARUDA_BOT/cmd_stardate #{e.to_s}")
		end

		post_reply(m,response)
	end

	def cmd_holidays(m)
		h = Holidays.find_all { |d| d > Date.today and d < (Date.today+31) }

		if h.empty? then
			h = Holidays.find { |d| d > Date.today }
			if h.nil? then
				post_reply(m,"I don't know about any holidays")
				@log.error("GARUDA_BOT/cmd_holidays no holidays found")
			else
				post_reply(m,"Next holiday is #{h.strftime("%-d %B")}")
			end
		else 		
			post_reply(m,"Upcoming holidays: #{h.map { |d| d.strftime("%-d %B") }.join(", ")}")
		end
	end

	def get_items
		@nexus.get_items
	end

	def start
		self.get_items
		self.get_status

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




