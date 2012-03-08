# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
  ### 各リソースの状態表示、および管理(holdなど)
  #TODO serviceurl

  # get '/ybz/dnsname/:oid' #TODO
  # get '/ybz/dnsname/retrospect/:oid' #TODO
  # get '/ybz/dnsname/floating' #TODO
  # delete '/ybz/dnsname/:oid' #TODO
end
