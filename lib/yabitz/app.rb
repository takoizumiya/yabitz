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

  ### detailed search ###
  get %r!/ybz/search(\.json|\.csv)?! do |ctype|
    authorized?
    
    @page_title = "ホスト検索"
    @hosts = nil
    andor = 'AND'
    conditions = []
    ex_andor = 'AND'
    ex_conditions = []
    if request.params['andor']
      andor = (request.params['andor'] == 'OR' ? 'OR' : 'AND')
      request.params.keys.map{|k| k =~ /\Acond(\d+)\Z/; $1 ? $1.to_i : nil}.compact.sort.each do |i|
        next if request.params["value#{i}"].nil? or request.params["value#{i}"].empty?
        search_value = request.params["value#{i}"].strip
        conditions.push([request.params["field#{i}"], search_value])
      end
      ex_andor = (request.params['ex_andor'] == 'OR' ? 'OR' : 'AND')
      request.params.keys.map{|k| k =~ /\Aex_cond(\d+)\Z/; $1 ? $1.to_i : nil}.compact.sort.each do |i|
        next if request.params["ex_value#{i}"].nil? or request.params["ex_value#{i}"].empty?
        ex_search_value = request.params["ex_value#{i}"].strip
        ex_conditions.push([request.params["ex_field#{i}"], ex_search_value])
      end
      @hosts = Yabitz::DetailSearch.search(andor, conditions, ex_andor, ex_conditions)
    end

    Stratum.preload(@hosts, Yabitz::Model::Host) if @hosts;
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @hosts.to_json
    when '.csv'
      response['Content-Type'] = 'text/csv'
      Yabitz::Model::Host.build_raw_csv(Yabitz::Model::Host::CSVFIELDS_LL, @hosts)
    else
      counter = 0
      keyvalues = []
      conditions.each{|f,v| keyvalues.push("cond#{counter}=#{counter}&field#{counter}=#{f}&value#{counter}=#{v}"); counter += 1}
      counter = 0
      ex_conditions.each{|f,v| keyvalues.push("ex_cond#{counter}=#{counter}&ex_field#{counter}=#{f}&ex_value#{counter}=#{v}"); counter += 1}
      csv_url = '/ybz/search.csv?andor=' + andor + '&ex_andor=' + ex_andor + '&' + keyvalues.join('&')
      @copypastable = true
      haml :detailsearch, :locals => {
        :andor => andor, :conditions => conditions,
        :ex_andor => ex_andor, :ex_conditions => ex_conditions,
        :csv_url => csv_url
      }
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

  get %r!/ybz/ipsegment/list/(local|global)(\.json)?! do |net, ctype|
    authorized?
    area = (net == 'local' ? Yabitz::Model::IPSegment::AREA_LOCAL : Yabitz::Model::IPSegment::AREA_GLOBAL)
    @ipsegments = Yabitz::Model::IPSegment.query(:area => area)
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @ipsegments.to_json
    else
      @ips = Yabitz::Model::IPAddress.choose(:hosts, :holder, :lowlevel => true){|hosts,holder| (not hosts.nil? and not hosts.empty?) or holder == Stratum::Model::BOOL_TRUE}
      @segment_network_map = {}
      @segment_used_ip_map = {}
      @ipsegments.each do |seg|
        @segment_network_map[seg.to_s] = seg.to_addr
        @segment_used_ip_map[seg.to_s] = []
      end
      @ips.each do |ip|
        @ipsegments.each do |seg|
          if @segment_network_map[seg.to_s].include?(ip.to_addr)
            @segment_used_ip_map[seg.to_s].push(ip)
            break
          end
        end
      end

      @page_title = "IPセグメントリスト(#{net} network)"
      @ipsegments.sort!
      haml :ipsegment_list
    end
  end

  get %r!/ybz/ipsegment/list/network/([:.0-9]+\d/\d+)(\.json)?! do |network_str, ctype|
    authorized?
    network = IPAddr.new(network_str)
    @ipsegments = Yabitz::Model::IPSegment.choose(:address){|v| network.include?(IPAddr.new(v))}
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @ipsegments.to_json
    else
      @ips = Yabitz::Model::IPAddress.choose(:hosts, :holder, :lowlevel => true){|hosts,holder| (not hosts.nil? and not hosts.empty?) or holder == Stratum::Model::BOOL_TRUE}
      @segment_network_map = {}
      @segment_used_ip_map = {}
      @ipsegments.each do |seg|
        @segment_network_map[seg.to_s] = seg.to_addr
        @segment_used_ip_map[seg.to_s] = []
      end
      @ips.each do |ip|
        @ipsegments.each do |seg|
          if @segment_network_map[seg.to_s].include?(IPAddr.new(ip.address))
            @segment_used_ip_map[seg.to_s].push(ip)
            break
          end
        end
      end

      @page_title = "IPセグメント (範囲: #{network_str})"
      @ipsegments.sort!
      haml :ipsegment_list
    end
  end

  get %r!/ybz/ipsegment/(\d+)(\.tr\.ajax|\.ajax|\.json)?! do |oid, ctype|
    authorized?
    @ipseg = Yabitz::Model::IPSegment.get(oid.to_i)
    pass unless @ipseg
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @ipseg.to_json
    when '.tr.ajax'
      network = IPAddr.new(@ipseg.address + '/' + @ipseg.netmask)
      @ips = Yabitz::Model::IPAddress.choose(:hosts, :holder, :address, :lowlevel => true){|hosts,holder,address|
        ((not hosts.nil? and not hosts.empty?) or holder == Stratum::Model::BOOL_TRUE) and network.include?(IPAddr.new(address))
      }
      @segment_used_ip_map = {@ipseg.to_s => @ips}
      haml :ipsegment, :layout => false, :locals => {:ipsegment => @ipseg}
    when '.ajax'
      haml :ipsegment_parts, :layout => false
    else
      @network = @ipseg.to_addr
      @ips = Yabitz::Model::IPAddress.choose(:address){|v| @network.include?(IPAddr.new(v))}
      iptable = Hash[*(@ips.map{|ip| [ip.address, ip]}.flatten)]
      @network.to_range.each{|ip| @ips.push(Yabitz::Model::IPAddress.query_or_create(:address => ip.to_s)) unless iptable[ip.to_s]}
      
      @page_title = "IPセグメント: #{@ipseg.to_s}"
      @ips.sort!
      haml :ipaddress_list
    end
  end
  # get '/ybz/ipsegment/retrospect/:oid' #TODO

  post '/ybz/ipsegment/:oid' do
    admin_protected!

    Stratum.transaction do |conn|
      seg = Yabitz::Model::IPSegment.get(params[:oid].to_i)
      pass unless seg

      unless request.params['target_id'].to_i == seg.id
        raise Stratum::ConcurrentUpdateError
      end

      case request.params['field']
      when 'ongoing'
        unless request.params['operation'] == 'toggle'
          halt HTTP_STATUS_NOT_ACCEPTABLE, "not allowed operation"
        end
        seg.ongoing = (not seg.ongoing)
      when 'notes'
        unless request.params['operation'] = 'edit'
          halt HTTP_STATUS_NOT_ACCEPTABLE, "not allowed operation"
        end
        seg.notes = request.params['value']
      else
        halt HTTP_STATUS_NOT_ACCEPTABLE, "not allowed operation"
      end
      seg.save unless seg.saved?
    end
    
    "ok"
  end

  post '/ybz/ipsegment/create' do
    admin_protected!

    if Yabitz::Model::IPSegment.query(:address => request.params['address'].strip, :count => true) > 0
      raise Yabitz::DuplicationError
    end
    seg = Yabitz::Model::IPSegment.new
    seg.set(request.params['address'].strip, request.params['mask'].to_i.to_s)

    cls_a = IPAddr.new("10.0.0.0/8")
    cls_b = IPAddr.new("172.16.0.0/12")
    cls_c = IPAddr.new("192.168.0.0/16")
    addr = IPAddr.new(seg.address + '/' + seg.netmask)
    seg.area = if cls_a.include?(addr) or cls_b.include?(addr) or cls_c.include?(addr)
                 Yabitz::Model::IPSegment::AREA_LOCAL
               else
                 Yabitz::Model::IPSegment::AREA_GLOBAL
               end
    seg.ongoing = true
    seg.save
    
    "ok"
  end

  post '/ybz/ipsegment/alter-prepare/:ope/:oid' do
    admin_protected!
    segment = Yabitz::Model::IPSegment.get(params[:oid].to_i)
    unless segment
      halt HTTP_STATUS_CONFLICT, "指定されたIPセグメントが見付かりません<br />ページを更新してやりなおしてください"
    end

    case params[:ope]
    when 'delete_records'
      network = segment.to_addr
      if Yabitz::Model::IPAddress.choose(:address, :hosts, :holder, :lowlevel => true, :oidonly => true){|addr,hosts,holder| not addr.nil? and not addr.empty? and network.include?(IPAddr.new(addr)) and not hosts.nil? and not hosts.empty? and holder == Stratum::Model::BOOL_FALSE}.size > 0
        "セグメント #{segment} において使用中のIPアドレスがありますが、強行しますか？"
      else
        "選択されたセグメント #{segment} を削除して本当にいいですか？"
      end
    else
      pass
    end
  end

  post '/ybz/ipsegment/alter-execute/:ope/:oid' do
    admin_protected!
    segment = Yabitz::Model::IPSegment.get(params[:oid].to_i)
    unless segment
      halt HTTP_STATUS_CONFLICT, "指定されたIPセグメントが見付かりません<br />ページを更新してやりなおしてください"
    end

    case params[:ope]
    when 'delete_records'
      segment_str = segment.to_s
      segment.remove()
      "完了： セグメント #{segment_str} の削除"
    else
      pass
    end
  end

  get %r!/ybz/ipaddress/list/network/([:._0-9]+\d/\d+)(\.json)?! do |network_str, ctype|
    authorized?
    @network = IPAddr.new(Yabitz::Model::IPAddress.dequote(network_str))
    @ips = Yabitz::Model::IPAddress.choose(:address){|v| @network.include?(IPAddr.new(v))}
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @ips.to_json
    else
      iptable = Hash[*(@ips.map{|ip| [ip.address, ip]}.flatten)]
      @network.to_range.each{|ip| @ips.push(Yabitz::Model::DummyIPAddress.new(ip.to_s)) unless iptable[ip.to_s]}

      @page_title = "ネットワーク内のIPアドレス: #{network_str}"
      @ips.sort!
      haml :ipaddress_list
    end
  end

  get %r!/ybz/ipaddress/(\d+_\d+_\d+_\d+)(\.tr\.ajax|\.ajax|\.json)?! do |ipaddr, ctype|
    authorized?
    @ip = Yabitz::Model::IPAddress.query(:address => Yabitz::Model::IPAddress.dequote(ipaddr), :unique => true)
    unless @ip
      @ip = Yabitz::Model::DummyIPAddress.new(Yabitz::Model::IPAddress.dequote(ipaddr))
    end

    case ctype
    when '.json'
      pass unless @ip.oid

      response['Content-Type'] = 'application/json'
      @ip.to_json
    when '.tr.ajax'
      haml :ipaddress, :layout => false, :locals => {:ipaddress => @ip}
    when '.ajax'
      haml :ipaddress_parts, :layout => false
    else
      @page_title = "IPアドレス: #{@ip.to_s}"
      require 'ipaddr'
      @ips = [@ip]
      haml :ipaddress_list
    end
  end

  get %r!/ybz/ipaddress/holder(\.json)?! do |ctype|
    authorized?
    @ips = Yabitz::Model::IPAddress.query(:holder => true)
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @ips.to_json
    else
      @page_title = "予約済みIPアドレス一覧"
      @ips.sort!
      haml :ipaddress_list
    end
  end

  get %r!/ybz/ipaddress/global(\.json)?! do |ctype|
    authorized?
    cls_a = IPAddr.new("10.0.0.0/8")
    cls_b = IPAddr.new("172.16.0.0/12")
    cls_c = IPAddr.new("192.168.0.0/16")
    @ips = Yabitz::Model::IPAddress.choose(:address){|v| ip = IPAddr.new(v); not cls_a.include?(ip) and not cls_b.include?(ip) and not cls_c.include?(ip)}
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @ips.to_json
    else
      @page_title = "グローバルIPアドレス一覧"
      @ips.sort!
      haml :ipaddress_list
    end
  end

  get %r!/ybz/ipaddress/list(\.json)?! do |ctype|
    authorized?
    @ips = Yabitz::Model::IPAddress.all
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @ips.to_json
    else
      raise NotImplementedError
    end
  end

  post %r!/ybz/ipaddress/(\d+_\d+_\d+_\d+)! do |ipaddr|
    admin_protected!

    Stratum.transaction do |conn|
      ip = Yabitz::Model::IPAddress.query_or_create(:address => Yabitz::Model::IPAddress.dequote(ipaddr))
      if request.params['target_id'] and (not request.params['target_id'].empty?) and request.params['target_id'].to_i != ip.id
        raise Stratum::ConcurrentUpdateError
      end

      case request.params['field']
      when 'holder'
        unless request.params['operation'] == 'toggle'
          halt HTTP_STATUS_NOT_ACCEPTABLE, "not allowed operation"
        end
        ip.holder = (not ip.holder)
      when 'notes'
        unless request.params['operation'] = 'edit'
          halt HTTP_STATUS_NOT_ACCEPTABLE, "not allowed operation"
        end
        ip.notes = request.params['value']
      else
        halt HTTP_STATUS_NOT_ACCEPTABLE, "not allowed operation"
      end
      ip.save unless ip.saved?
    end
    "ok"
  end

  ### rackunit, rack
  get %r!/ybz/rackunit/list(\.json)?! do |ctype|
    authorized?
    @rackunits = Yabitz::Model::RackUnit.all
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @rackunits.to_json
    else
      raise NotImplementedError
    end
  end

  get %r!/ybz/rackunit/(\d+)(\.json)?! do |oid, ctype|
    protected!
    ru = Yabitz::Model::RackUnit.get(oid.to_i)
    pass unless ru

    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      ru.to_json
    else
      unless ru.rack
        ru.rack_set
        ru.save
      end
      redirect "/ybz/rack/#{ru.rack.oid}"
    end
  end

  post '/ybz/rack/create' do
    admin_protected!
    if Yabitz::Model::Rack.query(:label => request.params['label'], :count => true) > 0
      raise Yabitz::DuplicationError
    end

    rack = Yabitz::Model::Rack.new()
    rack.label = request.params['label'].strip
    racktype = Yabitz::RackTypes.search(rack.label)
    rack.type = racktype.name
    rack.datacenter = racktype.datacenter
    rack.ongoing = true
    rack.save
    
    "ok"
  end

  get %r!/ybz/rack/list(\.json)?! do |ctype|
    authorized?
    @racks = Yabitz::Model::Rack.all
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @racks.to_json
    else
      @units_in_racks = {}
      @rack_blank_scores = nil

      @rackunits = Yabitz::Model::RackUnit.all
      Stratum.preload(@rackunits, Yabitz::Model::RackUnit)
      @rackunits.each do |ru|
        next if ru.hosts.select{|h| h.isnt(:removed, :removing)}.size < 1
        @units_in_racks[ru.rack_by_id] ||= 0
        @units_in_racks[ru.rack_by_id] += 1
      end

      @page_title = "ラック一覧"
      @racks.sort!
      haml :rack_list
    end
  end

  get %r!/ybz/rack/blanklist! do
    authorized?
    @racks = Yabitz::Model::Rack.all
    
    @units_in_racks = {}
    @rack_blank_scores = {}

    rackunits_per_rack = {}
    @rackunits = Yabitz::Model::RackUnit.all
    Stratum.preload(@rackunits, Yabitz::Model::RackUnit)
    hwinfos = Yabitz::Model::HwInformation.all
    @rackunits.each do |ru|
      next if ru.hosts.select{|h| h.isnt(:removed, :removing)}.size < 1
      rackunits_per_rack[ru.rack_by_id] ||= []
      rackunits_per_rack[ru.rack_by_id].push(ru)
      @units_in_racks[ru.rack_by_id] ||= 0
      @units_in_racks[ru.rack_by_id] += 1
    end
    @racks.each do |rack|
      racktype = Yabitz::RackTypes.search(rack.label)
      @rack_blank_scores[rack.oid] = racktype.rackunit_status_list(rack.label, (rackunits_per_rack[rack.oid] || []))
    end

    @page_title = "ラック一覧"
    @racks.sort!{|a,b| ((a.datacenter <=> b.datacenter) != 0) ? a.datacenter <=> b.datacenter : @rack_blank_scores[b.oid].first <=> @rack_blank_scores[a.oid].first}
    haml :rack_list
  end

  get %r!/ybz/rack/(\d+)(\.tr\.ajax|\.ajax|\.json)?! do |oid, ctype|
    authorized?
    @rack = Yabitz::Model::Rack.get(oid.to_i)
    pass unless @rack

    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @rack.to_json
    when '.tr.ajax'
      rackunits = Yabitz::Model::RackUnit.query(:rack => @rack).select{|ru| ru.hosts.select{|h| h.isnt(:removing, :removed)}.size > 0}
      @units_in_racks = {@rack.oid => rackunits.size}
      @rack_blank_scores = {@rack.oid => Yabitz::RackTypes.search(@rack.label).rackunit_status_list(@rack.label, rackunits)}
      haml :rack, :layout => false, :locals => {:rack => @rack}
    when '.ajax'
      haml :rack_parts, :layout => false
    else
      @hosts = Yabitz::Model::RackUnit.query(:rack => @rack).map(&:hosts).flatten
      Stratum.preload(@hosts, Yabitz::Model::Host)
      @units = {}
      racktype = Yabitz::RackTypes.search(@rack.label)
      @hosts.each do |host|
        next if host.hosttype.virtualmachine? or host.status == Yabitz::Model::Host::STATUS_REMOVED
        @units[host.rackunit.rackunit] = host
        if host.hwinfo and host.hwinfo.unit_height > 1
          racktype.upper_rackunit_labels(host.rackunit.rackunit, host.hwinfo.unit_height - 1).each{|pos| @units[pos] = host}
        end
      end
      @page_title = "ラック #{@rack.label} の状況"
      @hide_detailview = true
      haml :rack_show
    end
  end

  post '/ybz/rack/:oid' do
    admin_protected!

    Stratum.transaction do |conn|
      rack = Yabitz::Model::Rack.get(params[:oid].to_i)
      pass unless rack

      unless request.params['target_id'].to_i == rack.id
        raise Stratum::ConcurrentUpdateError
      end

      case request.params['field']
      when 'ongoing'
        unless request.params['operation'] == 'toggle'
          halt HTTP_STATUS_NOT_ACCEPTABLE, "not allowed operation"
        end
        rack.ongoing = (not rack.ongoing)
      when 'notes'
        unless request.params['operation'] = 'edit'
          halt HTTP_STATUS_NOT_ACCEPTABLE, "not allowed operation"
        end
        rack.notes = request.params['value']
      else
        halt HTTP_STATUS_NOT_ACCEPTABLE, "not allowed operation"
      end
      rack.save unless rack.saved?
    end
    
    "ok"
  end
  
  post '/ybz/rack/alter-prepare/:ope/:oid' do
    admin_protected!
    rack = Yabitz::Model::Rack.get(params[:oid].to_i)
    unless rack
      halt HTTP_STATUS_CONFLICT, "指定されたラックが見付かりません<br />ページを更新してやりなおしてください"
    end

    case params[:ope]
    when 'delete_records'
      if Yabitz::Model::RackUnit.query(:rack => rack).select{|ru| ru.hosts_by_id.size > 0}.size > 0
        halt HTTP_STATUS_NOT_ACCEPTABLE, "(撤去済みのものも含めて)<br />このラック所属のホストが存在したままです"
      end
      "選択されたラック #{rack} を削除して本当にいいですか？"
    else
      pass
    end
  end

  post '/ybz/rack/alter-execute/:ope/:oid' do
    admin_protected!
    rack = Yabitz::Model::Rack.get(params[:oid].to_i)
    unless rack
      halt HTTP_STATUS_CONFLICT, "指定されたラックが見付かりません<br />ページを更新してやりなおしてください"
    end
    rackunits = Yabitz::Model::RackUnit.query(:rack => rack)

    case params[:ope]
    when 'delete_records'
      rack_str = rack.to_s
      Stratum.transaction do |conn|
        rackunits.each do |ru|
          halt HTTP_STATUS_CONFLICT, "ラックに所属ホストが存在したままです: 更新が衝突した可能性があります" if ru.hosts_by_id > 0
          ru.rack = nil
          ru.save
          ru.remove
        end
      end
      rack.remove
      "完了： ラック #{rack_str} の削除"
    else
      pass
    end
  end
  # get '/ybz/rackunit/retrospect/:oid' #TODO
  # get '/ybz/rack/retrospect/:oid' #TODO


  # get '/ybz/dnsname/:oid' #TODO
  # get '/ybz/dnsname/retrospect/:oid' #TODO
  # get '/ybz/dnsname/floating' #TODO
  # delete '/ybz/dnsname/:oid' #TODO

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

  get %r!/ybz/hwinfo/list(\.json)?! do |ctype|
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
  
  # delete '/ybz/hwinfo/:oid' #TODO

  ### 運用状況
  # 筐体/OS別の台数/ユニット数
  
  get %r!/ybz/machines/hardware/(\d+)\.ajax! do |oid|
    authorized?
    @hwinfo = Yabitz::Model::HwInformation.get(oid.to_i)
    @all_services = Yabitz::Model::Service.all
    @service_count_map = {}
    @all_services.each do |service|
      num = Yabitz::Model::Host.query(:service => service, :hwinfo => @hwinfo, :count => true)
      @service_count_map[service.oid] = num if num > 0
    end
    haml :machine_hw_service_parts, :layout => false
  end

  get %r!/ybz/machines/hardware(\.tsv)?! do |ctype|
    authorized?
    @hws = Yabitz::Model::HwInformation.all.sort

    case ctype
    when '.tsv' then raise NotImplementedError
    else
      @hide_selectionbox = true
      @page_title = "筐体別使用状況"
      haml :machine_hardware
    end
  end

  get %r!/ybz/machines/os/(.+)\.ajax! do |osname_raw|
    authorized?
    @osname = unescape(CGI.unescapeHTML(osname_raw))
    @all_services = Yabitz::Model::Service.all
    @service_count_map = {}
    @all_services.each do |service|
      num = Yabitz::Model::Host.query(:service => service, :os => (@osname == 'NULL' ? '' : @osname), :count => true)
      @service_count_map[service.oid] = num if num > 0
    end
    haml :machine_os_service_parts, :layout => false
  end

  get %r!/ybz/machines/os(\.tsv)?! do |ctype|
    authorized?
    @osnames = Yabitz::Model::OSInformation.os_in_hosts.sort

    case ctype
    when '.tsv' then raise NotImplementedError
    else
      @hide_selectionbox = true
      @page_title = "OS別使用状況"
      haml :machine_os
    end
  end

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
  
  ### 連絡先

  get %r!/ybz/contact/list(\.json)?! do |ctype|
    protected!
    @contacts = Yabitz::Model::Contact.all.sort
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @contacts.to_json
    else
      @page_title = "連絡先一覧"
      haml :contact_list
    end
  end

  # get '/ybz/contact/create' #TODO
  # post '/ybz/contact/create' #TODO

  get %r!/ybz/contact/(\d+)(\.json)?! do |oid, ctype|
    protected!
    @contact = Yabitz::Model::Contact.get(oid.to_i)
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @contact.to_json
    else
      @page_title = "連絡先: #{@contact.label}"
      Stratum.preload([@contact], Yabitz::Model::Contact)
      haml :contact_page, :locals => {:cond => @page_title}
    end
  end

  post '/ybz/contact/:oid' do |oid|
    protected!
    pass if request.params['editstyle'].nil? or request.params['editstyle'].empty?

    case request.params['editstyle']
    when 'fields_edit'
      Stratum.transaction do |conn|
        @contact = Yabitz::Model::Contact.get(oid.to_i)
        pass unless @contact
        if request.params['target_id']
          raise Stratum::ConcurrentUpdateError unless request.params['target_id'].to_i == @contact.id
        end
        ['label', 'telno_daytime', 'mail_daytime', 'telno_offtime', 'mail_offtime', 'memo'].each do |field_string|
          unless @contact.send(field_string) == request.params[field_string].strip
            @contact.send(field_string + '=', request.params[field_string].strip)
          end
        end
        @contact.save unless @contact.saved?
        Yabitz::Plugin.get(:handler_hook).each do |plugin|
          if plugin.respond_to?(:contact_update)
            plugin.contact_update(@contact)
          end
        end
      end
    when 'add_with_create'
      Stratum.transaction do |conn|
        @contact = Yabitz::Model::Contact.get(oid.to_i)
        pass unless @contact
        if request.params['target_id']
          raise Stratum::ConcurrentUpdateError unless request.params['target_id'].to_i == @contact.id
        end
        if request.params['badge'] and not request.params['badge'].empty?
          if Yabitz::Model::ContactMember.query(:badge => request.params['badge'].strip).size > 0
            halt HTTP_STATUS_NOT_ACCEPTABLE, "入力された社員番号と同一のメンバ情報が既にあるため、そちらを検索から追加してください"
          end
        end
        unless request.params['name']
          halt HTTP_STATUS_NOT_ACCEPTABLE, "名前の入力のない登録はできません"
        end
        member = Yabitz::Model::ContactMember.new
        member.name = request.params['name'].strip
        member.telno = request.params['telno'].strip if request.params['telno']
        member.mail = request.params['mail'].strip if request.params['mail']
        member.badge = request.params['badge'].strip.to_i.to_s unless request.params['badge'].nil? or request.params['badge'].empty?
        if not member.badge
          hit_members = Yabitz::Model::ContactMember.find_by_fullname_list([member.name.delete(' 　')])
          if hit_members.size == 1
            member_entry = hit_members.first
            member.badge = member_entry[:badge]
            member.position = member_entry[:position]
          end
        else
          hit_members = Yabitz::Model::ContactMember.find_by_fullname_and_badge_list([[member.name.delete(' 　'), member.badge]])
          if hit_members.size == 1
            member_entry = hit_members.first
            member.position = member_entry[:position]
          end
        end
        @contact.members_by_id += [member.oid]
        @contact.save
        member.save

        Yabitz::Plugin.get(:handler_hook).each do |plugin|
          if plugin.respond_to?(:contactmember_update)
            plugin.contactmember_update(member)
          end
          if plugin.respond_to?(:contact_update)
            plugin.contact_update(@contact)
          end
        end
      end
    when 'add_with_search'
      Stratum.transaction do |conn|
        @contact = Yabitz::Model::Contact.get(oid.to_i)
        pass unless @contact
        if request.params['target_id']
          raise Stratum::ConcurrentUpdateError unless request.params['target_id'].to_i == @contact.id
        end
        if request.params['adding_contactmember']
          if request.params['adding_contactmember'] == 'not_selected'
            halt HTTP_STATUS_NOT_ACCEPTABLE, "追加するメンバを選択してください"
          end
          member = Yabitz::Model::ContactMember.get(request.params['adding_contactmember'].to_i)
          halt HTTP_STATUS_NOT_ACCEPTABLE, "指定された連絡先メンバが存在しません" unless member
          halt HTTP_STATUS_NOT_ACCEPTABLE, "指定された連絡先メンバは既にリストに含まれています" if @contact.members_by_id.include?(member.oid)
          @contact.members_by_id += [member.oid]
        else
          # space and full-width-space deleted.
          name_compacted_string = (request.params['name'] and not request.params['name'].empty?) ? request.params['name'].strip : nil
          badge_number = (request.params['badge'] and not request.params['badge'].empty?) ? request.params['badge'].tr('０-９　','0-9 ').strip.to_i : nil
          member = if name_compacted_string and badge_number
                     Yabitz::Model::ContactMember.query(:name => name_compacted_string, :badge => badge_number.to_s)
                   elsif name_compacted_string
                     if name_compacted_string =~ /[ 　]/
                       first_part, last_part = name_compacted_string.split(/[ 　]/)
                       Yabitz::Model::ContactMember.regex_match(:name => /#{first_part}[ 　]*#{last_part}/)
                     else
                       Yabitz::Model::ContactMember.query(:name => name_compacted_string)
                     end
                   elsif badge_number
                     Yabitz::Model::ContactMember.query(:badge => badge_number.to_s)
                   else
                     halt HTTP_STATUS_NOT_ACCEPTABLE, "検索条件を少なくともどちらか入力してください"
                   end
          halt HTTP_STATUS_NOT_ACCEPTABLE, "入力された条件に複数のメンバが該当するため追加できません" if member.size > 1
          halt HTTP_STATUS_NOT_ACCEPTABLE, "入力された条件にどのメンバも該当しません" if member.size < 1
          member = member.first
          @contact.members_by_id += [member.oid]
        end
        @contact.save
        Yabitz::Plugin.get(:handler_hook).each do |plugin|
          if plugin.respond_to?(:contact_update)
            plugin.contact_update(@contact)
          end
        end
      end
    when 'edit_memberlist'
      Stratum.transaction do |conn|
        @contact = Yabitz::Model::Contact.get(oid.to_i)
        pass unless @contact
        if request.params['target_id']
          raise Stratum::ConcurrentUpdateError unless request.params['target_id'].to_i == @contact.id
        end
        original_oid_order = @contact.members_by_id
        reorderd_list = []
        removed_list = []
        request.params.keys.select{|k| k =~ /\Aorder_of_\d+\Z/}.each do |key|
          target = key.gsub(/order_of_/,'').to_i
          order_index_string = request.params[key]
          if order_index_string.nil? or order_index_string.empty?
            removed_list.push(target)
          else
            order_index = order_index_string.to_i - 1
            halt HTTP_STATUS_NOT_ACCEPTABLE, "順序は1以上の数で指定してください" if order_index < 0
            if original_oid_order[order_index] != target
              if reorderd_list[order_index].nil?
                reorderd_list[order_index] = target
              else
                afterpart = reorderd_list[order_index + 1, reorderd_list.size]
                re_order_index = order_index + 1 + (afterpart.index(nil) || afterpart.size)
                reorderd_list[re_order_index] = target
              end
            end
          end
        end
        original_oid_order.each do |next_oid|
          next if removed_list.include?(next_oid) or reorderd_list.include?(next_oid)
          next_blank_index = reorderd_list.index(nil) || reorderd_list.size
          reorderd_list[next_blank_index] = next_oid
        end
        reorderd_list.compact!
        if original_oid_order != reorderd_list
          @contact.members_by_id = reorderd_list
          @contact.save

          Yabitz::Plugin.get(:handler_hook).each do |plugin|
            if plugin.respond_to?(:contact_update)
              plugin.contact_update(@contact)
            end
          end
        end
      end
    end
    "連絡先 #{@contact.label} の情報を変更しました"
  end
  # delete '/ybz/contact/:oid' #TODO

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
