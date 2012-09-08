module FayeClient
	class DefaultChannelHandler
		include Sidekiq::Worker
		sidekiq_options :queue => :messaging

		def perform(message)
			message
		end
	end
end