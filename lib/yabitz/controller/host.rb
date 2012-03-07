# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base

  # ホスト詳細表示
  get %r!/ybz/host/([-0-9]+)(\.json|\.ajax|\.tr\.ajax|(\.[SML])?\.csv)?! do |oidlist, ctype, size|
    authorized?
    @hosts = Yabitz::Model::Host.get(oidlist.split('-').map(&:to_i))
    pass if @hosts.empty? # object not found -> HTTP 404

    Stratum.preload(@hosts, Yabitz::Model::Host);
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @hosts.to_json
    when '.ajax'
      raise RuntimeError, "ajax host detail call accepts only 1 host" if @hosts.size > 1
      @host = @hosts.first
      haml :host_parts, :layout => false
    when '.tr.ajax'
      raise RuntimeError, "ajax host detail call accepts only 1 host" if @hosts.size > 1
      @host = @hosts.first
      haml :host, :layout => false, :locals => {:host => @host}
    when '.S.csv', '.M.csv', '.L.csv'
      response['Content-Type'] = 'text/csv'
      fields = case ctype
               when '.S.csv' then Yabitz::Model::Host::CSVFIELDS_S
               when '.M.csv' then Yabitz::Model::Host::CSVFIELDS_M
               when '.L.csv' then Yabitz::Model::Host::CSVFIELDS_L
               end
      Yabitz::Model::Host.build_csv(fields, @hosts)
    when '.csv'
      response['Content-Type'] = 'text/csv'
      Yabitz::Model::Host.build_raw_csv(Yabitz::Model::Host::CSVFIELDS_LL, @hosts)
    else
      @page_title = "ホスト: #{@hosts.map(&:display_name).join(', ')}"
      @copypastable = true
      @default_selected_all = true
      haml :hosts, :locals => {:cond => @page_title}
    end
  end

  # ホスト作成
  get '/ybz/host/create' do
    admin_protected!
    target_service = if params[:service]
                       Yabitz::Model::Service.get(params[:service].to_i)
                     else
                       nil
                     end
    @page_title = 'ホスト追加'
    haml :host_create, :locals => {:cond => @page_title, :target => target_service}
  end

  post '/ybz/host/create' do
    admin_protected!
    params = request.params

    service = Yabitz::Model::Service.get(params['service'].to_i)
    raise Yabitz::InconsistentDataError, "所属サービスが指定されていません" unless service
    unless params['status'] and Yabitz::Model::Host::STATUS_LIST.include?(params['status'])
      raise Yabitz::InconsistentDataError, "作成後の状態が指定されていません"
    end

    opetag = Yabitz::OpeTagGenerator.generate

    Stratum.transaction do |conn|
      hv_list = []
      hook_insert_host_list = []

      params.keys.select{|k| k =~ /\Aadding\d+\Z/}.each do |key|
        i = params[key].to_i.to_s

        # host-creation only validation (insufficiant case with Yabitz::Model::Host validators)
        hosttype = Yabitz::HostType.new(params["type#{i}"])
        if hosttype.host?
          raise Yabitz::InconsistentDataError, "ホスト作成時には必ずメモリ容量を入力してください" if not params["memory#{i}"] or params["memory#{i}"].strip.empty?
          raise Yabitz::InconsistentDataError, "ホスト作成時には必ずHDD容量を入力してください" if not params["disk#{i}"] or params["disk#{i}"].strip.empty?
        end

        host = Yabitz::Model::Host.new
        host.service = service
        host.status = params['status']
        host.type = hosttype.name
        host.rackunit = params["rackunit#{i}"].strip.empty? ? nil : Yabitz::Model::RackUnit.query_or_create(:rackunit => params["rackunit#{i}"].strip)
        host.hwid = params["hwid#{i}"].strip
        host.hwinfo = params["hwinfo#{i}"].strip.empty? ? nil : Yabitz::Model::HwInformation.get(params["hwinfo#{i}"].to_i)
        host.cpu = params["cpu#{i}"].strip
        host.memory = params["memory#{i}"].strip
        host.disk = params["disk#{i}"].strip
        host.os = params["os#{i}"].strip.empty? ? "" : Yabitz::Model::OSInformation.get(params["os#{i}"].to_i).name
        host.dnsnames = params["dnsnames#{i}"].split(/\s+/).select{|n|n.size > 0}.map{|dns| Yabitz::Model::DNSName.query_or_create(:dnsname => dns)}
        host.localips = params["localips#{i}"].split(/\s+/).select{|n|n.size > 0}.map{|lip| Yabitz::Model::IPAddress.query_or_create(:address => lip)}
        host.globalips = params["globalips#{i}"].split(/\s+/).select{|n|n.size > 0}.map{|gip| Yabitz::Model::IPAddress.query_or_create(:address => gip)}
        host.virtualips = params["virtualips#{i}"].split(/\s+/).select{|n|n.size > 0}.map{|gip| Yabitz::Model::IPAddress.query_or_create(:address => gip)}
        alert_plugin = Yabitz::Plugin.get(:hostalerts).first
        host.alert = alert_plugin ? alert_plugin.default_value : false

        if host.hwid and host.hwid.length > 0 and not hosttype.virtualmachine?
          bricks = Yabitz::Model::Brick.query(:hwid => host.hwid)
          unless bricks.first.nil? or bricks.first.status == Yabitz::Model::Brick::STATUS_STOCK
            raise Yabitz::InconsistentDataError, "指定されたhwid #{host.hwid} に対応する機器が「#{Yabitz::Model::Brick.status_title(Yabitz::Model::Brick::STATUS_STOCK)}」以外の状態です"
          end
          if bricks.size == 1
            brick = bricks.first
            brick.status = Yabitz::Model::Brick::STATUS_IN_USE
            brick.heap = host.rackunit.rackunit if host.rackunit
            if service.content and service.content.code and service.content.code.length > 0 and service.content.code != 'NONE'
              brick.served!
            end
            brick.save
          end
        end

        tags = Yabitz::Model::TagChain.new
        tags.tagchain = ([opetag] + params["tagchain#{i}"].strip.split(/\s+/)).flatten.compact
        host.tagchain = tags

        # host.parent / host.children
        if host.hosttype.virtualmachine? and host.rackunit and host.hwid and not host.hwid.empty?
          hv_oids = Yabitz::Model::Host.query(:rackunit => host.rackunit, :hwid => host.hwid, :type => host.hosttype.hypervisor.name, :oidonly => true)
          raise Yabitz::InconsistentDataError, "ラック位置とHWIDが同一のハイパーバイザが2台以上存在します" if hv_oids.size > 1
          raise Yabitz::InconsistentDataError, "ゲスト指定されていますがラック位置とHWIDの一致するハイパーバイザがありません" if hv_oids.size < 1

          unless hv_list.map(&:oid).include?(hv_oids.first)
            hv_list.push(Yabitz::Model::Host.get(hv_oids.first))
          end
          hv = hv_list.select{|h| h.oid == hv_oids.first}.first

          if hv.saved?
            hv.prepare_to_update()
            unless hv.tagchain.tagchain.include?(opetag)
              hv.tagchain.tagchain += [opetag]
              hv.tagchain.save
            end
          end
          host.parent = hv
          unless hv.dnsnames.map(&:dnsname).include?('p.' + host.dnsnames.first.dnsname)
            hv.dnsnames += [Yabitz::Model::DNSName.query_or_create(:dnsname => 'p.' + host.dnsnames.first.dnsname)]
          end
        end

        host.save
        tags.save

        hook_insert_host_list.push(host)
      end

      Yabitz::Plugin.get(:handler_hook).each do |plugin|
        if plugin.respond_to?(:host_insert)
          hook_insert_host_list.each do |h|
            plugin.host_insert(h)
          end
        end
      end

      hv_list.each do |hv|
        # for handler_hook, un-cached object get
        pre_state = Yabitz::Model::Host.get(hv.oid, :ignore_cache => true)

        hv.save

        Yabitz::Plugin.get(:handler_hook).each do |plugin|
          if plugin.respond_to?(:host_update)
            plugin.host_update(pre_state, hv)
          end
        end
      end
    end

    "opetag:" + opetag
  end

  # JSON PUT API は生データを投入するイメージ
  # brick連動はなし
  put '/ybz/host/create' do
    admin_protected!
    json = JSON.load(request.body)

    service = Yabitz::Model::Service.query(:name => json['service'], :unique => true);
    raise Yabitz::InconsistentDataError, "所属サービスが指定されていません" unless service
    unless json['status'] and Yabitz::Model::Host::STATUS_LIST.include?(json['status'])
      raise Yabitz::InconsistentDataError, "作成後の状態が指定されていません"
    end

    Stratum.transaction do |conn|
      hv_list = []

      params.keys.select{|k| k =~ /\Aadding\d+\Z/}.each do |key|
        i = params[key].to_i.to_s

        # host-creation only validation (insufficiant case with Yabitz::Model::Host validators)
        hosttype = Yabitz::HostType.new(json["type"])
        if hosttype.host?
          raise Yabitz::InconsistentDataError, "ホスト作成時には必ずメモリ容量を入力してください" if not json["memory"] or json["memory"].empty?
          raise Yabitz::InconsistentDataError, "ホスト作成時には必ずHDD容量を入力してください" if not json["disk"] or json["disk"].empty?
        end

        host = Yabitz::Model::Host.new
        host.service = service
        host.status = json['status']
        host.type = hosttype.name
        host.rackunit = (json["rackunit"].nil? or json["rackunit"].empty?) ? nil : Yabitz::Model::RackUnit.query_or_create(:rackunit => json["rackunit"])
        host.hwid = json["hwid"]
        host.hwinfo = (json["hwinfo"].nil? or json['hwinfo'].empty?) ? nil : Yabitz::Model::HwInformation.query(:name => json["hwinfo"], :unique => true)
        host.cpu = json["cpu"]
        host.memory = json["memory"]
        host.disk = json["disk"]
        host.os = json['os']
        host.dnsnames = json["dnsnames"].map{|dns| Yabitz::Model::DNSName.query_or_create(:dnsname => dns)}
        host.localips = json["localips"].map{|lip| Yabitz::Model::IPAddress.query_or_create(:address => lip)}
        host.globalips = json["globalips"].map{|gip| Yabitz::Model::IPAddress.query_or_create(:address => gip)}
        host.virtualips = json["virtualips"].map{|gip| Yabitz::Model::IPAddress.query_or_create(:address => gip)}

        # host.parent / host.children
        if host.hosttype.virtualmachine? and host.rackunit and host.hwid and not host.hwid.empty?
          hv_oids = Yabitz::Model::Host.query(
                                              :rackunit => host.rackunit, :hwid => host.hwid,
                                              :type => host.hosttype.hypervisor.name, :oidonly => true)
          raise Yabitz::InconsistentDataError, "ラック位置とHWIDが同一のハイパーバイザが2台以上存在します" if hv_oids.size > 1
          raise Yabitz::InconsistentDataError, "ゲスト指定されていますがラック位置とHWIDの一致するハイパーバイザがありません" if hv_oids.size < 1

          unless hv_list.map(&:oid).include?(hv_oids.first)
            hv_list.push(Yabitz::Model::Host.get(hv_oids.first))
          end
          hv = hv_list.select{|h| h.oid == hv_oids.first}.first

          if hv.saved?
            hv.prepare_to_update()
          end
          host.parent = hv
          unless hv.dnsnames.map(&:dnsname).include?('p.' + host.dnsnames.first.dnsname)
            hv.dnsnames += [Yabitz::Model::DNSName.query_or_create(:dnsname => 'p.' + host.dnsnames.first.dnsname)]
          end
        end

        host.save
      end

      hv_list.each do |hv|
        hv.save
      end
    end
    'ok'
  end


  # ホスト変更履歴
  get '/ybz/host/history/:oidlist' do |oidlist|
    authorized?
    @host_records = []
    oidlist.split('-').map(&:to_i).each do |oid|
      @host_records += Yabitz::Model::Host.retrospect(oid)
    end
    @host_records.sort!{|a,b| ((b.inserted_at.to_i <=> a.inserted_at.to_i) != 0) ? (b.inserted_at.to_i <=> a.inserted_at.to_i) : (b.id.to_i <=> a.id.to_i)}
    @oidlist = oidlist
    @hide_detailview = true
    haml :host_history
  end

  get %r!/ybz/host/diff/([-0-9]+)/(\d+)/?(\d+)?! do |oidlist, endpoint, startpoint|
    authorized?
    @id_end = endpoint.to_i
    @id_start = startpoint.to_i # if nil, id_start == 0
    @first_timestamp = nil
    @last_timestamp = nil
    @host_record_pairs = []
    oidlist.split('-').map(&:to_i).each do |oid|
      records = Yabitz::Model::Host.retrospect(oid)
      next if records.size < 1
      after = records.select{|h| h.id <= @id_end}.sort{|a,b| b.id <=> a.id}.first
      before = records.select{|h| h.id <= @id_start}.sort{|a,b| b.id <=> a.id}.first

      if (@first_timestamp.nil? and before) or (before and @first_timestamp.to_i > before.inserted_at.to_i)
        @first_timestamp = before.inserted_at
      end
      if (@last_timestamp.nil? and after) or (after and @last_timestamp.to_i < after.inserted_at.to_i)
        @last_timestamp = after.inserted_at
      end

      @host_record_pairs.push([after, before])
    end

    @hide_selectionbox = true
    haml :host_diff
  end

  get %r!/ybz/operations/?(\d{8})?/?(\d{8})?! do |start_date, end_date|
    authorized?
    @start_date = start_date
    @end_date = end_date
    # array of [date, tags]
    @tags_collection = if start_date and end_date
                         Yabitz::Model::TagChain.opetags_range(start_date, end_date)
                       else
                         Yabitz::Model::TagChain.active_opetags
                       end
    @hide_selectionbox = true
    haml :opetag_list
  end

  get %r!/ybz/host/operation/([^.]+)(\.ajax)?! do |ope, ctype|
    authorized?
    @opetag = ope

    case ctype
    when '.ajax'
      @hosts = Yabitz::Model::Host.get(Yabitz::Model::TagChain.query(:tagchain => @opetag).map(&:host_by_id), :force_all => true)
      haml :opetag_parts, :layout => false
    else
      tags = Yabitz::Model::TagChain.query(:tagchain => @opetag, :select => :first)
      @host_record_pairs = []
      tags.each do |tag|
        records = Yabitz::Model::Host.retrospect(tag.host_by_id)
        next if records.size < 1
        
        # '15' is magic number, but maybe operations (with opetag) is once in 30 seconds
        after = records.select{|h| (tag.inserted_at - 15) <= h.inserted_at and h.inserted_at <= (tag.inserted_at + 15)}.first
        before = records.select{|h| h.inserted_at < (tag.inserted_at - 15)}.first

        next if after.nil?

        @host_record_pairs.push([after, before])
      end
      @hide_selectionbox = true
      haml :opetag_diff
    end
  end

  # ホスト情報変更
  post %r!/ybz/host/(\d+)! do |oid|
    protected!

    Stratum.transaction do |conn|
      @host = Yabitz::Model::Host.get(oid.to_i)

      # for update hook
      pre_host_status = Yabitz::Model::Host.get(oid.to_i, :ignore_cache => true)

      pass unless @host
      if request.params['target_id']
        unless request.params['target_id'].to_i == @host.id
          raise Stratum::ConcurrentUpdateError
        end
      end

      field = request.params['field'].to_sym
      unless @isadmin or field == :notes or field == :tagchain
        halt HTTP_STATUS_FORBIDDEN, "not authorized"
      end

      @host.send(field.to_s + '=', @host.map_value(field, request))
      @host.save

      Yabitz::Plugin.get(:handler_hook).each do |plugin|
        if plugin.respond_to?(:host_update)
          plugin.host_update(pre_host_status, @host)
        end
      end
    end
    
    "ok"
  end

  # JSON PUT API は生データを直接書き換えるイメージなので、連動して他のステータスが変わるようなフックは実行しない
  # ということにする
  put %r!/ybz/host/(\d+)! do |oid|
    admin_protected!
    json = JSON.load(request.body)
    halt HTTP_STATUS_NOT_ACCEPTABLE, "mismatch oid between request #{json['oid']} and URI #{oid}" unless oid.to_i == json['oid'].to_i

    Stratum.transaction do |conn|
      host = Yabitz::Model::Host.get(oid.to_i)
      halt HTTP_STATUS_CONFLICT unless host.id == json['id'].to_i

      # for update hook
      pre_host_status = Yabitz::Model::Host.get(oid.to_i, :ignore_cache => true)
      pre_children_status = Yabitz::Model::Host.get(pre_host_status.children_by_id, :ignore_cache => true)

      content = json['content']

      host.service = Yabitz::Model::Service.get(content['service'].to_i) unless equal_in_fact(host.service_by_id, content['service'])
      host.status = content['status'] unless equal_in_fact(host.status, content['status'])
      host.type = Yabitz::HostType.new(content['type']).name unless equal_in_fact(host.type, content['type'])
      unless equal_in_fact(host.rackunit, content['rackunit'])
        host.rackunit = if content['rackunit'].nil? or content['rackunit'].empty?
                          nil
                        else
                          Yabitz::Model::RackUnit.query_or_create(:rackunit => content['rackunit'])
                        end
        if host.hosttype.hypervisor?
          host.children.each do |c|
            c.rackunit = host.rackunit
          end
        end
      end
      unless equal_in_fact(host.hwid, content['hwid'])
        host.hwid = content['hwid']
        if host.hosttype.hypervisor?
          host.children.each do |c|
            c.hwid = content['hwid']
          end
        end
      end

      unless equal_in_fact(host.hwinfo, content['hwinfo'])
        host.hwinfo = if content['hwinfo'].nil? or content['hwinfo'].empty?
                        nil
                      else
                        Yabitz::Model::HwInformation.query_or_create(:name => content['hwinfo'])
                      end
      end
      host.cpu = content['cpu'] unless equal_in_fact(host.cpu, content['cpu'])
      host.memory = content['memory'] unless equal_in_fact(host.memory, content['memory'])
      host.disk = content['disk'] unless equal_in_fact(host.disk, content['disk'])
      unless equal_in_fact(host.os, content['os'])
        host.os = if content['os'].nil? or content['os'].empty?
                    nil
                  else
                    Yabitz::Model::OSInformation.query_or_create(:name => content['os']).name
                  end
      end
      unless equal_in_fact(host.dnsnames, content['dnsnames'])
        if content['dnsnames']
          host.dnsnames = content['dnsnames'].map{|dns| Yabitz::Model::DNSName.query_or_create(:dnsname => dns)}
        else
          host.dnsnames = []
        end
      end
      unless equal_in_fact(host.localips, content['localips'])
        if content['localips']
          host.localips = content['localips'].map{|lip| Yabitz::Model::IPAddress.query_or_create(:address => lip)}
        else
          host.localips = []
        end
      end
      unless equal_in_fact(host.globalips, content['globalips'])
        if content['globalips']
          host.globalips = content['globalips'].map{|lip| Yabitz::Model::IPAddress.query_or_create(:address => lip)}
        else
          host.globalips = []
        end
      end
      unless equal_in_fact(host.virtualips, content['virtualips'])
        if content['virtualips']
          host.virtualips = content['virtualips'].map{|lip| Yabitz::Model::IPAddress.query_or_create(:address => lip)}
        else
          host.virtualips = []
        end
      end
      host.alert = content['alert']
      tags = content['tagchain'].is_a?(Array) ? content['tagchain'] : (content['tagchain'] && content['tagchain'].split(/\s+/))
      unless equal_in_fact(host.tagchain.tagchain, tags)
        host.tagchain.tagchain = tags
        host.tagchain.save
      end
      host.notes = content['notes'] unless equal_in_fact(host.notes, content['notes'])
      if not host.saved?
        host.save
        host.children.each do |child|
          child.save unless child.saved?
        end
      end

      Yabitz::Plugin.get(:handler_hook).each do |plugin|
        if plugin.respond_to?(:host_update)
          plugin.host_update(pre_host_status, host)
          [pre_children_status, host.children].transpose.each do |pre, post|
            plugin.host_update(pre, post)
          end
        end
      end
    end
    "ok"
  end

  # 複数ホスト一括変更 (status_* / change_service / add_tag / tie_hypervisor / change_dns / delete_records)
  post '/ybz/host/alter-prepare/:ope/:oidlist' do
    admin_protected!
    oidlist = params[:oidlist].split('-').map(&:to_i)
    hosts = Yabitz::Model::Host.get(oidlist)
    unless oidlist.size == hosts.size
      halt HTTP_STATUS_CONFLICT, "指定されたホストの全部もしくは一部が見付かりません<br />ページを更新してやりなおしてください"
    end
    
    case params[:ope]
    when 'status_under_dev', 'status_in_service', 'status_no_count', 'status_suspended', 'status_standby',
      'status_removing', 'status_removed', 'status_missing', 'status_other'
      st_title = Yabitz::Model::Host.status_title(params[:ope] =~ /\Astatus_(.+)\Z/ ? $1.upcase : nil)
      "状態: #{st_title} へ変更していいですか？"
    when 'change_service'
      Stratum.preload(Yabitz::Model::Service.all, Yabitz::Model::Service)
      service_select_tag_template = <<EOT
