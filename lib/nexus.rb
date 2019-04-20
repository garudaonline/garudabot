#!/usr/bin/ruby

require "open-uri"
require "rexml/document"
require "logger"
require_relative "item"

class Nexus
	Stages = ["turns_downloaded", "turns_processed", "turns_uploaded", "emails_sent","specials_processed","day_finished"]

	attr_reader :stardate,:items

	def initialize(uid=nil,code=nil,log=Logger.new(STDOUT))
		@prevtimes = {}
		@log = log
		@xmluri = "https://www.phoenixbse.com/index.php?a=xml&uid=#{uid}&code=#{code}&sa="
		@items = []
	end

	def self.from_file(fname,log=Logger.new(STDOUT))
        (uid,code) = File.open(".nexusid") { |f| f.read.chomp.split(",") }

		self.new(uid,code,log)
    end


	
	def current_status
			status = []

			Stages.each do |stage|
				t = @prevtimes[stage]
				if not t.nil? and t.strftime("%s").to_i > 1 then
					status << [stage.tr('_',' ').capitalize,t]
				end
			end
			@log.info("NEXUS/current_status #{status.inspect}")
			return status
	end

	def get_items
		@log.debug "NEXUS/get_items Polling items"
		begin

			xml_items_raw = open(@xmluri+"items").read

			@items = REXML::Document.new(xml_items_raw).elements["data"].elements["items"].map do |x|
				i = Item.new
				x.elements.each do |k|
					i[k.name] = k.attributes["value"]
				end
				i
			end

		rescue => e
			@log.error "NEXUS/get_items #{e.inspect}"
		end

		@items
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
					changes << [stage.tr('_',' ').capitalize,newtime]
				end

				@prevtimes[stage] = newtime

			end

		rescue => e
				@log.error "NEXUS/get_status #{e.inspect}"
		end
		
		return changes

	end
end
