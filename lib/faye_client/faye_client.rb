module FayeClient
	attr_accessor :messaging_client, :messaging_client_thread, :messaging_server_url, :messaging_channels
	attr_accessor :default_channel_handler_class_name, :default_channel_handler_method


	# Start client
	# Will need to restart client anytime you want to add more channels
	def start
		raise "AlreadyRunning" if running?
		self.messaging_client_thread = Thread.new do
			# Must be run inside EventMachine
			EventMachine.run {
				# Create the actual Faye client
				self.messaging_client = Faye::Client.new(messaging_server_url)
				self.messaging_channels.each do |channel|
					# Channel Handlers provide customization for how to handle a message
					channel_handler = self.get_channel_handler(channel)
					raise 'NoChannelNameProvided' if !channel_handler[:name]
					self.messaging_client.subscribe(channel_handler[:name]) do |message|
						channel_handler[:handler_class_name].send(channel_handler[:handler_method_name], message)
					end
				end
			}
		end
	end

	def stop
		raise "NotRunning" if !running?
		EM.stop
	end

	def restart
		stop
		start
	end


	# Is the client running?
	def running?
		EM.reactor_running?
	end

	def get_channel_handler(channel)
		if channel.is_a? String
			parsed_channel_name = channel.gsub(/^\//, '').gsub('/','::')
			handler = get_channel_handler_for_string(parsed_channel_name)
			handler[:name] = channel
		elsif channel.is_a? Hash
			# Can provide a Hash to get full customization of handler names/methods
			handler = get_channel_handler_for_hash
			handler[:name] = channel[:name]
		else
			raise TypeError, 'Channel Must be a String or a Hash'
		end

		handler
	end

	def get_channel_handler_for_string(channel)
		handler = {}
		# Set handler class
		handler[:handler_class_name] = get_channel_handler_class_name_for_string(channel)
		# Set handler method
		handler[:handler_method_name] = get_default_channel_handler_method_name
		
		handler
	end

	# Build channel handler pointers when hash is provided for channel
	def get_channel_handler_for_hash(channel)
		handler = {}
		if channel[:handler_class_name] 
			# if class name is provided, then you use it
			handler[:handler_class_name] = channel[:handler_class_name]
		else
			# Get default class ifnone is provided
			handler[:handler_class_name] = get_channel_handler_class_name_for_string(channel[:name])
		end

		if channel[:handler_method_name]
			# Get method to use if one is provided
			handler[:handler_method_name] = channel[:handler_method_name]
		else
			# Use default method if none is provided
			handler[:handler_method_name] = get_default_channel_handler_method_name
		end
		return handler
	end

	def get_channel_handler_class_name_for_string(channel)
		# Try to use the channel name to determine the class to use
		class_name = "#{self.class}::#{channel.capitalize}Handler"
		rescue_counter = 0
		begin
		class_name = ActiveSupport::Inflector.constantize class_name if class_name.is_a? String
		rescue NameError
			# If class_name can't be constantized, try to use a default
			if self.default_channel_handler_class_name and rescue_counter == 0
				# Try to use defined default from class
				class_name = self.default_channel_handler_class_name
			else
				# Use gem default if defined default doesn't work
				class_name = "FayeClient::DefaultChannelHandler"
			end
			rescue_counter += 1
			retry if rescue_counter <= 1
			raise 'CannotLoadConstant' if rescue_counter > 1
		end
		return class_name
	end

	def get_default_channel_handler_method_name
		if self.default_channel_handler_method
			# Use defined default if available
			return self.default_channel_handler_method
		else
			# By default we are using Sidekiq Workers to handle incoming messages.
			# 'perform_async' comes from Sidekiq
			return 'perform_async'
		end
	end
end