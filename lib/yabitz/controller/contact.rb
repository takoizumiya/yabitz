# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
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
        @contact.label = request.params['label'].strip unless @contact.label == request.params['label'].strip
        @contact.telno_daytime = request.params['telno_daytime'].strip unless @contact.telno_daytime == request.params['telno_daytime'].strip
        @contact.mail_daytime = request.params['mail_daytime'].strip unless @contact.mail_daytime == request.params['mail_daytime'].strip
        @contact.telno_offtime = request.params['telno_offtime'].strip unless @contact.telno_offtime == request.params['telno_offtime'].strip
        @contact.mail_offtime = request.params['mail_offtime'].strip unless @contact.mail_offtime == request.params['mail_offtime'].strip
        @contact.memo = request.params['memo'].strip unless @contact.memo == request.params['memo'].strip

        @contact.save
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

end
