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
  
end
