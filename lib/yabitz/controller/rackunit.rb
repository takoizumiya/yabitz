# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
  ### rackunit, rack
  get %r!/ybz/rackunit/list(\.json)?! do |ctype|
    authorized?
    @rackunits = Yabitz::Model::RackUnit.all
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @rackunits.to_json
    else
      raise NotImplementedError
    end
  end

  get %r!/ybz/rackunit/(\d+)(\.json)?! do |oid, ctype|
    protected!
    ru = Yabitz::Model::RackUnit.get(oid.to_i)
    pass unless ru

    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      ru.to_json
    else
      unless ru.rack
        ru.rack_set
        ru.save
      end
      redirect "/ybz/rack/#{ru.rack.oid}"
    end
  end

  # get '/ybz/rackunit/retrospect/:oid' #TODO
end
