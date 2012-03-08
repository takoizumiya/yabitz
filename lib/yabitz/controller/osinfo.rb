# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
  ### OSおよびハードウェア情報
  get %r!/ybz/osinfo/list(.json)?! do |ctype|
    authorized?
    @osinfos = Yabitz::Model::OSInformation.all
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @osinfos.to_json
    else
      @page_title = "OS情報一覧"
      @osinfos.sort!
      haml :osinfo_list
    end
  end

  post '/ybz/osinfo/create' do
    admin_protected!

    if Yabitz::Model::OSInformation.query(:name => request.params['name'], :count => true) > 0
      raise Yabitz::DuplicationError
    end
    osinfo = Yabitz::Model::OSInformation.new()
    osinfo.name = request.params['name'].strip
    osinfo.save
    
    "ok"
  end

  # delete '/ybz/osinfo/:oid' #TODO

end
