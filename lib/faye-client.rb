require 'rubygems'
require 'eventmachine'
require 'Faye' unless defined? Faye
require 'sidekiq'
require 'active_support'
require 'require_all'
require_rel 'faye-client'