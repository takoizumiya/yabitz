# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
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

      prev_rack = nil
      next_rack = nil
      rack_list = Yabitz::Model::Rack.all().sort{|a,b| a.label <=> b.label}
      rack_list.each_index do |i|
        if rack_list[i].oid == @rack.oid
          prev_rack = rack_list[i - 1] if rack_list[i - 1]
          next_rack = rack_list[i + 1] if rack_list[i + 1]
          break
        end
      end
      
      @page_title = "ラック #{@rack.label} の状況"
      @hide_detailview = true
      haml :rack_show, :locals => {:current => @rack, :prev_rack => prev_rack, :next_rack => next_rack}
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

  # get '/ybz/rack/retrospect/:oid' #TODO
end
