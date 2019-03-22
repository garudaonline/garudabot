

class Item < Hash

	def to_s
		"#{self["Name"]} (#{self["Number"]})"
	end

	def description
		s = self.to_s

		if self["Type"] then 
			if self["Subtype"] then
				s += " [" + self["Type"] + "/" + self["Subtype"] + "]"
			else
				s += " [" + self["Type"] + "]"
			end
		end

		if self["Mus"] then
			s += " " + self["Mus"] + "MUs"
		end
	end


end
