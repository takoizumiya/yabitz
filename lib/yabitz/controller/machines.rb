# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
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
end
