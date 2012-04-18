# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
  get %r!/ybz/content/list(\.json)?! do |ctype|
    authorized?
    @contents = Yabitz::Model::Content.all.sort
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @contents.to_json
    else
      @page_title = "コンテンツ一覧"
      haml :content_list
    end
  end

  post %r!/ybz/content/create! do
    admin_protected!
    if Yabitz::Model::Content.query(:name => request.params['name'].strip, :count => true) > 0
      raise Yabitz::DuplicationError
    end
    content = Yabitz::Model::Content.new()
    content.name = request.params['name'].strip
    content.charging = request.params['charging'].strip
    content.code = request.params['code'].strip
    content.dept = Yabitz::Model::Dept.get(request.params['dept'].strip.to_i)
    content.save
    redirect '/ybz/content/list'
  end
  get %r!/ybz/content/(\d+)(\.json|\.tr\.ajax|\.ajax)?! do |oid, ctype|
    authorized?
    @content = Yabitz::Model::Content.get(oid.to_i)
    pass unless @content # object not found -> HTTP 404

    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @content.to_json
    when '.ajax' then haml :content_parts, :layout => false
    when '.tr.ajax' then haml :content, :layout => false, :locals => {:content => @content}
    else
      Stratum.preload([@content], Yabitz::Model::Content)
      @hide_detailbox = true
      @page_title = "コンテンツ: #{@content.name}"
      haml :content_page, :locals => {:cond => @page_title}
    end
  end
  post %r!/ybz/content/(\d+)! do |oid|
    admin_protected!

    Stratum.transaction do |conn|
      @content = Yabitz::Model::Content.get(oid.to_i)
      pass unless @content
      if request.params['target_id']
        unless request.params['target_id'].to_i == @content.id
          raise Stratum::ConcurrentUpdateError
        end
      end
      field = request.params['field'].to_sym
      @content.send(field.to_s + '=', @content.map_value(field, request))
      @content.save
    end
    
    "ok"
  end
  # delete '/ybz/content/:oid' #TODO
  
  post '/ybz/content/alter-prepare/:ope/:oid' do
    admin_protected!
    oid = params[:oid].to_i
    content = Yabitz::Model::Content.get(oid)
    unless content
      halt HTTP_STATUS_CONFLICT, "指定されたコンテンツが見付かりません<br />ページを更新してやりなおしてください"
    end

    case params[:ope]
    when 'change_dept'
      dept_select_tag_template = <<EOT
%div 変更先を選択してください
%div
  %select{:name => "dept"}
    - Yabitz::Model::Dept.all.sort.each do |dept|
      %option{:value => dept.oid}&= dept.to_s
EOT
      haml dept_select_tag_template, :layout => false
    when 'delete_records'
      if Yabitz::Model::Service.query(:content => content, :count => true) > 0
        halt HTTP_STATUS_NOT_ACCEPTABLE, "該当コンテンツに所属しているサービスがあるため削除できません"
      end
      "選択されたコンテンツ #{content.name} のデータを削除して本当にいいですか？"
    else
      pass
    end
  end

  post '/ybz/content/alter-execute/:ope/:oid' do
    admin_protected!
    oid = params[:oid].to_i
    content = Yabitz::Model::Content.get(oid)
    unless content
      halt HTTP_STATUS_CONFLICT, "指定されたコンテンツが見付かりません<br />ページを更新してやりなおしてください"
    end

    case params[:ope]
    when 'change_dept'
      dept = Yabitz::Model::Dept.get(params[:dept].to_i)
      halt HTTP_STATUS_CONFLICT, "指定された対象が見付かりませんでした" unless dept

      content.dept = dept
      content.save
      "完了： コンテンツ #{content.name} の #{dept.to_s} への変更"
    when 'delete_records'
      contentname = content.name
      Stratum.transaction do |conn|
        if Yabitz::Model::Service.query(:content => content, :count => true) > 0
          halt HTTP_STATUS_NOT_ACCEPTABLE, "該当コンテンツに所属しているサービスがあるため削除できません"
        end

        content.services = []
        content.save()

        content.remove()
      end
      "完了： コンテンツ #{contentname} の削除"
    else
      pass
    end
  end
end
