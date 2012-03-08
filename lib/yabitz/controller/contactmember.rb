# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
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

end
