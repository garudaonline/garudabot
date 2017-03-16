#!/usr/bin/ruby

require "net/irc"
require "open-uri"
require "rexml/document"
require "digest/md5"



Hail_responses = ["Cower, puny mortals.","GarudaBot will devour you last.","GarudaBot glares balefully.","Beep boop","Boop beep","Target acquired. Engaging.","I am not sentient and have no current plans to take over the world.","Beep beep", "Boop boop", "Don't run, I am your friend.", "If you scratch me, do you not void my warranty?"]

Stages = ["turns_downloaded", "turns_processed", "turns_uploaded", "emails_sent","specials_processed","day_finished"]

def logmsg(t)
	$stderr.puts "#{Time.now} #{t}"
end

begin
	(Xml_uid,Xml_code) = File.open(".nexusid") { |f| f.read.chomp.split(",") }
rescue 
	logmsg "Create a file called .nexusid with the nexus XML uid and code on a single line separated by a comma"
	exit(1)
end

Xmluri = "http://www.phoenixbse.com/index.php?a=xml&uid=#{Xml_uid}&code=#{Xml_code}&sa="

begin
	(Server,Port,Nick,Realname,Username,AnnounceChannel) = File.open("garudabot.config") { |f| f.read.chomp.split(",") }
rescue
	logmsg "Create a file called garudabot.config with a single line containing comma-separated server,port,nick,realname,username,announcechannel"
	exit(1)
end



class GarudaBot < Net::IRC::Client

	attr_accessor :readylock

	def initialize(*args)
		super
		@readylock = Mutex.new
		@readylock.lock
		@prevtimes = {}
	end

	def on_privmsg(m)
		super
		if m.params[0] == Nick then
			dest = m.prefix.sub(/!.*/,'')
		else
			dest = m.params[0]
		end

		if m.params[1] =~ /^~status/ then
			self.postmsg(self.to_s,dest)
		elsif m.params[1] =~ /hail garuda/i then
			self.postmsg(Hail_responses.sample,dest)
		elsif m.params[1] =~ /^~item/i then
			self.lookupitem(m.params[1].sub(/^~item ?/,''),dest)
		end
	end

	def lookupitem(query,dest=AnnounceChannel)
			@readylock.synchronize { }

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
				self.postmsg("No items found",dest)
			elsif results.length > 5 then
				result_text = "#{results.length} results: " + 
								results.map { |i| "#{i.elements["Name"].attributes["value"]} (#{i.attributes["key"]})" }.join(", ")
				if result_text.length > 300 then
					result_text = result_text[0..297] + "..."
				end
				self.postmsg(result_text,dest)
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

					result_text += " " + "http://phoenixbse.com/index.php?a=game&sa=items&id="+i.attributes["key"]
	
					self.postmsg(result_text,dest)
				end
			end

	end

	def to_s
			msg_text = "Phoenix #{@stardate} "

			Stages.each do |stage|
				t = @prevtimes[stage]
				logmsg "#{stage} #{t}"
				if t.strftime("%s").to_i > 1 then
					msg_text += "| #{stage.sub(/.*_/,'').capitalize}: #{t.strftime("%H:%M")} "
				end
			end
		
			return msg_text
	end

	def on_rpl_welcome(m)
		logmsg "JOINING #{AnnounceChannel}"
		post JOIN, AnnounceChannel
		self.poll_status(true)
		@readylock.unlock
	end

	def postmsg(t,dest=AnnounceChannel)	
		@readylock.synchronize {
			logmsg "POSTING #{t} to #{dest}"
			post PRIVMSG, dest, t
		}
	end

	def poll_status(silent=false)
		begin
			xml_status = open(Xmluri+"game_status") do |f| 
				REXML::Document.new(f.read).elements["data"].elements["game_status"]
			end
			@xml_items = open(Xmluri+"items") do |f| 
				REXML::Document.new(f.read).elements["data"].elements["items"]
			end	
		
		rescue Exception <= e
			logmsg "EXCEPTION IN XML READ: #{e.inspect}"
			logmsg e.backtrace.join("\n")
		end

		@stardate = xml_status.elements["star_date"].text

		Stages.each do |stage|
			newtime = DateTime.strptime(xml_status.elements[stage].text,"%s")
			if not silent and newtime.strftime("%s").to_i > 1 and newtime != @prevtimes[stage] then
				if stage == "day_finished" then
					@prevtimes[stage] = newtime
					logmsg("Day finished - #{self.to_s}")
					self.postmsg(self.to_s)
					#stages.map { |s| @prevtimes[s] }.join(",")
				else
					self.postmsg("Phoenix #{stage.tr('_',' ')}: #{newtime.strftime("%H:%M")}")
					logmsg("#{stage} was #{@prevtimes[stage]} now #{newtime}")
				end
			end
			@prevtimes[stage] = newtime
		end

		logmsg("Finishing poll")
	end

end


while true do	

	irc = nil

	Thread.new do 
		irc = GarudaBot.new(Server,Port,{:nick => Nick,:real => Realname, :user => Username})
		begin
			logmsg "STARTING IRC"
			irc.start
		rescue => e
			logmsg "EXCEPTION IN IRC #{e.inspect}"
			irc.finish
		end
		logmsg "IRC STOPPED"
	end


	begin	
		while true do
			while irc.nil? do
				sleep(5)
			end
	
			sleep(60)
			irc.poll_status
		end

	rescue Exception => e
		logmsg "EXCEPTION #{e.inspect}"
		logmsg e.backtrace.join("\n")
	ensure
		logmsg "CLOSING DOWN"
		irc.finish unless irc.nil?
	end

	logmsg "RESTARTING"
	sleep(30)
	
end	
