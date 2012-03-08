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

require_relative 'controller/authenticate.rb'
require_relative 'controller/auth_info.rb'
require_relative 'controller/brick.rb'
require_relative 'controller/charge.rb'
require_relative 'controller/contactmember.rb'
require_relative 'controller/contact.rb'
require_relative 'controller/content.rb'
require_relative 'controller/dept.rb'
require_relative 'controller/dnsname.rb'
require_relative 'controller/host.rb'
require_relative 'controller/hosts.rb'
require_relative 'controller/hwinfo.rb'
require_relative 'controller/ipaddress.rb'
require_relative 'controller/ipsegment.rb'
require_relative 'controller/machines.rb'
require_relative 'controller/osinfo.rb'
require_relative 'controller/rack.rb'
require_relative 'controller/rackunit.rb'
require_relative 'controller/search.rb'
require_relative 'controller/service.rb'
require_relative 'controller/smartsearch.rb'

if ENV['RACK_ENV'].to_sym == :development or ENV['RACK_ENV'].to_sym == :importtest
  Yabitz::Application.run! :host => '0.0.0.0', :port => 8180
end
