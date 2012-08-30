# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
  get %r!/ybz/hostname/lookup(\.json|\.txt)! do |ctype|
    authorized?
    @ip = Yabitz::Model::IPAddress.query(:address => env['REMOTE_ADDR'], :unique => true)

    case ctype
    when '.json'
      pass unless @ip.oid
      response['Content-Type'] = 'application/json'
      @ip.to_json
    when '.txt'
      pass unless @ip.oid
      pass unless @ip.hosts.first
      response['Content-Type'] = 'text/plain'
      @ip.hosts.first.display_name
    else
      pass
    end
  end
end
