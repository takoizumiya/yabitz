# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
  get '/ybz/brick/create' do
    admin_protected!
    @page_title = "機器追加"
    haml :brick_create
  end

  post '/ybz/brick/create' do
    admin_protected!
    params = request.params
    Stratum.transaction do |conn|
      params.keys.select{|k| k =~ /\Aadding\d+\Z/}.each do |key|
        i = params[key].to_i.to_s
        brick = Yabitz::Model::Brick.new
        brick.productname = params["productname#{i}"].strip
        brick.hwid = params["hwid#{i}"].strip
        brick.serial = params["serial#{i}"].strip
        brick.heap = params["heap#{i}"].strip
        brick.delivered = params["delivered"]
        brick.status = params["status"]
        brick.save
      end
    end
    "ok"
  end

  get '/ybz/brick/bulkcreate' do
    admin_protected!
    @page_title = "機器追加(CSV/TSV)"
    haml :brick_bulkcreate
  end
  
  post '/ybz/brick/bulkcreate' do
    admin_protected!
    status = request.params["status"]
    datalines = request.params["dataarea"].split("\n")
    raise Yabitz::InconsistentDataError, "データが空です" if datalines.empty?
    splitter = if datalines.first.include?("\t")
                 lambda {|l| l.split("\t")}
               else
                 require 'csv'
                 lambda {|l| l.parse_csv}
               end
    Stratum.transaction do |conn|
      datalines.each do |line|
        next if line.empty? or line.length < 1
        p, s, d, h = splitter.call(line)
        raise Yabitz::InconsistentDataError, "不足しているフィールドがあります" unless p and s and d and h
        brick = Yabitz::Model::Brick.new
        brick.productname = p
        brick.hwid = h
        brick.serial = s
        brick.delivered = d
        brick.status = status
        brick.save
      end
    end
    "ok"
  end

  get %r!/ybz/bricks/list/all(\.json|\.csv)?! do |ctype|
    authorized?
    if request.params['p'].nil?
      @bricks = Yabitz::Model::Brick.all
      @cond = "全て"
    else
      product = request.params['p']
      @bricks = Yabitz::Model::Brick.query(:productname => product)
      @cond = product
    end
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @bricks.to_json
    when '.csv'
      response['Content-Type'] = 'text/csv'
      Yabitz::Model::Brick.build_raw_csv(Yabitz::Model::Brick::CSVFIELDS, @bricks)
    else
      @bricks.sort!
      @page_title = "機器一覧 (#{@cond})"
      haml :bricks, :locals => {:cond => @cond}
    end
  end

  get %r!/ybz/brick/list/hosts/([-0-9]+)(\.json|\.csv)?! do |host_oidlist, ctype|
    authorized?
    hosts = Yabitz::Model::Host.get(host_oidlist.split('-').map(&:to_i))
    pass if hosts.empty? # object not found -> HTTP 404

    hwidlist = []
    hosts.each do |h|
      if h.hwid and h.hwid.length > 1
        hwidlist.push(h.hwid)
      end
    end
    @bricks = Yabitz::Model::Brick.choose(:hwid){|hwid| hwidlist.delete(hwid)}
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @bricks.to_json
    when '.csv'
      response['Content-Type'] = 'text/csv'
      Yabitz::Model::Brick.build_raw_csv(Yabitz::Model::Brick::CSVFIELDS, @bricks)
    else
      @bricks.sort!
      @page_title = "機器一覧 (選択ホストから)"
      @default_selected_all = true
      haml :bricks, :locals => {:cond => "選択ホストから"}
    end
  end

  get %r!/ybz/bricks/list/(stock|in_use|spare|repair|broken)(\.json|\.csv)?! do |statuslabel, ctype|
    authorized?
    targetstatus = case statuslabel
                   when 'stock'  then Yabitz::Model::Brick::STATUS_STOCK
                   when 'in_use' then Yabitz::Model::Brick::STATUS_IN_USE
                   when 'spare'  then Yabitz::Model::Brick::STATUS_SPARE
                   when 'repair' then Yabitz::Model::Brick::STATUS_REPAIR
                   when 'broken' then Yabitz::Model::Brick::STATUS_BROKEN
                   end
    statustitle = Yabitz::Model::Brick.status_title(targetstatus)
    product = request.params['p']
    if product.nil?
      @bricks = Yabitz::Model::Brick.query(:status => targetstatus)
      @cond = statustitle
    else
      @bricks = Yabitz::Model::Brick.query(:status => targetstatus, :productname => product)
      @cond = "#{statustitle} / #{product}"
    end
    product_list = @bricks.map(&:productname).uniq.compact
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @bricks.to_json
    when '.csv'
      response['Content-Type'] = 'text/csv'
      Yabitz::Model::Brick.build_raw_csv(Yabitz::Model::Brick::CSVFIELDS, @bricks)
    else
      @bricks.sort!
      @page_title = "機器一覧 (#{@cond})"
      haml :bricks, :locals => {:cond => @cond, :products => product_list, :selected => product}
    end
  end

  get %r!/ybz/brick/hwid/(.*)(\.json|\.csv)?! do |hwid, ctype|
    authorized?
    @bricks = Yabitz::Model::Brick.query(:hwid => hwid)
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      @bricks.to_json
    when '.csv'
      response['Content-Type'] = 'text/csv'
      Yabitz::Model::Brick.build_raw_csv(Yabitz::Model::Brick::CSVFIELDS, @bricks)
    else
      @bricks.sort!
      @page_title = "機器一覧 (HWID: #{CGI.escapeHTML(hwid)})"
      haml :bricks, :locals => {:cond => 'HWID:' + hwid}
    end
  end

  get %r!/ybz/brick/([-0-9]+)(\.ajax|\.tr\.ajax|\.json|\.csv)?! do |oidlist, ctype|
    authorized?
    @bricks = Yabitz::Model::Brick.get(oidlist.split('-').map(&:to_i))
    pass if @bricks.empty? # object not found -> HTTP 404
    case ctype
    when '.ajax'
      @brick = @bricks.first
      haml :brick_parts, :layout => false
    when '.tr.ajax'
      haml :brick, :layout => false, :locals => {:brick => @bricks.first}
    when '.json'
      response['Content-Type'] = 'application/json'
      @bricks.to_json
    when '.csv'
      response['Content-Type'] = 'text/csv'
      Yabitz::Model::Brick.build_raw_csv(Yabitz::Model::Brick::CSVFIELDS, @bricks)
    else
      @page_title = "機器一覧"
      haml :bricks, :locals => {:cond => '機器: ' + @bricks.map{|b| CGI.escapeHTML(b.to_s)}.join(', ')}
    end
  end

  post '/ybz/brick/:oid' do 
    protected!
    Stratum.transaction do |conn|
      @brick = Yabitz::Model::Brick.get(params[:oid].to_i)
      pass unless @brick
      if request.params['target_id']
        unless request.params['target_id'].to_i == @brick.id
          raise Stratum::ConcurrentUpdateError
        end
      end
      field = request.params['field'].to_sym
      @brick.send(field.to_s + '=', @brick.map_value(field, request))
      @brick.save
    end
    "ok"
  end

  post '/ybz/brick/alter-prepare/:ope/:oidlist' do
    admin_protected!
    oidlist = params[:oidlist].split('-').map(&:to_i)
    bricks = Yabitz::Model::Brick.get(oidlist)
    unless oidlist.size == bricks.size
      halt HTTP_STATUS_CONFLICT, "指定された機器の全部もしくは一部が見付かりません<br />ページを更新してやりなおしてください"
    end
    
    case params[:ope]
    when 'status_in_use', 'status_repair', 'status_broken', 'status_stock'
      st_title = Yabitz::Model::Brick.status_title(params[:ope] =~ /\Astatus_(.+)\Z/ ? $1.upcase : nil)
      "状態: #{st_title} へ変更していいですか？"
    when 'status_spare'
      if bricks.select{|b| b.heap.nil? or b.heap == ''}.size > 0
        halt HTTP_STATUS_NOT_ACCEPTABLE, "指定された機器に置き場所不明のものがあります<br />入力してからやりなおしてください"
      end
      "状態 #{Yabitz::Model::Brick.status_title(Yabitz::Model::Brick::STATUS_SPARE)} へ変更していいですか？"
    when 'set_heap'
      set_heap_template = <<EOT
