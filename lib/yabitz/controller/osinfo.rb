# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
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

  get %r!/ybz/osinfo/(\d+)(\.tr\.ajax|\.ajax)! do |oid,ctype|
    authorized?
    @osinfo = Yabitz::Model::OSInformation.get(oid.to_i)
    pass unless @osinfo
    case ctype
    when '.ajax'
      haml :osinfo_parts, :layout => false
    when '.tr.ajax'
      haml :osinfo, :layout => false, :locals => {:osinfo => @osinfo}
    else
      pass
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

  post '/ybz/osinfo/alter-prepare/:ope/:oid' do
    admin_protected!
    oid = params[:oid].to_i
    osinfo = Yabitz::Model::OSInformation.get(oid)
    unless osinfo
      halt HTTP_STATUS_CONFLICT, "指定されたOS情報が見付かりません<br />ページを更新してやりなおしてください"
    end

    case params[:ope]
    when 'delete_records'
      "選択されたOS情報 #{osinfo.name} のデータを削除して本当にいいですか？"
    else
      pass
    end
  end

  post '/ybz/osinfo/alter-execute/:ope/:oid' do
    admin_protected!
    oid = params[:oid].to_i
    osinfo = Yabitz::Model::OSInformation.get(oid)
    unless osinfo
      halt HTTP_STATUS_CONFLICT, "指定されたOS情報が見付かりません<br />ページを更新してやりなおしてください"
    end

    case params[:ope]
    when 'delete_records'
      osinfoname = osinfo.name
      Stratum.transaction do |conn|
        osinfo.remove()
      end
      "完了： OS情報 #{osinfoname} の削除"
    else
      pass
    end
  end
end