%div 変更先サービスを選択してください
%div
  %select{:name => "service"}
    - Yabitz::Model::Service.all.sort.each do |service|
      %option{:value => service.oid}&= service.name + ' [' + service.content.to_s + ']'
EOT
      haml service_select_tag_template, :layout => false
    when 'add_tag'
      tag_input_template = <<EOT
%div 付与するタグを入力してください
%div
  %input{:type => "text", :name => "tag", :size => 16}
EOT
      haml tag_input_template, :layout => false
    when 'delete_records'
      "選択されたホストすべてのデータを削除して本当にいいですか？<br />" + hosts.map{|host| h(host.display_name)}.join('<br />')
    when 'tie_hypervisor'
      if hosts.select{|h| t = h.hosttype; (not t.hypervisor?) and (not t.virtualmachine?)}.size > 0
        halt HTTP_STATUS_NOT_ACCEPTABLE, "ハイパーバイザおよびゲスト以外のホストが選択に含まれています"
      end

      hv_host = hosts.select{|h| h.hosttype.hypervisor?}
      unless hv_host.size == 1
        halt HTTP_STATUS_NOT_ACCEPTABLE, "ハイパーバイザのホストをひとつだけ指定してください"
      end
      hv_host = hv_host.first

      guest_hosts = hosts.select{|h| h.hosttype.virtualmachine?}
      unless guest_hosts.inject(true){|t,h| t and h.hosttype.hypervisor.name == hv_host.hosttype.name}
        halt HTTP_STATUS_NOT_ACCEPTABLE, "ハイパーバイザとゲストの間で種類が合っていないものが含まれています"
      end

      unless guest_hosts.inject(true){|t,h| t and (h.hwid.nil? or h.hwid.empty? or h.hwid == hv_host.hwid) and (h.rackunit.nil? or h.rackunit_by_id == hv_host.rackunit_by_id)}
        halt HTTP_STATUS_OK, "HWIDおよびラック位置の異なるものが含まれていますが、親 #{hv_host.display_name} 子 #{guest_hosts.map(&:display_name).join(',')} の関係を設定を強行しますか？"
      end

      "親 #{hv_host.display_name} 子 #{guest_hosts.map(&:display_name).join(',')} の関係を設定していいですか？"
    when 'change_dns'
      if hosts.select{|host| host.dnsnames.nil? or host.dnsnames.empty? or host.dnsnames.size > 1}.size > 0
        halt HTTP_STATUS_NOT_ACCEPTABLE, "指定されたホストに、以下のものが含まれています<br />dns名を持っていない、あるいは複数のdns名を持っている<br />この対象はdns名の一斉変更ができません"
      end
      name_parts = hosts.map do |h|
        rev = h.dnsnames.first.dnsname.split('.').reverse
        rev.shift if rev.first == h.hwinfo.to_s
        rev
      end.transpose
      match_parts = []
      name_parts.each do |array|
        if array.inject(){|a,b| (a and a == b) ? a : nil}
          match_parts.push(array.first)
        else
          break
        end
      end
      change_dns_template = if match_parts.size == 0
                              <<EOT
