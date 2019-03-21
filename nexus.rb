#!/usr/bin/ruby

require "open-uri"
require "rexml/document"
require "logger"

class Nexus
	Stages = ["turns_downloaded", "turns_processed", "turns_uploaded", "emails_sent","specials_processed","day_finished"]

	def initialize(log=Logger.new(STDOUT))
		@prevtimes = {}
		@log = log

		begin
			(xml_uid,xml_code) = File.open(".nexusid") { |f| f.read.chomp.split(",") }
			@xmluri = "https://www.phoenixbse.com/index.php?a=xml&uid=#{xml_uid}&code=#{xml_code}&sa="
		rescue => e
			$stderr.puts "ERROR: Create a file called .nexusid with the nexus XML uid and code on a single line separated by a comma"
			@log.fatal("NEXUS/initialize #{e.inspect}")
			exit(1)
		end

		self.get_items
		self.get_status
	end

	
	def status_text
			msg_text = "Phoenix #{@stardate} "

			Stages.each do |stage|
				t = @prevtimes[stage]
				@log.info "NEXUS/status #{stage} #{t}"
				if not t.nil? and t.strftime("%s").to_i > 1 then
					msg_text += "| #{stage.sub(/.*_/,'').capitalize}: #{t.strftime("%H:%M")} "
				end
			end
		
			return msg_text
	end

	def search_item(query)
			replies = []

			@log.info "NEXUS/search_item query [#{query}]"

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

	def get_items
		@log.debug "NEXUS/get_items Polling items"
		begin
			xml_items_raw = open(@xmluri+"items").read
		
			@xml_items = REXML::Document.new(xml_items_raw).elements["data"].elements["items"]	

		rescue => e
			@log.error "NEXUS/get_items {e.inspect}"
		end
	end

	def get_status
		@log.debug "NEXUS/get_status Polling status"
		changes = []
	
		begin
			xml_status_raw = open(@xmluri+"game_status").read

			xml_status = REXML::Document.new(xml_status_raw).elements["data"].elements["game_status"]

			@stardate = xml_status.elements["star_date"].text


			Stages.each do |stage|

				newtime = Time.strptime(xml_status.elements[stage].text,"%s").localtime
				
				if newtime.strftime("%s").to_i > 1 and newtime != @prevtimes[stage] then
					@log.debug("NEXUS/get_status #{stage} was #{@prevtimes[stage]} now #{newtime}")				
					changes << "#{stage.tr('_',' ')}: #{newtime.strftime("%H:%M")}"
				end

				@prevtimes[stage] = newtime

			end

		rescue => e
				@log.error "NEXUS/get_status #{e.inspect}"
		end
		
		return changes

	end
end
