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
