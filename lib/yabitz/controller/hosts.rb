#-*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
  # サービスに対するホスト一覧
  get %r!/ybz/hosts/service/(\d+)(\.json|\.csv)?! do |oid, ctype|
    authorized?
    @srv = Yabitz::Model::Service.get(oid.to_i)
    pass unless @srv # object not found -> HTTP 404

    @hosts = Yabitz::Model::Host.query(:service => @srv).select{|h| h.status != Yabitz::Model::Host::STATUS_REMOVED}
    Stratum.preload(@hosts, Yabitz::Model::Host)
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @hosts.to_json
    when '.csv'
      response['Content-Type'] = 'text/csv'
      Yabitz::Model::Host.build_raw_csv(Yabitz::Model::Host::CSVFIELDS_LL, @hosts)
    else
      #TODO sort order options
      @hosts.sort!
      @page_title = "ホスト一覧 (サービス: #{@srv.name})"
      @copypastable = true
      haml :hosts, :locals => {:cond => "サービス: #{@srv.name}, コンテンツ: #{@srv.content.name}"}
    end
  end

  # IPアドレスからのホスト一覧
  get %r!/ybz/hosts/ipaddress/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(\.json|\.csv)?! do |address, ctype|
    authorized?
    ip = Yabitz::Model::IPAddress.query(:address => address, :unique => true)
    pass unless ip and ip.hosts.size > 0

    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      ip.hosts.to_json
    when '.csv'
      response['Content-Type'] = 'text/csv'
      Yabitz::Model::Host.build_raw_csv(Yabitz::Model::Host::CSVFIELDS_LL, ip.hosts)
    else
      @hosts = ip.hosts
      @hosts.sort!
      @page_title = "ホスト一覧 (IPアドレス: #{address})"
      @copypastable = true
      haml :hosts, :locals => {:cond => "IPアドレス: #{address}"}
    end
  end

  # 特定のステータスのホスト一覧 (removed/missing/other などでの参照を想定)
  get %r!/ybz/hosts/status/([_a-z]+)(\.json|\.csv)?! do |status, ctype|
    authorized?
    pass unless Yabitz::Model::Host::STATUS_LIST.include?(status.upcase)

    @hosts = Yabitz::Model::Host.query(:status => status.upcase)
    Stratum.preload(@hosts, Yabitz::Model::Host)
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @hosts.to_json
    when '.csv'
      response['Content-Type'] = 'text/csv'
      Yabitz::Model::Host.build_raw_csv(Yabitz::Model::Host::CSVFIELDS_LL, @hosts)
    else
      @hosts.sort!
      status_title = Yabitz::Model::Host.status_title(status.upcase)
      @page_title = "ホスト一覧 (状態: #{status_title})"
      @copypastable = true
      haml :hosts, :locals => {:cond => "状態: #{status_title}"}
    end
  end

  get %r!/ybz/hosts/all(\.json|\.csv)! do |ctype|
    authorized?
    started = Time.now
    @hosts = Yabitz::Model::Host.all
    preloading = Time.now
    Stratum.preload(@hosts, Yabitz::Model::Host)
    loaded = Time.now
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @hosts.to_json
    when '.csv'
      response['Content-Type'] = 'text/csv'
      response['X-DATA-STARTED'] = started.to_s
      response['X-DATA_PRELOAD'] = preloading.to_s
      response['X-DATA-LOADED'] = loaded.to_s
      # Yabitz::Model::Host.build_raw_csv(Yabitz::Model::Host::CSVFIELDS_LL, @hosts)
      str = Yabitz::Model::Host.build_raw_csv_burst_llfields(@hosts)
      response['X-DATA-RESPONSE'] = Time.now.to_s
      str
    else
      pass
    end
  end
end