%div 選択した機器の置き場所を入力してください
%div
  %input{:type => "text", :name => "heap", :size => 16}
EOT
      haml set_heap_template, :layout => false
    when 'set_served'
      set_served_template = <<EOT
%div 選択した機器の利用開始日を入力してください
%div
  %input{:type => "text", :name => "served", :size => 16}
EOT
      haml set_served_template, :layout => false
    when 'delete_records'
      "選択された機器すべてのデータを削除して本当にいいですか？<br />" + bricks.map{|brick| h(brick.to_s)}.join('<br />')
    else
      pass
    end
  end
  
  post '/ybz/brick/alter-execute/:ope/:oidlist' do
    admin_protected!
    oidlist = params[:oidlist].split('-').map(&:to_i)
    bricks = Yabitz::Model::Brick.get(oidlist)
    unless oidlist.size == bricks.size
      halt HTTP_STATUS_CONFLICT, "指定された機器の全部もしくは一部が見付かりません<br />ページを更新してやりなおしてください"
    end
    
    case params[:ope]
    when 'status_in_use', 'status_repair', 'status_broken', 'status_stock'
      raise ArgumentError, params[:ope] unless params[:ope] =~ /\Astatus_(.+)\Z/ and Yabitz::Model::Brick::STATUS_LIST.include?($1.upcase)
      new_status = $1.upcase
      Stratum.transaction do |conn|
        bricks.each do |brick|
          brick.status = new_status
          brick.save
        end
      end
    when 'status_spare'
      raise ArgumentError if bricks.select{|b| b.heap.nil? or b.heap == ''}.size > 0
      Stratum.transaction do |conn|
        bricks.each do |brick|
          brick.status = Yabitz::Model::Brick::STATUS_SPARE
          brick.save
        end
      end
    when 'set_heap'
      Stratum.transaction do |conn|
        bricks.each do |brick|
          brick.heap = params[:heap]
          brick.save
        end
      end
    when 'set_served'
      Stratum.transaction do |conn|
        bricks.each do |brick|
          brick.served = params[:served]
          brick.save
        end
      end
    when 'delete_records'
      Stratum.transaction do |conn|
        bricks.each do |brick|
          brick.remove
        end
      end
    else
      pass
    end
    'ok'
  end

  get '/ybz/brick/history/:oidlist' do |oidlist|
    authorized?
    @brick_records = []
    oidlist.split('-').map(&:to_i).each do |oid|
      @brick_records += Yabitz::Model::Brick.retrospect(oid)
    end
    @brick_records.sort!{|a,b| ((b.inserted_at.to_i <=> a.inserted_at.to_i) != 0) ? (b.inserted_at.to_i <=> a.inserted_at.to_i) : (b.id.to_i <=> a.id.to_i)}
    @oidlist = oidlist
    @hide_detailview = true
    haml :brick_history
  end

  get %r!/ybz/brick/served(\/([-0-9]+)(\/([-0-9]+))?)?(\.json|\.csv)?! do |dummy1, from, dummy2, to, ctype|
    authorized?
    @served_records = nil
    from = params[:from] if not from and params[:from]
    to = params[:to] if not to and params[:to] and params[:to].length > 0

    if from and from.length > 0
      raise ArgumentError, "invalid from" unless from and from =~ /^\d\d\d\d-\d\d-\d\d$/
      raise ArgumentError, "invalid to" unless to.nil? or to =~ /^\d\d\d\d-\d\d-\d\d$/
      to = Time.now.strftime('%Y-%m-%d') if to.nil?
      @served_records = Yabitz::Model::Brick.served_between(from, to)
    end
    case ctype
    when '.json'
      raise NotImplementedError, "hmmmm...."
    when '.csv'
      raise NotImplementedError, "hmmmm...."
    else
      @from_param = from
      @to_param = to
      @page_title = "機器利用開始リスト"
      haml :brick_served, :locals => {:from => from, :to => to}
    end
  end

end
