# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
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

end
