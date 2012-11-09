# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
  get %r!/ybz/hwinfo/list(\.ajax|\.json)?! do |ctype|
    authorized?
    @hwinfos = Yabitz::Model::HwInformation.all
    # Stratum.preload(@hwinfos, Yabitz::Model::Host) # has no ref/reflist field.
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @hwinfos.to_json
    else
      @page_title = "ハードウェア情報一覧"
      @hwinfos.sort!
      haml :hwinfo_list
    end
  end

  get %r!/ybz/hwinfo/(\d+)(\.tr\.ajax|\.ajax)! do |oid,ctype|
    authorized?
    @hwinfo = Yabitz::Model::HwInformation.get(oid.to_i)
    pass unless @hwinfo
    case ctype
    when '.ajax'
      haml :hwinfo_parts, :layout => false
    when '.tr.ajax'
      haml :hwinfo, :layout => false, :locals => {:hwinfo => @hwinfo}
    else
      pass
    end
  end

  post '/ybz/hwinfo/create' do 
    admin_protected!
    if Yabitz::Model::HwInformation.query(:name => request.params['name'], :count => true) > 0
      raise Yabitz::DuplicationError
    end
    hwinfo = Yabitz::Model::HwInformation.new()
    hwinfo.name = request.params['name'].strip
    hwinfo.units = request.params['units'].strip
    hwinfo.calcunits = (request.params['calcunits'].strip == "" ? hwinfo.units_calculated : request.params['calcunits'].strip)
    hwinfo.virtualized = (request.params['virtualized'] and request.params['virtualized'].strip == 'on')

    if not hwinfo.virtualized and hwinfo.calcunits.to_f == 0.0
      raise Yabitz::InconsistentDataError.new("ユニット数なしは仮想化サーバの場合のみ可能です")
    end
    hwinfo.save
    
    "ok"
  end
  
  post %r!/ybz/hwinfo/(\d+)! do |oid|
    protected!

    Stratum.transaction do |conn|
      @hwinfo = Yabitz::Model::HwInformation.get(oid.to_i)
      pass unless @hwinfo
      if request.params['target_id']
        unless request.params['target_id'].to_i == @hwinfo.id
          raise Stratum::ConcurrentUpdateError
        end
      end

      field = request.params['field'].to_sym
      @hwinfo.send(field.to_s + '=', @hwinfo.map_value(field, request))
      @hwinfo.save
    end
    "ok"
  end

  # delete '/ybz/hwinfo/:oid' #TODO

end
