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
    target_status = (/\?s=([_a-z]+)$/.match(request.referer) || ['','in_service'])[1]
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
                                   [[Yabitz::Model::Host::STATUS_IN_SERVICE], nil]
                                 end
    status_cond ||= Yabitz::Model::Host.status_title(status_labels.first)
    Stratum.conn do |conn|
      sql = <<EOSQL
SELECT service AS service_oid, status, count(*) AS counts
FROM #{Yabitz::Model::Host.tablename}
WHERE hwinfo=? AND head=? AND removed=?
GROUP BY service,status
EOSQL
      conn.query(sql, @hwinfo.oid, Stratum::Model::BOOL_TRUE, Stratum::Model::BOOL_FALSE).each do |row|
        sid = row['service_oid'].to_i
        @service_count_map[sid] ||= {:target => 0, :all => 0}
        counts = row['counts']
        next if counts < 1
        @service_count_map[sid][:all] += counts
        if status_labels.include?(row['status'])
          @service_count_map[sid][:target] += counts
        end
      end
    end
    haml :machine_hw_service_parts, :layout => false, :locals => {:cond => status_cond}
  end

  get %r!/ybz/machines/hardware(\.tsv)?! do |ctype|
    authorized?
    @hws = Yabitz::Model::HwInformation.all.sort
    target_status = (request.params['s'] || 'in_service')
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
    @osname = unescape(CGI.unescapeHTML(osname_raw)) || nil
    @all_services = Yabitz::Model::Service.all
    @service_count_map = {}
    target_status = (/\?s=([_a-z]+)$/.match(request.referer) || ['','in_service'])[1]
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
                                   [[Yabitz::Model::Host::STATUS_IN_SERVICE], nil]
                                 end
    status_cond ||= Yabitz::Model::Host.status_title(status_labels.first)
    Stratum.conn do |conn|
      sql = <<EOSQL
SELECT service AS service_oid, status, count(*) AS counts
FROM #{Yabitz::Model::Host.tablename}
WHERE os=? AND head=? AND removed=?
GROUP BY service,status
EOSQL
      conn.query(sql, @osname, Stratum::Model::BOOL_TRUE, Stratum::Model::BOOL_FALSE).each do |row|
        sid = row['service_oid'].to_i
        @service_count_map[sid] ||= {:target => 0, :all => 0}
        counts = row['counts']
        next if counts < 1
        @service_count_map[sid][:all] += counts
        if status_labels.include?(row['status'])
          @service_count_map[sid][:target] += counts
        end
      end
    end
    haml :machine_os_service_parts, :layout => false, :locals => {:cond => status_cond}
  end

  get %r!/ybz/machines/os(\.tsv)?! do |ctype|
    authorized?
    @osnames = Yabitz::Model::OSInformation.os_in_hosts.sort
    target_status = (request.params['s'] || 'in_service')
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
      @page_title = "OS別使用状況"
      cond = "OS別使用状況 ステータス: #{status_cond}"
      haml :machine_os, :locals => {:selected => target_status, :status_list => status_labels, :cond => cond}
    end
  end
end
