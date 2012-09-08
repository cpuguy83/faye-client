module FayeClient
	# extend FayeClient in your class to use
	# the "start" method spins off the EM instance with the Faye client to it's own thread
	# You can access the the client itself or the thread using the class accessor methods "messaging_client" and "messaging_client_thread", respectively
	# You must specify a :messaging_server_url and :messaging_channels using the available class accessors
	# You should also supply a default_channel_handler_class_name and a default_channel_handler_method or it will default to the built-in handler, which is useless
	# Alternatively (or in addition to), you can specify a Hash for your channel which would specify which class/method to use to handler the incoming message
	# Example:
	#
	# 	class MyClientClass
	# 		extend FayeClient
	# 		self.messaging_server_url = 'http://myserver/faye'
	# 		self.messaging_channels = ['/foo', '/bar', {name: '/foofoo', handler_class_name: FooFooHandlerClass, handler_method_name: 'foofoo_handler_method' }]
	# 		self.default_channel_handler_class_name = 'MyDefaultHandlerClass'
	# 		self.default_channel_handler_method = 'my_default_handler_method'
	# 	end
	#
	# 	MyClient.start
	#
	# Channels for '/foo' and '/bar' in the above example will use the default class/method combo specified
	# Channel '/foofoo' will use the specified class/method, assuming they are defined

	 

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

	# Publish a :message to a :channel
	def publish(options)
		raise 'NoChannelProvided' unless options[:channel]
		raise 'NoMessageProvided' unless options[:message]
		messaging_client.publish(options[:channel], options[:message])
	end

	# Stop the running client
	def stop
		raise "NotRunning" if !running?
		self.messaging_client.disconnect
		self.messaging_client_thread.kill
	end

	# Restart the running client
	def restart
		stop
		start
	end


	# Is the client running?
	def running?
		if self.messaging_client and self.messaging_client.state == :CONNECTED
			true
		else
			false
		end
	end

	# Set the handler class/method to be used for a given channel
	def get_channel_handler(channel)
		if channel.is_a? String
			parsed_channel_name = channel.gsub(/^\//, '').gsub('/','::')
			handler = get_channel_handler_for_string(parsed_channel_name)
			handler[:name] = channel
		elsif channel.is_a? Hash
			# Can provide a Hash to get full customization of handler names/methods
			handler = get_channel_handler_for_hash(channel)
			handler[:name] = channel[:name]
		else
			raise TypeError, 'Channel Must be a String or a Hash'
		end

		handler
	end

	# If just a string is provided for a channel
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