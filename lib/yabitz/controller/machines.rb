# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
  ### 運用状況
  # 筐体/OS別の台数/ユニット数
  
  COUNT_TOBE_REMAIN = [
                       Yabitz::Model::Host::STATUS_IN_SERVICE, Yabitz::Model::Host::STATUS_UNDER_DEV, Yabitz::Model::Host::STATUS_NO_COUNT,
                       Yabitz::Model::Host::STATUS_STANDBY, Yabitz::Model::Host::STATUS_MISSING, Yabitz::Model::Host::STATUS_OTHER,
                       Yabitz::Model::Host::STATUS_SUSPENDED
                      ]
  COUNT_REMAINING = COUNT_TOBE_REMAIN + [Yabitz::Model::Host::STATUS_REMOVING]

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
    target_status = (request.params['s'] || 'all')
    status_labels, status_cond = case target_status
                                 when 'all' then [[], "全て"]
                                 when 'remaining' then [COUNT_REMAINING, "未撤去すべて"]
                                 when 'tobe_remain' then [COUNT_TOBE_REMAIN, "撤去済・撤去依頼済以外すべて"]
                                 when 'in_service' then [[Yabitz::Model::Host::STATUS_IN_SERVICE], nil]
                                 when 'under_dev' then [[Yabitz::Model::Host::STATUS_UNDER_DEV], nil]
                                 when 'no_count' then [[Yabitz::Model::Host::STATUS_NO_COUNT], nil]
                                 when 'standby' then [[Yabitz::Model::Host::STATUS_STANDBY], nil]
                                 when 'missing' then [[Yabitz::Model::Host::STATUS_MISSING], nil]
                                 when 'other' then [[Yabitz::Model::Host::STATUS_OTHER], nil]
                                 when 'suspended' then [[Yabitz::Model::Host::STATUS_SUSPENDED], nil]
                                 when 'removing' then [[Yabitz::Model::Host::STATUS_REMOVING], nil]
                                 when 'removed' then [[Yabitz::Model::Host::STATUS_REMOVED], nil]
                                 else
                                   nil
                                 end
    unless status_labels
      halt HTTP_STATUS_NOT_FOUND, "指定のステータスには対応していません"
    end
    status_cond ||= Yabitz::Model::Host.status_title(status_labels.first)
    case ctype
    when '.tsv' then raise NotImplementedError
    else
      @hide_selectionbox = true
      @page_title = "筐体別使用状況"
      cond = "筐体別使用状況 ステータス: #{status_cond}"
      haml :machine_hardware, :locals => {:selected => target_status, :status_list => status_labels, :cond => cond}
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
