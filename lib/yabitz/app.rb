# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'
require 'sass'

require 'cgi'
require 'digest/sha1'
require 'json'
require 'ipaddr'

require_relative 'misc/init'

########### ldap try for osx module loading
if Yabitz.config.name == :development and Yabitz.config.ldapparams and not Yabitz.config.ldapparams.empty?
  require 'ldap'
  ldap = Yabitz.config.ldapparams
  LDAP::Conn.new(ldap[0], ldap[1])
end
###########

require_relative './helper'

require_relative 'misc/opetag_generator'
require_relative 'misc/search'
require_relative 'misc/charge'
require_relative 'misc/checker'

class Yabitz::Application < Sinatra::Base
  BASIC_AUTH_REALM = "Yabitz Authentication"
  
  HTTP_STATUS_OK = 200
  HTTP_STATUS_FORBIDDEN = 403
  HTTP_STATUS_NOT_FOUND = 404
  HTTP_STATUS_NOT_ACCEPTABLE = 406
  HTTP_STATUS_CONFLICT = 409

  helpers Sinatra::AuthenticateHelper
  helpers Sinatra::PartialHelper
  helpers Sinatra::HostCategorize
  helpers Sinatra::LinkGenerator
  helpers Sinatra::EscapeHelper
  helpers Sinatra::ValueComparator

  # configure :production do
  # end
  # configure :test do 
  # end

  configure do
    set :public_folder, File.dirname(__FILE__) + '/../../public'
    set :views, File.dirname(__FILE__) + '/../../view'
    set :haml, {:format => :html5}

    system_boot_str = ""
    open('|who -b') do |io|
      system_boot_str = io.readlines.join
    end
    use Rack::Session::Cookie, :expire_after => 3600*48, :secret => Digest::SHA1.hexdigest(system_boot_str)
  end

  Yabitz::Plugin.get(:middleware_loader).each do |plugin|
    plugin.load_middleware(self)
  end
  
  before do 
  end

  after do
    # when auth failed, unread content body make error log on Apache
    request.body.read # and throw away to somewhere...
  end

  ### 認証 ###
  get '/ybz/authenticate/login' do
    protected!
    if request.referer.nil? or request.referer.empty? or request.referer == '/'
      redirect '/ybz/services'
    end
    redirect request.referer
  end

  get '/ybz/authenticate/logout' do
    session[:username] = ""
    redirect '/ybz/services'
  end

  get '/ybz/authenticate/basic' do
    protected!
    "ok"
  end

  post '/ybz/authenticate/form' do
    pair = request.params().values_at(:username, :password)
    user = Yabitz::Model::AuthInfo.authenticate(*pair, request.ip)
    unless user
      response['WWW-Authenticate'] = %(Basic realm=BASIC_AUTH_REALM)
      throw(:halt, [401, "Not Authorized\n"])
    end
    "ok"
  end

  ### smart search ###
  get %r!/ybz/smartsearch(\.json|\.csv)?! do |ctype|
    authorized?
    searchparams = request.params['keywords'].strip.split(/\s+/)
    @page_title = "簡易検索 結果"
    @service_results = []
    @results = []
    @brick_results = []
    searchparams.each do |keyword|
      search_props = Yabitz::SmartSearch.kind(keyword)
      search_props.each do |type, name, model|
        if model == :service
          @service_results.push([name + ": " + keyword, Yabitz::SmartSearch.search(type, keyword)])
        elsif model == :brick
          @brick_results.push([name + ": " + keyword, Yabitz::SmartSearch.search(type, keyword)])
        else
          @results.push([name + ": " + keyword, Yabitz::SmartSearch.search(type, keyword)])
        end
      end
    end

    Stratum.preload(@results.map(&:last).flatten, Yabitz::Model::Host) if @results.size > 0 and @results.map(&:last).flatten.size > 0
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      # ignore service/brick list for json
      @results.map(&:last).flatten.to_json
    when '.csv'
      response['Content-Type'] = 'text/csv'
      # ignore service/brick list for csv
      Yabitz::Model::Host.build_raw_csv(Yabitz::Model::Host::CSVFIELDS_LL, @results.map(&:last).flatten)
    else
      @copypastable = true
      @service_unselectable = true
      @brick_unselectable = true
      haml :smartsearch, :locals => {:cond => searchparams.join(' ')}
    end
  end

  ### 管理用 情報閲覧・操作 ###
  
  # hostに対して service,contact,dnsname,ipaddress,rackunit,hwidの欠落および重複をチェックして一覧出力
  get '/ybz/checker' do
    authorized?
    @result = Yabitz::Checker.check
    haml :checker
  end

  get '/ybz/systemchecker' do 
    authorized?
    "ok" #TODO write!
  end

  ### 各リソースの状態表示、および管理(holdなど)
  #TODO serviceurl

  # get '/ybz/rack/retrospect/:oid' #TODO


  # get '/ybz/dnsname/:oid' #TODO
  # get '/ybz/dnsname/retrospect/:oid' #TODO
  # get '/ybz/dnsname/floating' #TODO
  # delete '/ybz/dnsname/:oid' #TODO

  ### 課金状況
  # 全体
  get %r!/ybz/charge/summary(\.tsv)?! do |ctype|
    authorized?
    @depts = Yabitz::Model::Dept.all
    @contents = Yabitz::Model::Content.all
    @services = Yabitz::Model::Service.all
    @hosts = Yabitz::Model::Host.all
    tmp3 = Yabitz::Model::HwInformation.all

    @status, @types, @chargings, @dept_counts, @content_counts = Yabitz::Charging.calculate(@hosts)

    case ctype
    when '.tsv' then raise NotImplementedError
    else
      @hide_selectionbox = true
      @page_title = "課金用情報サマリ"
      haml :charge_summary
    end
  end
  # コンテンツごと
  get %r!/ybz/charge/content/(\d+)\.ajax! do |oid|
    authorized?
    
    @content = Yabitz::Model::Content.get(oid.to_i)
    @content_charges = Yabitz::Charging.calculate_content(@content)
    haml :charge_content_parts, :layout => false
  end

  ### ユーザ情報 (すべて認証要求、post/putはadmin)
  get '/ybz/auth_info/list' do
    protected!
    all_users = Yabitz::Model::AuthInfo.all.sort
    valids = []
    invalids = []
    all_users.each do |u|
      if u.valid? and not u.root?
        valids.push(u)
      elsif not u.root?
        invalids.push(u)
      end
    end
    @users = valids + invalids
    @page_title = "ユーザ認証情報一覧"
    haml :auth_info_list
  end

  get %r!/ybz/auth_info/(\d+)(\.ajax|\.tr\.ajax)?! do |oid, ctype|
    protected!
    @auth_info = Yabitz::Model::AuthInfo.get(oid.to_i)
    pass unless @auth_info # object not found -> HTTP 404

    case ctype
    when '.ajax' then haml :auth_info_parts, :layout => false
    when '.tr.ajax' then haml :auth_info, :layout => false, :locals => {:auth_info => @auth_info}
    else
      raise NotImplementedError
    end
  end
  
  post '/ybz/auth_info/:oid' do
    admin_protected!
    user = Yabitz::Model::AuthInfo.get(params[:oid].to_i)
    pass unless user

    case request.params['operation']
    when 'toggle'
      case request.params['field']
      when 'priv'
        if user.admin?
          user.priv = nil
        else
          user.set_admin
        end
      when 'valid'
        user.valid = (not user.valid?)
      end
    end
    user.save
    "ok"
  end
  # post '/ybz/auth_info/invalidate' #TODO

  get %r!/ybz/contactmember/list(\.json)?! do |ctype|
    protected!
    @contactmembers = Yabitz::Model::ContactMember.all.sort
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @contactmembers.to_json
    else
      @page_title = "連絡先メンバ一覧"
      haml :contactmember_list
    end
  end

  # get '/ybz/contactmember/create' #TODO
  # post '/ybz/contactmember/create' #TODO

  get %r!/ybz/contactmember/(\d+)(\.json|\.ajax|\.tr.ajax)?! do |oid, ctype|
    protected!
    @contactmember = Yabitz::Model::ContactMember.get(oid.to_i)
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @contactmember.to_json
    when '.ajax'
      haml :contactmember_parts, :layout => false
    when '.tr.ajax'
      haml :contactmember, :layout => false, :locals => {:contactmember => @contactmember}
    else
      @contactmembers = [@contactmember]
      @page_title = "連絡先メンバ表示：" + @contactmember.name
      haml :contactmember_list
    end
  end

  post %r!/ybz/contactmember/(\d+)! do |oid|
    protected!
    Stratum.transaction do |conn|
      @member = Yabitz::Model::ContactMember.get(oid.to_i)

      pass unless @member
      if request.params['target_id']
        unless request.params['target_id'].to_i == @member.id
          raise Stratum::ConcurrentUpdateError
        end
      end
      field = request.params['field'].to_sym
      @member.send(field.to_s + '=', @member.map_value(field, request))
      @member.save

      Yabitz::Plugin.get(:handler_hook).each do |plugin|
        if plugin.respond_to?(:contactmember_update)
          plugin.contactmember_update(@member)
        end
      end

    end
    "ok"
  end

  post '/ybz/contactmember/alter-prepare/:ope/:oidlist' do
    admin_protected!
    oidlist = params[:oidlist].split('-').map(&:to_i)
    members = Yabitz::Model::ContactMember.get(oidlist)
    unless oidlist.size == members.size
      halt HTTP_STATUS_CONFLICT, "指定された連絡先メンバの全部もしくは一部が見付かりません<br />ページを更新してやりなおしてください"
    end
    case params[:ope]
    when 'remove_data'
      "指定された連絡先メンバをすべての連絡先から取り除き、データを削除します"
    when 'update_from_source'
      if members.select{|m| (m.name.nil? or m.name.empty?) and (m.badge.nil? or m.badge.empty?)}.size > 0
        halt HTTP_STATUS_NOT_ACCEPTABLE, "氏名も社員番号も入力されていないメンバがあり、検索できません"
      end
      "指定された連絡先メンバの氏名と社員番号・職種を連携先から取得して更新します"
    when 'combine_each'
      "指定された連絡先メンバのうち、氏名と電話番号、メールアドレスが一致するものを統合します"
    else
      pass
    end
  end

  post '/ybz/contactmember/alter-execute/:ope/:oidlist' do
    admin_protected!
    oidlist = params[:oidlist].split('-').map(&:to_i)
    members = Yabitz::Model::ContactMember.get(oidlist)
    unless oidlist.size == members.size
      halt HTTP_STATUS_CONFLICT, "指定された連絡先メンバの全部もしくは一部が見付かりません<br />ページを更新してやりなおしてください"
    end
    case params[:ope]
    when 'remove_data'
      Stratum.transaction do |conn|
        Yabitz::Model::Contact.all.each do |contact|
          if (contact.members_by_id & oidlist).size > 0
            contact.members_by_id = (contact.members_by_id - oidlist)
            contact.save
          end
        end
        members.each do |member|
          member.remove
        end
      end
      "#{oidlist.size}件の連絡先メンバを削除しました"
    when 'update_from_source'
      name_only = []
      badge_only = []
      fully_qualified = []

      members.each do |m|
        if m.name and not m.name.empty? and m.badge and not m.badge.empty?
          fully_qualified.push([m, [m.name.delete(' 　'), m.badge.to_i]]) # delete space, and full-width space
        elsif m.name and not m.name.empty?
          name_only.push([m, m.name.delete(' 　')]) # delete space, and full-width space
        elsif m.badge and not m.badge.empty?
          badge_only.push([m, m.badge.to_i])
        end
      end

      def update_member(member, entry)
        return unless entry
        
        if entry[:fullname] and member.name.delete(' 　') != entry[:fullname]
          member.name = entry[:fullname]
        end
        if entry[:badge] and entry[:badge].to_i != member.badge.to_i
          member.badge = entry[:badge].to_s
        end
        if entry[:position] and entry[:position] != member.position
          member.position = entry[:position]
        end
        member.save unless member.saved?
      end

      Stratum.transaction do |conn|
        if name_only.size > 0
          memlist, namelist = name_only.transpose
          entries = Yabitz::Model::ContactMember.find_by_fullname_list(namelist)
          entries.each_index do |i|
            update_member(memlist[i], entries[i])
          end
        end
        if badge_only.size > 0
          memlist, badgelist = badge_only.transpose
          entries = Yabitz::Model::ContactMember.find_by_badge_list(badgelist)
          entries.each_index do |i|
            update_member(memlist[i], entries[i])
          end
        end
        if fully_qualified.size > 0
          memlist, pairlist = fully_qualified.transpose
          entries = Yabitz::Model::ContactMember.find_by_fullname_and_badge_list(pairlist)
          entries.each_index do |i|
            update_member(memlist[i], entries[i])
          end
        end
      end
      "連絡先メンバの更新に成功しました"
    when 'combine_each'
      combined = {}
      members.each do |member|
        combkey = member.name + '/' + member.telno + '/' + member.mail
        combined[combkey] = [] unless combined[combkey]
        combined[combkey].push(member)
      end
      oid_map = []
      all_combined_oids = []
      Stratum.transaction do |conn|
        combined.each do |key, list|
          next if list.size < 2
          c = Yabitz::Model::ContactMember.new
          c.name = list.first.name
          c.telno = list.first.telno
          c.mail = list.first.mail
          c.comment = list.map(&:comment).compact.join("\n")
          c.save
          oid_map.push([list.map(&:oid), c.oid])
          all_combined_oids += list.map(&:oid)
        end

        Yabitz::Model::Contact.all.each do |contact|
          next if (contact.members_by_id & all_combined_oids).size < 1

          member_id_list = contact.members_by_id
          member_id_list.each_index do |index|
            oid_map.each do |from_id_list, to_id|
              if from_id_list.include?(member_id_list[index])
                member_id_list[index] = to_id
              end
            end
          end
          contact.members_by_id = member_id_list
          contact.save
        end
        members.each do |member|
          member.remove if all_combined_oids.include?(member.oid)
        end
      end
      "指定された連絡先メンバの統合を実行しました"
    else
      pass
    end
  end

  # delete '/ybz/contactmembers/:oid' #TODO

  get '/ybz/yabitz.css' do
    authorized?
    content_type 'text/css', :charset => 'utf-8'
    sass :yabitz
  end

  get %!/ybz/top_toggle! do
    authorized?
    if session[:toppage] and session[:toppage] == 'googlelike'
      session[:toppage] = nil
    else
      session[:toppage] = 'googlelike'
    end
    redirect '/ybz'
  end

  get %r!\A/ybz/?\Z! do 
    authorized?
    @hide_detailview = true
    haml :toppage
  end

  get %r!\A/\Z! do
    redirect '/ybz'
  end

  Yabitz::Plugin.get(:handler).each do |plugin|
    if plugin.respond_to?(:addhandlers)
      plugin.addhandlers(self)
    end
  end

  not_found do 
    "指定の操作が定義にないか、または操作対象のoidが存在しません"
  end

  error Yabitz::DuplicationError do
    halt HTTP_STATUS_CONFLICT, "そのデータは既に存在しています"
  end

  error Yabitz::InconsistentDataError do
    halt HTTP_STATUS_NOT_ACCEPTABLE, CGI.escapeHTML(request.env['sinatra.error'].message)
  end

  error Stratum::FieldValidationError do
    msg = CGI.escapeHTML(request.env['sinatra.error'].message)
    if request.env['sinatra.error'].model and request.env['sinatra.error'].field
      ex = request.env['sinatra.error'].model.ex(request.env['sinatra.error'].field)
      if ex and not ex.empty?
        msg += "<br />" + CGI.escapeHTML(ex)
      end
    end
    halt HTTP_STATUS_NOT_ACCEPTABLE, msg
  end

  error Stratum::ConcurrentUpdateError do 
    halt HTTP_STATUS_CONFLICT, "他の人とWeb更新操作が衝突しました<br />ページを更新してからやり直してください"
  end

  error Stratum::TransactionOperationError do 
    halt HTTP_STATUS_CONFLICT, "他の人と処理が衝突しました<br />ページを更新してからやり直してください"
  end

  Yabitz::Plugin.get(:error_handler).each do |plugin|
    if plugin.respond_to?(:adderrorhandlers)
      plugin.adderrorhandlers(self)
    end
  end

  # error do 
  # end
end

require_relative 'controller'

if ENV['RACK_ENV'].to_sym == :development or ENV['RACK_ENV'].to_sym == :importtest
  Yabitz::Application.run! :host => '0.0.0.0', :port => 8180
end
