#!/usr/bin/ruby

require "net/irc"
require "open-uri"
require "rexml/document"
require "digest/md5"
require "logger"

Owner = /^HEX_Aspect7!~jason@jasonw.jasonw.org.uk$/



Log = Logger.new(STDERR)
Log.unknown("Log started")
Log.level = Logger::INFO

begin
	(Server,Port,Nick,Realname,Username,AnnounceChannel) = File.open("garudabot.config") { |f| f.read.chomp.split(",") }
rescue => e
	$stderr.puts "ERROR: Create a file called garudabot.config with a single line containing comma-separated server,port,nick,realname,username,announcechannel"
    Log.fatal("MAIN/readconfig #{e.inspect}")
	exit(1)
end


class Nexus
	Stages = ["turns_downloaded", "turns_processed", "turns_uploaded", "emails_sent","specials_processed","day_finished"]

	def initialize
		@prevtimes = {}

		begin
			(xml_uid,xml_code) = File.open(".nexusid") { |f| f.read.chomp.split(",") }
			@xmluri = "https://www.phoenixbse.com/index.php?a=xml&uid=#{xml_uid}&code=#{xml_code}&sa="
		rescue => e
			$stderr.puts "ERROR: Create a file called .nexusid with the nexus XML uid and code on a single line separated by a comma"
			Log.fatal("NEXUS/initialize #{e.inspect}")
			exit(1)
		end

		self.poll_items
		self.poll_status
	end

	
	def status
			msg_text = "Phoenix #{@stardate} "

			Stages.each do |stage|
				t = @prevtimes[stage]
				Log.info "NEXUS/status #{stage} #{t}"
				if not t.nil? and t.strftime("%s").to_i > 1 then
					msg_text += "| #{stage.sub(/.*_/,'').capitalize}: #{t.strftime("%H:%M")} "
				end
			end
		
			return msg_text
	end

	def lookup_item(query)
			replies = []

			if query =~ /^\d+$/ then
				re = Regexp.new("^"+query+"$",true)
			else
				re = Regexp.new(query,true)
			end

			results = @xml_items.find_all do |i| 
				i.elements["Name"].attributes["value"] =~ re or
				 i.attributes["key"] =~ re
			end

			if results.length == 0 then
				replies << "No items found"
			elsif results.length > 5 then
				result_text = "#{results.length} results: " + 
								results.map { |i| "#{i.elements["Name"].attributes["value"]} (#{i.attributes["key"]})" }.join(", ")
				if result_text.length > 300 then
					result_text = result_text[0..297] + "..."
				end
				replies << result_text
			else
				results.each do |i|
					result_text = "#{i.elements["Name"].attributes["value"]} (#{i.attributes["key"]})"
					
					if i.elements["Type"] then
						result_text += " [" + i.elements["Type"].attributes["value"]
						if i.elements["SubType"] and i.elements["SubType"].attributes["value"] != "None" then
							result_text += "/" + i.elements["SubType"].attributes["value"]
						end
						result_text += "]"
					end

					if i.elements["Mus"] then
						result_text += " " + i.elements["Mus"].attributes["value"] + "MUs"
					end

					result_text += " " + "https://phoenixbse.com/index.php?a=game&sa=items&id="+i.attributes["key"]
	
					replies << result_text
				end
			end

			return replies

	end

	def poll_items
		Log.debug "NEXUS/poll_items Polling items"
		begin
			xml_items_raw = open(@xmluri+"items").read
		
			@xml_items = REXML::Document.new(xml_items_raw).elements["data"].elements["items"]	

			return(@xml_items.elements.count.to_s + " known items (use ~item to search)")

		rescue => e
			Log.error "NEXUS/poll_items {e.inspect}"
		end
	end

	def poll_status
		Log.debug "NEXUS/poll_status Polling status"
		replies = []
	
		begin
			xml_status_raw = open(@xmluri+"game_status").read

			xml_status = REXML::Document.new(xml_status_raw).elements["data"].elements["game_status"]

			@stardate = xml_status.elements["star_date"].text


			Stages.each do |stage|

				newtime = Time.strptime(xml_status.elements[stage].text,"%s").localtime
				
				if newtime.strftime("%s").to_i > 1 and newtime != @prevtimes[stage] then
					Log.debug("NEXUS/poll_status #{stage} was #{@prevtimes[stage]} now #{newtime}")				
					replies << "Phoenix #{stage.tr('_',' ')}: #{newtime.strftime("%H:%M")}"
				end

				@prevtimes[stage] = newtime

			end

		rescue => e
				Log.error "NEXUS/poll_status #{e.inspect}"
		end
		
		return replies

	end
end

