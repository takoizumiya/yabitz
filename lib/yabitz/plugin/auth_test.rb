# -*- coding: utf-8 -*-

module Yabitz::Plugin
  module TestAuthenticate
    def self.plugin_type
      :auth
    end
    def self.plugin_priority
      1
    end
    
    TesterFile = File.expand_path(File.dirname(__FILE__) + "/../../../.tester_usernames")

    # MUST returns full_name (as String)
    # if authentication failed, return nil
    def self.authenticate(username, password, sourceip=nil)
      names = []
      if File.exist?(TesterFile)
        names = open(TesterFile){|f|
          f.readlines.map(&:chomp)
        }
      end
      if Yabitz.config().name == :development and (username =~ /\Atest/ or names.include?(username))
        return username
      end
      nil
    end
  end
end
