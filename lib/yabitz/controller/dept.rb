# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
  ### 部署等 (post/put/deleteはすべてadmin認証要求)
  get %r!/ybz/dept/list(\.json)?! do |ctype|
    authorized?
    @depts = Yabitz::Model::Dept.all.sort
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @depts.to_json
    else
      @page_title = "部署一覧"
      haml :dept_list
    end
  end

  post '/ybz/dept/create' do
    admin_protected!
    if Yabitz::Model::Dept.query(:name => request.params['name'].strip, :count => true) > 0
      raise Yabitz::DuplicationError
    end
    dept = Yabitz::Model::Dept.new()
    dept.name = request.params['name'].strip
    dept.save
    "ok"
  end
  get %r!/ybz/dept/(\d+)(\.json|\.tr\.ajax|\.ajax)?! do |oid, ctype|
    authorized?
    
    @dept = Yabitz::Model::Dept.get(oid.to_i)
    pass unless @dept # object not found -> 404

    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @dept.to_json
    when '.ajax' then haml :dept_parts, :layout => false
    when '.tr.ajax' then haml :dept, :layout => false, :locals => {:dept => @dept}
    else
      @hide_detailbox = true
      @page_title = "部署: #{@dept.name}"
      haml :dept_page, :locals => {:cond => @page_title}
    end
  end

  post %r!/ybz/dept/(\d+)! do |oid|
    admin_protected!

    Stratum.transaction do |conn|
      @dept = Yabitz::Model::Dept.get(oid.to_i)
      pass unless @dept
      if request.params['target_id']
        unless request.params['target_id'].to_i == @dept.id
          raise Stratum::ConcurrentUpdateError
        end
      end
      field = request.params['field'].to_sym
      @dept.send(field.to_s + '=', @dept.map_value(field, request))
      @dept.save
    end
    
    "ok"
  end
  # delete '/ybz/dept/:oid' #TODO

  post '/ybz/dept/alter-prepare/:ope/:oid' do
    admin_protected!
    oid = params[:oid].to_i
    dept = Yabitz::Model::Dept.get(oid)
    unless dept
      halt HTTP_STATUS_CONFLICT, "指定された対象が見付かりません<br />ページを更新してやりなおしてください"
    end

    case params[:ope]
    when 'delete_records'
      if Yabitz::Model::Content.query(:dept => dept, :count => true) > 0
        halt HTTP_STATUS_NOT_ACCEPTABLE, "指定された対象に所属しているコンテンツがあるため削除できません"
      end
      "#{dept.name} のデータを削除して本当にいいですか？"
    else
      pass
    end
  end

  post '/ybz/dept/alter-execute/:ope/:oid' do
    admin_protected!
    oid = params[:oid].to_i
    dept = Yabitz::Model::Dept.get(oid)
    unless dept
      halt HTTP_STATUS_CONFLICT, "指定された対象が見付かりません<br />ページを更新してやりなおしてください"
    end

    case params[:ope]
    when 'delete_records'
      deptname = dept.name
      Stratum.transaction do |conn|
        if Yabitz::Model::Content.query(:dept => dept, :count => true) > 0
          halt HTTP_STATUS_NOT_ACCEPTABLE, "指定された対象に所属しているコンテンツがあるため削除できません"
        end

        dept.remove()
      end
      "完了： #{deptname} の削除"
    else
      pass
    end
  end
end