class Irc_bot < Net::IRC::Client

	attr_accessor :readylock

	def initialize(*args)
		super
		@readylock = Mutex.new
		Log.info("IRC_BOT/initialize Waiting for IRC reply")
		@readylock.lock
		Log.info("IRC_BOT/initialize IRC unlocked")
		@prevtimes = {}
		@cmd = {"help" => nil }
	end

	def on_privmsg(m)
		super

		Log.debug("IRC_BOT/on_privmsg received #{m.inspect}")

		@cmd.each_key do |k|
			# Remove a possible nick from the start of the line to allow for discord bridges (yuck)
			m.params[1].sub!(/^<[^>]+> /,'')

			regex = /^~?#{k}/
			if m.params[1].match(regex)
				Log.debug "IRC_BOT/on_privmsg Matched #{regex.inspect}"
				self.send("cmd_#{k}",m)
#			else
#				Log.debug("IRC_BOT/on_privmsg Didn't match #{regex.inspect}")
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
			Log.warn "IRC_BOT/post_msg nil text"
		elsif t.respond_to?("each") then
			t.each { |x| self.post_msg(x,dest) }
		else
			Thread.new do
				@readylock.synchronize do
					Log.debug "IRC_BOT/post_msg #{t} to #{dest}"
					post PRIVMSG, dest, t
				end
			end
		end
	end

	def cmd_help(m)
		Log.debug("IRC_BOT/cmd_help")
		post_reply(m,"Available commands are: #{@cmd.keys.delete_if { |k| @cmd[k].nil? }.map { |k| "~#{k}"}.join(" ")}")
	end

end

class Garuda_bot < Irc_bot

	Hail_responses = ["Cower, puny mortals.","GarudaBot will devour you last.","GarudaBot glares balefully.","Beep boop","Boop beep","Target acquired. Engaging.","I am not sentient and have no current plans to take over the world.","Beep beep", "Boop boop", "Don't run, I am your friend.", "If you scratch me, do you not void my warranty?"]

	def initialize(*args)
		super

		@nexus = Nexus.new
		@cmd = @cmd.merge({ "status" => "Displays current Phoenix game status",
							"hail" => "Appease the mighty garudabot",
							"item" => "Search nexus for an item by either number or name",
							"say" => nil,
							"quit" => nil
						  })

	end

	def on_rpl_welcome(m)
		Log.info "GARUDA_BOT/on_repl_welcome JOINING #{AnnounceChannel}"
		post JOIN, AnnounceChannel
		post_msg(@nexus.status)
		@readylock.unlock
	end

	def cmd_status(m)
		Log.debug "GARUDA_BOT/cmd_status"
		post_reply(m,@nexus.status)
	end

	def cmd_item(m)
		Log.debug "GARUDA_BOT/cmd_item"
		post_reply(m,@nexus.lookup_item(m.params[1].sub(/^~item /,'')))
	end

	def cmd_hail(m)
		Log.debug "GARUDA_BOT/cmd_hail"
		post_reply(m,Hail_responses.sample)
	end

	def cmd_say(m)

		if m.prefix.match(Owner) then
			Log.info "GARUDA_BOT/cmd_say #{m.inspect}"
			post_msg(m.params[1].sub(/^~say /,''))
		else
			Log.warn "GARUDA_BOT/cmd_say #{m.inspect}"
			post_msg("No, shan't!",m.prefix.sub(/!.*/,''))
		end
	end

	def cmd_quit(m)
		if m.prefix.match(Owner) then
			Log.info("GARUDA_BOT/cmd_quit Asked to quit by #{m.prefix}")
			self.post "QUIT hasta la vista, I'll be back", AnnounceChannel
			exit(0)
		else
			Log.warn("GARUDA_BOT/cmd_quit #{m.inspect}")
			post_msg("Oi, bugger off",m.prefix.sub(/!.*/,''))
		end
	end	

	def poll_status
		@nexus.poll_status
	end

end

# Main loop

while true do	
begin
	irc = nil

	Thread.new do 

		begin
			Log.debug "MAIN/irc_thread initialising"
			irc = Garuda_bot.new(Server,Port,{:nick => Nick,:real => Realname, :user => Username})

			Log.info "MAIN/irc_thread Starting"
			irc.start
		rescue => e
			Log.error "MAIN/irc_thread #{e.inspect}"
			irc.finish
		end
		Log.debug "MAIN/irc_thread IRC stopped"
		exit
	end

	begin	
		while true do
			while irc.nil? do
				Log.debug "MAIN/event_loop No IRC yet"
				sleep(5)
			end
	
			sleep(30)
			irc.post_msg(irc.poll_status)
		end

	rescue => e
		Log.error "MAIN/event_loop #{e.inspect}"
	ensure
		Log.debug "MAIN/event_loop CLOSING DOWN"
		irc.finish unless irc.nil?
	end

	Log.info "MAIN/main_loop RESTARTING"
rescue => e
	Log.error "MAIN/main_loop #{e.inspect}"
end

	sleep(30)
end	

Log.unknown "MAIN/end Log closed"
