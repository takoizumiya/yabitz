# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
  ### 一覧系 ###

  # サービス一覧 ( /ybz/service/list が別途後ろの方に作成してあるので注意。現状中身はいっしょ。)
  get '/ybz/services' do
    authorized?
    @services = Yabitz::Model::Service.all.sort
    Stratum.preload(@services, Yabitz::Model::Service)
    @page_title = "サービス"
    haml :services
  end

  get %r!/ybz/service/diff/(\d+)! do |oid|
    authorized?
    @service = Yabitz::Model::Service.get(oid.to_i)
    pass unless @service

    @host_record_pairs = nil
    startdate = request.params['from']
    enddate = request.params['to']
    unless startdate and startdate =~ %r!\A\d{4}[-/]?\d{2}[-/]?\d{2}\Z! and enddate and enddate =~ %r!\A\d{4}[-/]?\d{2}[-/]?\d{2}\Z!
      @hide_selectionbox = true
      return haml :service_diff
    end

    startdate =~ %r!\A(\d{4})[-/]?(\d{2})[-/]?(\d{2})\Z!
    startdate = $1 + '-' + $2 + '-' + $3
    enddate =~ %r!\A(\d{4})[-/]?(\d{2})[-/]?(\d{2})\Z!
    enddate = $1 + '-' + $2 + '-' + $3

    @first_timestamp = startdate + ' 00:00:00'
    @last_timestamp = enddate + ' 23:59:59'


    pre_oids = Yabitz::Model::Host.query(:service => @service, :before => @first_timestamp, :oidonly => true)
    post_oids = Yabitz::Model::Host.query(:service => @service, :before => @last_timestamp, :oidonly => true)
    oids = (pre_oids + post_oids).uniq

    pre_hosts_hash = Hash[*(Yabitz::Model::Host.get(oids, :before => @first_timestamp, :force_all => true).map{|h| [h.oid, h]}.flatten)]
    post_hosts_hash = Hash[*(Yabitz::Model::Host.get(oids, :before => @last_timestamp, :force_all => true).map{|h| [h.oid, h]}.flatten)]
    pre_hosts = oids.map{|i| pre_hosts_hash[i]}
    post_hosts = oids.map{|i| post_hosts_hash[i]}

    @host_record_pairs = [post_hosts, pre_hosts].transpose.select{|a,b| (not a and b) or (a and not b) or (a and b and a.id != b.id)}
    @hide_selectionbox = true
    haml :service_diff
  end

  get %r!/ybz/service/list(\.json)?! do |ctype|
    authorized?
    @services = Yabitz::Model::Service.all
    Stratum.preload(@services, Yabitz::Model::Service)
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @services.to_json
    else
      @services.sort!
      @page_title = "サービス"
      haml :services
    end
  end

  post '/ybz/service/create' do
    admin_protected!
    if Yabitz::Model::Service.query(:name => request.params['name'].strip, :count => true) > 0
      raise Yabitz::DuplicationError
    end
    service = Yabitz::Model::Service.new
    service.name = request.params['name'].strip
    service.content = Yabitz::Model::Content.get(request.params['content'].to_i)
    service.mladdress = request.params['mladdress'].strip
    service.save
    redirect '/ybz/service/list'
  end

  get %r!/ybz/service/(\d+)(\.json|\.ajax|\.tr\.ajax)?! do |oid, ctype|
    authorized?
    @srv = Yabitz::Model::Service.get(oid.to_i)
    pass unless @srv # object not found -> HTTP 404

    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @srv.to_json
    when '.ajax' then haml :service_parts, :layout => false
    when '.tr.ajax' then haml :service, :layout => false, :locals => {:service => @srv}
    else
      @page_title = "サービス: #{@srv.name}"
      @service_single = true
      @services = [@srv]
      Stratum.preload(@services, Yabitz::Model::Service)
      haml :services
    end
  end

  post %r!/ybz/service/(\d+)! do |oid|
    protected!

    Stratum.transaction do |conn|
      @srv = Yabitz::Model::Service.get(oid.to_i)
      pass unless @srv
      if request.params['target_id']
        unless request.params['target_id'].to_i == @srv.id
          raise Stratum::ConcurrentUpdateError
        end
      end

      field = request.params['field'].to_sym
      unless @isadmin or field == :contact or field == :notes
        halt HTTP_STATUS_FORBIDDEN, "not authorized"
      end

      @srv.send(field.to_s + '=', @srv.map_value(field, request))
      @srv.save

      if field == :contact
        Yabitz::Plugin.get(:handler_hook).each do |plugin|
          if plugin.respond_to?(:contact_update)
            plugin.contact_update(@srv.contact)
          end
        end
      end
    end
    "ok"
  end
  # delete '/ybz/service/:oid' #TODO

  post '/ybz/service/alter-prepare/:ope/:oid' do
    admin_protected!
    oid = params[:oid].to_i
    service = Yabitz::Model::Service.get(oid)
    unless service
      halt HTTP_STATUS_CONFLICT, "指定されたサービスが見付かりません<br />ページを更新してやりなおしてください"
    end

    case params[:ope]
    when 'change_content'
      content_select_tag_template = <<EOT
%div 変更先コンテンツを選択してください
%div
  %select{:name => "content"}
    - Yabitz::Model::Content.all.sort.each do |content|
      %option{:value => content.oid}&= content.to_s
EOT
      haml content_select_tag_template, :layout => false
    when 'delete_records'
      if Yabitz::Model::Host.query(:service => service, :count => true) > 0
        halt HTTP_STATUS_NOT_ACCEPTABLE, "該当サービスに所属しているホストがあるため削除できません"
      end
      "選択されたサービス #{service.name} のデータを削除して本当にいいですか？"
    else
      pass
    end
  end

  post '/ybz/service/alter-execute/:ope/:oid' do
    admin_protected!
    oid = params[:oid].to_i
    service = Yabitz::Model::Service.get(oid)
    unless service
      halt HTTP_STATUS_CONFLICT, "指定されたサービスが見付かりません<br />ページを更新してやりなおしてください"
    end

    case params[:ope]
    when 'change_content'
      content = Yabitz::Model::Content.get(params[:content].to_i)
      halt HTTP_STATUS_CONFLICT, "指定されたサービスが見付かりませんでした" unless content

      service.content = content
      service.save
      "完了： サービス #{service.name} の #{content.to_s} への変更"
    when 'delete_records'
      servicename = service.name
      Stratum.transaction do |conn|
        if Yabitz::Model::Host.query(:service => service, :count => true) > 0
          halt HTTP_STATUS_NOT_ACCEPTABLE, "該当サービスに所属しているホストがあるため削除できません"
        end

        content = service.content
        content.services_by_id = content.services_by_id - [service.oid]
        content.save

        service.urls = []
        service.contact = nil
        service.save()
        
        service.remove()
      end
      "完了： サービス #{servicename} の削除"
    else
      pass
    end
  end
end
