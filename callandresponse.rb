
class CallAndResponse

	attr_accessor :responses

	def initialize(responses,duration)
		@timeout = nil
		@responsecount = 0
		@responses = Hash.new {|h,k| h[k] = Array.new }.merge(responses)
		@duration = duration
	end

	def call
		if @timeout.nil? or @timeout < Time.now() then
			@responsecount = 1
			@timeout = Time.now() + @duration
			return @responses[1].sample
		else
			@responsecount += 1
			return @responses[@responsecount].sample
		end
	end

end