%div dns名の末尾に追加します
%div
  %input{:type => "text", :name => "dns_replace_to", :size => 16}
  %input{:type => "hidden", :name => "dns_replace_from", :value => ""}
EOT
                            else
                              replace_string = match_parts.reverse.join('.')
                              <<EOT
%div dns名の #{h(replace_string)} の部分を置き換えます
%div
  %input{:type => "text", :name => "dns_replace_to", :size => 16}
  %input{:type => "hidden", :name => "dns_replace_from", :value => h(replace_string)}
EOT
                            end
      haml change_dns_template, :layout => false, :locals => {:replace_string => replace_string}
    else
      pass
    end
  end
  
  post '/ybz/host/alter-execute/:ope/:oidlist' do
    admin_protected!
    oidlist = params[:oidlist].split('-').map(&:to_i)
    hosts = Yabitz::Model::Host.get(oidlist)

    # for update hook
    pre_host_status_list = Yabitz::Model::Host.get(oidlist, :ignore_cache => true)

    unless oidlist.size == hosts.size
      halt HTTP_STATUS_CONFLICT, "指定されたホストの全部もしくは一部が見付かりません<br />ページを更新してやりなおしてください"
    end

    case params[:ope]
    when 'status_under_dev', 'status_in_service', 'status_no_count', 'status_suspended', 'status_standby',
      'status_removing', 'status_removed', 'status_missing', 'status_other'
      raise ArgumentError, params[:ope] unless params[:ope] =~ /\Astatus_(.+)\Z/ and Yabitz::Model::Host::STATUS_LIST.include?($1.upcase)
      new_status = $1.upcase
      tag = Yabitz::OpeTagGenerator.generate

      # for udpate hook for hypervisors
      pre_hv_hosts = []
      hv_hosts = []

      Stratum.transaction do |conn|
        hosts.each do |host|
          host.prepare_to_update()

          if host.tagchain.nil?
            host.tagchain = Yabitz::Model::TagChain.new.save
          end
          host.status = new_status

          # if content.code is valid and status is in_service, then brick will be served.
          if host.hwid and host.hwid.length > 0 and not host.hosttype.virtualmachine? and
              new_status == Yabitz::Model::Host::STATUS_IN_SERVICE and host.service and host.service.content and
              host.service.content.code and host.service.content.code.length > 0 and host.service.content.code != 'NONE'
            bricks = Yabitz::Model::Brick.query(:hwid => host.hwid)
            if bricks.size == 1
              brick = bricks.first
              if brick.status == Yabitz::Model::Brick::STATUS_IN_USE
                brick.served!
                brick.save
              end
            end
          end

          if new_status == Yabitz::Model::Host::STATUS_REMOVED
            host.localips = []
            host.globalips = []
            host.virtualips = []

            if host.parent_by_id
              # for update hook
              unless pre_hv_hosts.map(&:oid).include?(host.parent_by_id)
                pre_hv_hosts.push(Yabitz::Model::Host.get(host.parent_by_id, :ignore_cache => true))
                hv_hosts.push(Yabitz::Model::Host.get(host.parent_by_id))
              end

              ph = hv_hosts.select{|hv| hv.oid == host.parent_by_id}.first
              ph.prepare_to_update() if ph.saved?

              unless ph.tagchain.tagchain.include?(tag)
                ph.tagchain.tagchain += [tag]
              end
              ph.dnsnames = ph.dnsnames.select{|d| d.dnsname != 'p.' + host.dnsnames.first.dnsname}
              host.parent = nil
            end
          end
          host.tagchain.tagchain += [tag]
          host.tagchain.save
          host.save
        end
        hv_hosts.each do |hv|
          hv.tagchain.save
          hv.save
        end

        Yabitz::Plugin.get(:handler_hook).each do |plugin|
          if params[:ope] == 'status_removed'
            if plugin.respond_to?(:host_delete)
              hosts.each do |host|
                plugin.host_delete(host)
              end
            end
            if plugin.respond_to?(:host_update)
              if pre_hv_hosts.size > 0
                [pre_hv_hosts, hv_hosts].transpose.each do |pre, post|
                  plugin.host_update(pre, post)
                end
              end
            end
          else
            if plugin.respond_to?(:host_update)
              [pre_host_status_list, hosts].transpose.each do |pre, post|
                plugin.host_update(pre, post)
              end
            end
          end
        end
      end
      "opetag:" + tag
    when 'change_service'
      service = Yabitz::Model::Service.get(params[:service].to_i)
      tag = Yabitz::OpeTagGenerator.generate
      Stratum.transaction do |conn|
        hosts.each do |host|
          if host.tagchain.nil?
            host.tagchain = Yabitz::Model::TagChain.new.save
          end

          host.service = service

          # if content.code is valid and status is in_service, then brick will be served.
          if host.hwid and host.hwid.length > 0 and not host.hosttype.virtualmachine? and
              host.status == Yabitz::Model::Host::STATUS_IN_SERVICE and service and service.content and
              service.content.code and service.content.code.length > 0 and service.content.code != 'NONE'
            bricks = Yabitz::Model::Brick.query(:hwid => host.hwid)
            if bricks.size == 1
              brick = bricks.first
              if brick.status == Yabitz::Model::Brick::STATUS_IN_USE
                brick.served!
                brick.save
              end
            end
          end

          host.tagchain.tagchain += [tag]
          host.tagchain.save
          host.save
        end

        Yabitz::Plugin.get(:handler_hook).each do |plugin|
          if plugin.respond_to?(:host_update)
            [pre_host_status_list, hosts].transpose.each do |pre, post|
              plugin.host_update(pre, post)
            end
          end
        end
      end
      "opetag:" + tag
    when 'add_tag'
      tag = params[:tag]
      Stratum.transaction do |conn|
        hosts.each do |host|
          if host.tagchain.nil?
            host.tagchain = Yabitz::Model::TagChain.new.save
          end
          host.tagchain.tagchain += [tag]
          host.tagchain.save
          host.save
        end
        
        Yabitz::Plugin.get(:handler_hook).each do |plugin|
          if plugin.respond_to?(:host_update)
            [pre_host_status_list, hosts].transpose.each do |pre, post|
              plugin.host_update(pre, post)
            end
          end
        end
      end
      tag
    when 'delete_records'
      tag = Yabitz::OpeTagGenerator.generate
      Stratum.transaction do |conn|
        hosts.each do |host|
          if host.tagchain.nil?
            host.tagchain = Yabitz::Model::TagChain.new.save
          end
          host.parent = nil
          host.children = []
          host.rackunit = nil
          host.hwinfo = nil
          host.dnsnames = []
          host.localips = []
          host.globalips = []
          host.virtualips = []
          host.tagchain.tagchain += [tag]
          host.tagchain.save
          host.save

          host.remove
        end

        Yabitz::Plugin.get(:handler_hook).each do |plugin|
          if plugin.respond_to?(:host_delete)
            pre_host_status_list.each do |host|
              plugin.host_delete(host)
            end
          end
        end
      end
      "opetag:" + tag
    when 'tie_hypervisor'
      tag = Yabitz::OpeTagGenerator.generate

      Stratum.transaction do |conn|
        hv_host = hosts.select{|h| h.hosttype.hypervisor?}.first
        guest_hosts = hosts.select{|h| h.hosttype.virtualmachine?}
        raise Yabitz::InconsistentDataError, "ホスト選択が不整合" unless guest_hosts.size + 1 == hosts.size
        unless guest_hosts.inject(true){|t,h| t and h.hosttype.hypervisor.name == hv_host.hosttype.name}
          raise Yabitz::InconsistentDataError, "ハイパーバイザとゲストの間で種類が不整合"
        end
        
        hv_host.prepare_to_update()

        guest_hosts.each do |g|
          g.hwid = hv_host.hwid if g.hwid.nil? or g.hwid.empty?
          g.rackunit = hv_host.rackunit unless g.rackunit
          g.parent = hv_host
          g.tagchain.tagchain += [tag]
          g.tagchain.save
          g.save

          p_dnsname = Yabitz::Model::DNSName.query_or_create(:dnsname => 'p.' + g.dnsnames.first.dnsname)
          unless hv_host.dnsnames.map(&:oid).include?(p_dnsname.oid)
            hv_host.dnsnames += [p_dnsname]
          end
          p_dnsname.hosts.select{|h| h.hosttype.hypervisor? and not h.children_by_id.include?(g.oid)}.each do |pre_hv|
            pre_hv.dnsnames = pre_hv.dnsnames.select{|dns| dns.oid != p_dnsname.oid}
            pre_hv.tagchain.tagchain += [tag]
            pre_hv.tagchain.save
            pre_hv.save
          end
        end
        hv_host.tagchain.tagchain += [tag]
        hv_host.tagchain.save
        hv_host.save

        Yabitz::Plugin.get(:handler_hook).each do |plugin|
          if plugin.respond_to?(:host_update)
            [pre_host_status_list, hosts].transpose.each do |pre, post|
              plugin.host_update(pre, post)
            end
          end
        end
      end
      "opetag:" + tag
    when 'change_dns'
      tag = Yabitz::OpeTagGenerator.generate
      replace_from_part = params[:dns_replace_from]
      replace_to_part = params[:dns_replace_to]
      Stratum.transaction do |conn|
        hosts.each do |host|
          raise Yabitz::InconsistentDataError.new("dns名の数が不正です") unless host.dnsnames.size == 1
          if host.tagchain.nil?
            host.tagchain = Yabitz::Model::TagChain.new.save
          end
          replaced = if replace_from_part.size > 0
                       host.dnsnames.first.dnsname.sub(replace_from_part, replace_to_part)
                     else
                       host.dnsnames.first.dnsname + replace_to_part
                     end
          host.dnsnames = Yabitz::Model::DNSName.query_or_create(:dnsname => replaced)
          host.tagchain.tagchain += [tag]
          host.tagchain.save
          host.save
        end

        Yabitz::Plugin.get(:handler_hook).each do |plugin|
          if plugin.respond_to?(:host_update)
            [pre_host_status_list, hosts].transpose.each do |pre, post|
              plugin.host_update(pre, post)
            end
          end
        end
      end
      "opetag:" + tag
    else
      pass
    end
  end
end

