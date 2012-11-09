$(function(){
  var h = $('#mainview').height();
  $('#detailview').height(h);
  $('#detailboxarea').height(h);
  
  $('#nav').droppy();
  $('#searchinput').keypress(function(e){if(e.which == 13){$('#smartsearch').submit();};});

  // toolbox operations
  $('button#select_on_all').click(function(e){
    clear_selections();
    $('.selectable').each(function(){select_on_selectable($(this));});
    $('#detailbox').hide();
  });
  $('button#select_off_all').click(function(e){
    $('#detailbox').hide();
    clear_selections();
  });
  $('button#selected_hosts').click(function(e){show_selected_hosts(e);});
  $('button#hosts_history').click(function(e){show_hosts_history(e);});
  $('button#hosts_diff').click(function(e){show_hosts_diff(e);});
  $('button#opetaglist').click(function(e){show_operations(e);});
  $('button#bricks_of_hosts').click(function(e){show_bricks_of_hosts(e);});

  $('button#selected_bricks').click(function(e){show_selected_bricks(e);});
  $('button#bricks_history').click(function(e){show_bricks_history(e);});
  $('select#brick_selection_list').change(function(e){show_more_selected_bricks(e);});
  $('select#hardwares_host_selection_list').change(function(e){show_hardwares_selected_hosts(e);});
  $('select#os_host_selection_list').change(function(e){show_os_selected_hosts(e);});

  $('div#copypasterlinks').find('.copypaster').click(function(e){
    copypastable_all_hosts($(e.target), window.location.href);
  });


  // events for main table items
  $('.host_outline.selectable').click(function(e){toggle_item_selection(e, 'host');});
  $('.service_item.selectable').click(function(e){toggle_item_selection(e, 'service', true);});
  $('.service_item.unselectable').click(function(e){show_detailbox_without_selection(e, 'service');});
  $('.content_item.selectable').click(function(e){toggle_item_selection(e, 'content', true);});
  $('.dept_item.selectable').click(function(e){toggle_item_selection(e, 'dept', true);});
  $('.rack_item.selectable').click(function(e){toggle_item_selection(e, 'rack', true);});
  $('.ipaddress_item.selectable').click(function(e){toggle_item_selection(e, 'ipaddress', true);});
  $('.ipsegment_item.selectable').click(function(e){toggle_item_selection(e, 'ipsegment', true);});
  $('.hwinfo_item.selectable').click(function(e){toggle_item_selection(e, 'hwinfo', true);});
  $('.authinfo_item.selectable').click(function(e){toggle_item_selection(e, 'auth_info');});
  $('.charge_item.selectable').click(function(e){toggle_item_selection(e, 'charge/content', true);});
  $('.machine_item.hw.selectable').click(function(e){toggle_item_selection(e, 'machines/hardware', true);});
  $('.machine_item.os.selectable').click(function(e){toggle_item_selection(e, 'machines/os', true);});
  $('.opetag_item.selectable').click(function(e){toggle_item_selection(e, 'host/operation', true);});
  $('.contactmember_item.selectable').click(function(e){toggle_item_selection(e, 'contactmember');});
  $('.brick_item.selectable').click(function(e){toggle_item_selection(e, 'brick');});
  $('.brick_item.unselectable').click(function(e){show_detailbox_without_selection(e, 'brick');});

  // events for mainview toggle
  $('.show_mainview').click(function(event){
    $(event.target).closest('#editpain1,#editpain2').addClass('hidden');
    $('#maincontents').removeClass('hidden');
  });
  $('.show_editpain1').click(function(event){$('#maincontents').addClass('hidden'); $('#editpain1').removeClass('hidden');});
  $('.show_editpain2').click(function(event){$('#maincontents').addClass('hidden'); $('#editpain2').removeClass('hidden');});

  // event for cloneable items add button
  $('div.listclone').click(function(e){clone_cloneable_item(e);});

  // events for entry-creation (host, contactmember, contact)
  $('form.mainform').submit(function(e){commit_main_form(e);});
  $('button.mainform_commit').click(function(e){$(e.target).closest('form.mainform').submit();});

  // events for edit contact (member-add/remove, re-ordering)


  // top page search
  $('#googlelikeinput').keypress(function(e){if(e.which == 13){e.preventDefault(); return false;} return true;});
  $('button.search_googlelike').click(function(e){
    var button = $(e.target).closest('button.search_googlelike');
    var param = button.closest('form.mainform_googlelike').formSerialize() + '&field0=' + button.attr('title');
    window.location.href = '/ybz/search?' + param;
    e.preventDefault();
    return false;
  });
  $('button.search_googlelike_smart').click(function(e){
    var button = $(e.target).closest('button.search_googlelike_smart');
    var param = $('input#googlelikeinput').val();
    window.location.href = '/ybz/smartsearch?keywords=' + param;
    e.preventDefault();
    return false;
  });

  // admin events for mainview
  $('form.smartadd').submit(function(e){commit_smartadd_form(e);});
  $('select.admin_operations').change(function(e){dispatch_admin_operation(e);});

  if ($('div.default_selected_all').size() > 0) {
    $('button#select_on_all').click();
  }

  $('.search_field_select').each(function(i, elem){
    searchFieldCheckInit( elem );
  });

  ZeroClipboard.setMoviePath( '/zeroclipboard/ZeroClipboard10.swf' );

  // sort hosts
  if ($('tr.host_outline').size() > 0) {
    appendSortbarAfter( $('tr.host.outline.detailsearch_information') );
    appendSortbarAfter( $('tr.host.outline.smartsearch_condition'), 'all' );

    var target_expr = 'tr.host_category_summary';
    var target = $(target_expr);
    $.each( target, function(i, e){
      if ( i < target.size() - 1 ) {
        appendSortbarAfter( $(e) );
      }
    });

    var prev_elem;
    $.each( $('table#hostlist > tbody > tr'), function(i, e){
      var elem = $(e);
      if ( prev_elem ) {
        if ( elem.attr('class').match('host_outline') && prev_elem.attr('class') == 'sortbar' ) {
          if ( typeof( prev_elem.attr( 'target' ) ) == 'undefined' ) {
            prev_elem.attr( 'target', $(elem.children('td').get(0)).attr('class') );
          }
        }
      }
      prev_elem = elem;
    } );

    var hostlist = $('table#hostlist > tbody > tr').get(0);
    if ($(hostlist).attr('class').match('host_outline') && ! $(hostlist).attr('class').match('unupdatable') ) {
      var sortbar;
      var top_tr = $($('table#hostlist > tbody > tr').get(0));
      top_tr.before('<tr id="voidtarget"></tr>');
      if ( top_tr.attr('class').match('hypervisor') ) {
        sortbar = appendHyperVisorSortbarAfter( $('tr#voidtarget') );
      }
      else {
        sortbar = appendSortbarAfter( $('tr#voidtarget') );
      }
      sortbar.attr( 'target', $(top_tr.children('td').get(0)).attr('class') );

      $('tr#voidtarget').remove();
    }
    $('th.sortbtn').click(function(){
      sortByColumn( this );
    });
    sortByUrl();
  }

  // build Dom0-suggestion select-box
  if ( $('select.host_hypervisor').size() > 0 ) {
    var service_select = $('select[name=service]');
    $('select.host_hypervisor').hide();
    $('span.loading.hypervisor').show();
    var do_hypervisor_suggeest = function(obj) {
      if (obj.val() < 0) return;
      $('select.host_hypervisor').hide();
      $('span.loading.hypervisor').show();
      get_hypervisors( obj, function(hvlist) {
        set_suggests( hvlist );
        $('select.host_hypervisor').html( $(get_suggests()).slice(0,10) ).prepend(suggest_head()).append(suggest_foot());
        $('span.loading.hypervisor').hide();
        $('select.host_hypervisor').show();
      });
    };
    service_select.change(function(){ do_hypervisor_suggeest($(this)); });
    do_hypervisor_suggeest(service_select);
  }

  // K/B shortcut 
  if ( $('div.listclone').size() > 0 && $('div.listclone').closest('div.hostadd_item').size() > 0 ) {
    $('body').keydown(function(event){
      if (event.altKey === true && event.which === 65 ) {
        item_clone_kb_shortcut();
      }
    });
  }
});

$.fn.hoverClass = function(c) {
  return this.each(function(){
    $(this).hover( 
      function() { $(this).addClass(c);  },
      function() { $(this).removeClass(c); }
    );
  });
};

function regist_event_listener(target){
  if (target.hasClass('host_outline')) {
    target.click(function(e){toggle_item_selection(e, 'host');});
  }
  if (target.hasClass('service_item')) {
    if (target.hasClass('selectable'))
      target.click(function(e){toggle_item_selection(e, 'service');});
    else if (target.hasClass('unselectable'))
      target.click(function(e){show_detailbox_without_selection(e, 'service');});
  }
  if (target.hasClass('content_item')) {
    target.click(function(e){toggle_item_selection(e, 'content', true);});
  }
  if (target.hasClass('dept_item')) {
    target.click(function(e){toggle_item_selection(e, 'dept', true);});
  }
  if (target.hasClass('rack_item')) {
    target.click(function(e){toggle_item_selection(e, 'rack', true);});
  }
  if (target.hasClass('ipaddress_item')) {
    target.click(function(e){toggle_item_selection(e, 'ipaddress', true);});
  }
  if (target.hasClass('ipsegment_item')) {
    target.click(function(e){toggle_item_selection(e, 'ipsegment', true);});
  }
  if (target.hasClass('contactmember_item')) {
    target.click(function(e){toggle_item_selection(e, 'contactmember');});
  }
  if (target.hasClass('brick_item')) {
    if (target.hasClass('selectable'))
      target.click(function(e){toggle_item_selection(e, 'brick');});
    else if (target.hasClass('unselectable'))
      target.click(function(e){show_detailbox_without_selection(e, 'brick');});
  }
  if (target.hasClass('authinfo_item')) {
    target.click(function(e){toggle_item_selection(e, 'auth_info');});
  }
};

if (!('bind_events_detailbox_addons' in window)) {
  bind_events_detailbox_addons = [];
}

function bind_events_detailbox() {
  $('.clickableitem,.dataview,.dataupdown,.orderedit').mouseover(function(e){highlight_editable_item(e);});
  $('.clickableitem,.dataview,.dataupdown,.orderedit').mouseout(function(e){un_highlight_editable_item(e);});

  $('div.clickablelabel,div.clickablebutton').click(function(e){show_editable_item(e);});
  $('div.memoeditbutton').click(function(e){show_editable_item(e);});

  $('img.itemadd').click(function(e){show_add_item(e);});
  $('input.togglebutton').click(function(e){e.preventDefault(); $(e.target).closest('form').submit(); return false;});

  $('form.field_edit_form').submit(function(e){commit_field_change(e);});
  $('form.toggle_form').submit(function(e){commit_toggle_form(e);});

  if (('bind_events_detailbox_addons' in window) && bind_events_detailbox_addons.length > 0) {
    $.each(bind_events_detailbox_addons, function(){ this(); });
  }
};

function commit_main_form(event){
  var form = $(event.target);
  if (form.attr('name') == 'host_create') {
    commit_mainview_form($(event.target), "ホスト追加に成功", function(){
      location.href = '/ybz/hosts/service/' + form.find('select[name="service"]').val();
    });
  }
  else if (form.attr('name') == 'host_search') {
    return true;
  }
  else if (form.attr('name') == 'host_search_dns') {
    return true;
  }
  else if (form.attr('name') == 'host_search_ip') {
    return true;
  }
  else if (form.attr('name') == 'host_search_service') {
    return true;
  }
  else if (form.attr('name') == 'host_search_rackunit') {
    return true;
  }
  else if (form.attr('name') == 'host_search_hwid') {
    return true;
  }
  else if (form.attr('name') == 'smart_search') {
    return true;
  }
  else if (form.attr('name') == 'contact_edit') {
    commit_mainview_form($(event.target), "連絡先の情報を更新しました", function(){
      location.href = '/ybz/contact/' + $('div#contact_oid div.contact_oid').attr('id');
    });
  }
  else if (form.attr('name') == 'contact_add_with_create') {
    commit_mainview_form($(event.target), "連絡先の情報を更新しました", function(){
      location.href = '/ybz/contact/' + $('div#contact_oid div.contact_oid').attr('id');
    });
  }
  else if (form.attr('name') == 'contact_add_with_search') {
    commit_mainview_form($(event.target), "連絡先の情報を更新しました", function(){
      location.href = '/ybz/contact/' + $('div#contact_oid div.contact_oid').attr('id');
    });
  }
  else if (form.attr('name') == 'contact_edit_memberlist') {
    commit_mainview_form($(event.target), "連絡先の情報を更新しました", function(){
      location.href = '/ybz/contact/' + $('div#contact_oid div.contact_oid').attr('id');
    });
  }
  else if (form.attr('name') == 'brick_create') {
    commit_mainview_form($(event.target), "機器追加に成功", function(){
      location.href = '/ybz/bricks/list/' + form.find('select[name="status"]').val().toLowerCase();
    });
  }
  else if (form.attr('name') == 'brick_bulkcreate') {
    commit_mainview_form($(event.target), "機器追加に成功", function(){
      location.href = '/ybz/bricks/list/' + form.find('select[name="status"]').val().toLowerCase();
    });
  }

  event.preventDefault();
  return false;
};

function show_selected_hosts(event){
  var selected = $(selected_objects());
  if (selected.size() < 1) {
    show_error_dialog("対象がなにも選択されていません");
    return false;
  };
  window.location.href = '/ybz/host/' + selected.get().join('-');
  return false;
};

function show_bricks_of_hosts(event){
  var selected = $(selected_objects());
  if (selected.size() < 1) {
    show_error_dialog("対象がなにも選択されていません");
    return false;
  };
  window.location.href = '/ybz/brick/list/hosts/' + selected.get().join('-');
  return false;
};

function show_selected_bricks(event){
  var selected = $(selected_objects());
  if (selected.size() < 1) {
    show_error_dialog("対象がなにも選択されていません");
    return false;
  };
  window.location.href = '/ybz/brick/' + selected.get().join('-');
  return false;
};

function show_more_selected_bricks(event){
  var product = $(event.target).val();
  var uri;
  if (product === '') {
    uri = window.location.origin + window.location.pathname;
    window.location.href = uri;
    return;
  }
  uri = window.location.origin + window.location.pathname + '?p=' + product;
  window.location.href = uri;
};

function show_hardwares_selected_hosts(event){
  var status = $(event.target).val();
  var uri;
  if (status === '') {
    uri = window.location.origin + window.location.pathname;
    window.location.href = uri;
    return;
  }
  uri = window.location.origin + window.location.pathname + '?s=' + status;
  window.location.href = uri;
};

function show_os_selected_hosts(event){
  var status = $(event.target).val();
  var uri;
  if (status === '') {
    uri = window.location.origin + window.location.pathname;
    window.location.href = uri;
    return;
  }
  uri = window.location.origin + window.location.pathname + '?s=' + status;
  window.location.href = uri;
};

function show_hosts_history(event){
  var selected = $(selected_objects());
  if (selected.size() < 1) {
    show_error_dialog("対象がなにも選択されていません");
    return false;
  };
  window.location.href = '/ybz/host/history/' + selected.get().join('-');
  return false;
};

function show_bricks_history(event){
  var selected = $(selected_objects());
  if (selected.size() < 1) {
    show_error_dialog("対象がなにも選択されていません");
    return false;
  };
  window.location.href = '/ybz/brick/history/' + selected.get().join('-');
  return false;
};

function show_hosts_diff(event){
  var oidlist = $("input[name='oidlist']").val();
  var before = $("input[type='radio']").filter("input[name='before']").filter(":checked").val();
  var after = $("input[type='radio']").filter("input[name='after']").filter(":checked").val();
  if (after == undefined && before == undefined) {
    show_error_dialog("開始点および終了点を選択してください");
    return false;
  }

  if (after == undefined || Number(after) < Number(before)) {
    var tmp = after;
    after = before;
    before = tmp;
  }
  var url = '/ybz/host/diff/' + oidlist + '/' + after;
  if (before != undefined) {
    url = url + '/' + before;
  }
  window.location.href =  url;
  return false;
};

function show_operations(event){
  var start = $("input[name='start_date']").val();
  var end = $("input[name='end_date']").val();
  var url = "/ybz/operations";
  if (start != null && end != null) {
    if (start.length != 8 || end.length != 8) {
      alert("日付入力は8桁 yyyymmdd で入力してください");
      return false;
    }
    url = url + '/' + start + '/' + end;
  }
  window.location.href = url;
  return false;
};

function load_page(url) { window.location.href = url; };

function reload_page(){
  window.location.reload(true);
};

function jump_opetag(tag) {
  window.location.href = '/ybz/host/operation/' + tag;
};

function show_confirm_dialog(msg, ok_callback, cancel_callback){
  var dialogbox = $('div#confirm_dialog');
  dialogbox.dialog({
    autoOpen: false,
    height: 250,
    width: 600,
    modal: true,
    buttons: {'OK': function(){dialogbox.dialog('close'); ok_callback();},
              'キャンセル': function(){dialogbox.dialog('close'); cancel_callback();}}
  });
  dialogbox.children('div#dialogmessage').html(msg);
  dialogbox.dialog('open');
};

function show_form_dialog(url, form_content, success_callback, cancel_callback){
  var dialogbox = $('div#form_dialog');
  dialogbox.dialog({
    autoOpen: false,
    height: 250,
    width: 600,
    modal: true,
    buttons: {
      '送信': function(){
        $('#dialogform').ajaxSubmit({
          url: url,
          success: function(data, dataType){
            dialogbox.dialog('close');
            show_success_dialog('処理に成功しました', data, success_callback);
          },
          error: function(xhr, testStatus, error){
            dialogbox.dialog('close');
            show_error_dialog(xhr.responseText, cancel_callback);
          }
        });
      },
      'キャンセル': function(){dialogbox.dialog('close'); cancel_callback();}
    }
  });
  dialogbox.find('div#dialogform_content').html(form_content);
  dialogbox.dialog('open');
};

function show_success_dialog(msg, result_tag, callback){
  var dialogbox = $('div#success_dialog');
  dialogbox.dialog({
    autoOpen: false,
    height: 250,
    width: 600,
    modal: true,
    buttons: {'OK': function(){dialogbox.dialog('close');}}
  });
  dialogbox.children('div#dialogmessage').html(msg + '<br />' + result_tag);
  if (callback) {
    if (result_tag.match(/^opetag:(.*)$/)) {
      var opetag = RegExp.$1;
      dialogbox.bind("dialogclose", function(event, ui){jump_opetag(opetag);});
    }
    else {
      dialogbox.bind("dialogclose", function(event, ui){callback(result_tag);});
    }
  }
  dialogbox.dialog('open');
};

function show_error_dialog(msg, callback){
  var dialogbox = $('div#error_dialog');
  dialogbox.dialog({
    autoOpen: false,
    height: 250,
    width: 600,
    modal: true,
    buttons: {'OK': function(){dialogbox.dialog('close');}}
  });
  dialogbox.children('div#dialogmessage').html(msg);
  if (callback) {
    dialogbox.bind("dialogclose", function(event, ui){callback();});
  }
  dialogbox.dialog('open');
};

function copypastable_setup(target, copypaster_type, baseurl, linkurl){
  if ($('embed#ZeroClipboardMovie_1').size() > 0) {
    $('embed#ZeroClipboardMovie_1').parent().remove();
  };
  $('li#paster').remove();

  var url = "";
  switch(copypaster_type) {
  case 'copypaster_s':
    url = baseurl + '.S.csv'; break;
  case 'copypaster_m':
    url = baseurl + '.M.csv'; break;
  case 'copypaster_l':
    url = baseurl + '.L.csv'; break;
  }
  $(target).closest('.copypaster').after('<li id="paster">[copy]</li>');
  $.get(url, function(data){
    var clip = new ZeroClipboard.Client();
    clip.setText(linkurl + "\n" + data);
    clip.glue('paster');
    $('#paster').click(function(e){$(e.target).remove();});
  });
  event.preventDefault();
  return false;
};

function copypastable_all_hosts(target, linkurl) {
  copypastable_setup(
    target,
    $(target).closest('.copypaster').attr('id'),
    '/ybz/host/' + $.map($('.host_outline.selectable'), function(v,i){return $(v).attr('id');}).join('-'),
    linkurl
  );
  event.preventDefault();
  return false;
};

function copypaster(event) {
  var hosts_url = '/ybz/host/' + selected_objects().join('-');
  copypastable_setup(
    event.target,
    $(event.target).closest('.copypaster').attr('id'),
    hosts_url,
    window.location.protocol + '//' + window.location.host + hosts_url
  );
  event.preventDefault();
  return false;
};

function update_selections_number(){
  var num = $('#selections').children().size();
  if (num == 0) {
    $('#selection_number').text('なし');
    $('.copypaster').unbind();
    $('#copypasterbox').hide();
  }
  else {
    $('#selection_number').text(num);
    $('#copypasterbox').show();
    $('.copypaster').unbind().click(copypaster);
  }
};

function clear_selections(){
  $('.selectable').each(function(){select_off_selectable($(this));});
  $('#selections').children().remove();
};

function add_to_selections(oid, disp_name){
  $('#selections').children('[title="' + oid + '"]').remove();
  $('#selections').append('<li title="' + oid + '">' + disp_name + '</li>');
  update_selections_number();
};
function remove_from_selections(oid){
  $('#selections').find('[title="' + oid + '"]').remove();
  update_selections_number();
};
function selected_objects(){
  return $.map($('#selections').children(), function(obj,i){ return $(obj).attr('title'); });
};

function select_on_selectable(target){
  var oid = target.attr("id");
  if (target.filter('.selected_item').size() > 0) {
    return;
  }
  target.addClass('selected_item').find(':checkbox').attr('checked', true);
  add_to_selections(oid, target.attr('title'));
};

function select_off_selectable(target){
  var oid = target.attr("id");
  if (target.filter('.selected_item').size() < 1) {
    return;
  }
  target.removeClass('selected_item').find(':checkbox').attr('checked', false);
  remove_from_selections(oid);
};

function show_detailbox_without_selection(event, modelname){
  var target = $(event.target).closest('.selectable,.unselectable');
  var oid = target.attr("id"); // in case of ipaddr, "id" has ipaddress string, instead of oid
  if (oid == null || oid == "") {return false; }
  show_detailbox(modelname, oid, event.pageY - detailbox_offset(), false);
  return false;
};

function toggle_item_selection(event, modelname, single){
  var target = $(event.target).closest('.selectable');
  var oid = target.attr("id"); // in case of ipaddr, "id" has ipaddress string, instead of oid
  if (oid == null || oid == "") { return false; }

  var sibling_ids = target.parent().children().map(function(){return $(this).attr("id") || -1;});
  var target_obj_index = $.inArray(target.attr("id"), sibling_ids);

  if (single && target.filter('.selected_item').size() > 0) {
    select_off_selectable(target);
  }
  else if (single) {
    clear_selections();
    select_on_selectable(target);
  }
  else if (event.shiftKey && arguments.callee.last_clicked != undefined) {
    var listup = function(target, start, end) {
      if (end < start) { var tmp = end; end = start; start = tmp; }
      return $.grep(target.parent().children(), function(obj,i){return $(obj).filter('.selectable').size() > 0 && i >= start && i <= end;});
    };
    var start_obj_index = $.inArray($(selected_objects()).eq(-1).get()[0], sibling_ids);
    if (target.filter('.selected_item').size() > 0) {
      $(listup(target, start_obj_index, target_obj_index)).each(function(){select_off_selectable($(this));});
    }
    else {
      $(listup(target, start_obj_index, target_obj_index)).each(function(){select_on_selectable($(this));});
    }
  }
  else if (target.filter('.selected_item').size() > 0) {
    select_off_selectable(target);
  }
  else {
    select_on_selectable(target);
  }
  arguments.callee.last_clicked = target_obj_index;
  show_detailbox(modelname, oid, event.pageY - detailbox_offset(), false);
  return false;
};

function reload_table_rows(type, oids){
  if (! $.isArray(oids)) {
    oids = [oids];
  }
  $.each(oids, function(i, oid){
    var oldtarget = $('tr#' + oid);
    if (oldtarget.filter('.unupdatable').size() > 0) {
      return;
    }
    oldtarget.addClass('obsolete_row');
    $.get('/ybz/' + type + '/' + oid + '.tr.ajax?t=' + (new Date()).getTime(), null, function(data){
      oldtarget.after(data);
      $('tr.obsolete_row#' + oid).remove();
      var target = $('tr#' + oid);
      regist_event_listener(target);
      if ($('#selections').children('[title="' + oid + '"]').size() > 0) {
        target.addClass('selected_item').find(':checkbox').attr('checked', true);
        add_to_selections(oid, target.attr('title'));
      }

      var orig_color = target.css('background-color');
      target.animate({backgroundColor:'yellow'}, 250, null, function(){
        target.animate({backgroundColor:orig_color}, 250, null, function(){
          target.removeAttr('style');
        });
      });
    });
  });
};

function detailbox_offset(){
  var topmargin_h = $("#appheader").outerHeight();
  var toolbox_h = $("#toolbox_spacer_top").outerHeight() + $("#toolbox_spacer_bottom").outerHeight() + $("#toolbox").outerHeight();
  return topmargin_h + toolbox_h;
};

function toggle_detailbox(event){
  $('#detailbox').toggle();
  $('#notesbox').toggle();
  return false;
};

function show_detailbox(type, oid, ypos, toggled, callback){
  var dboxarea = $('#detailboxarea');
  dboxarea.load('/ybz/' + type + '/' + oid + '.ajax?t=' + (new Date()).getTime(), null, function(){replace_detailbox(ypos, toggled, callback);});
};

function reload_detailbox(callback){
  var oid = $('#detailbox > .identity').children("input[name='oid']").val();
  var type = $('#detailbox > .identity').children("input[name='type']").val();
  var ypos = $('#detailbox').css("top");
  var toggled = false;
  if ($('#notesbox').size() > 0 && "none" != $('#notesbox').css("display")) {
    toggled = true;
  }
  show_detailbox(type, oid, ypos, toggled, callback);
};

function replace_detailbox(ypos, toggled, callback){
  if (ypos == null) {
    ypos = 0;
  }
  var dbox = $('#detailbox');
  var nbox = $('#notesbox');

  if (ypos + dbox.outerHeight() > $('#detailboxarea').innerHeight()) {
    ypos = $('#detailboxarea').innerHeight() - dbox.outerHeight();
  }
  if (ypos < $('#selectionbox').outerHeight() + 10) {
    ypos = $('#selectionbox').outerHeight() + 10;
  }
  dbox.css("top", ypos);
  nbox.css("top", ypos);
  if (toggled) {
    dbox.hide();
    nbox.show();
  }
  else {
    dbox.show();
    nbox.hide();
  };
  $('#boxtoggle_notes').unbind().click(toggle_detailbox);
  $('#boxtoggle_main').unbind().click(toggle_detailbox);

  bind_events_detailbox();
  if (callback) { callback(); }
};

function clone_cloneable_item(event){
  var cloneable_box = $(event.target).closest('div.cloneablebox');
  var count = cloneable_box.find('div.cloneable,div.cloneableline').size();
  var sibling_last = cloneable_box.find('div.cloneable,div.cloneableline').eq(count - 1);
  var cloned_from = $(event.target).closest('div.cloneable,div.cloneableline');
  var cloned_from_id = cloned_from.find('input.cloneable_number').val();
  var cloned_to = cloned_from.clone(true);
  var cloned_to_id = parseInt(sibling_last.find('input.cloneable_number').val()) + 1;
  cloned_from.find('select').each(function(){ // select.value is not cloned in $().clone, so set by hand.
    cloned_to.find('select').filter('[name="' + $(this).attr('name') + '"]').val($(this).val());
  });
  cloned_to.find('select,input').each(function(){ // replace name of input/select tags (value is cloneed above)
    $(this).attr('name', $(this).attr('name').replace(cloned_from_id, cloned_to_id));
  });
  cloned_to.find('input.cloneable_number').val(cloned_to_id);
  cloned_to.find('input.blank_onclone').val('');
  cloned_to.insertAfter(sibling_last);
  searchFieldCheckInit(cloned_to.find('select.search_field_select').get(0));
};

function commit_mainview_form(form, success_message, on_success_callback, on_error_callback) {
  $(form).ajaxSubmit({
    success: function(data, datatype){show_success_dialog(success_message, data, on_success_callback);},
    error: function(xhr){show_error_dialog(xhr.responseText, on_error_callback);}
  });
  return false;
};

function commit_smartadd_form(event) {
  $(event.target).ajaxSubmit({
    success: reload_page,
    error: function(xhr){show_error_dialog(xhr.responseText);}
  });
  event.preventDefault();
  return false;
};

function commit_field_change(event) {
  var form = $(event.target).closest('form.field_edit_form');
  commit_field_form(form, function(){form.find('div.dataedit').find(':input').filter(':visible').focus();});
  event.preventDefault();
  return false;
};

function commit_order_change(event) {
  var swapfrom_valueitem = $(event.target).closest('li.valueitem');
  var swapfrom = swapfrom_valueitem.children('div.dataedit').children('input');
  var swapto_valueitem = null;
  if ($(event.target).attr('name') == 'up') {
    swapto_valueitem = swapfrom_valueitem.prev();
  }
  else {
    swapto_valueitem = swapfrom_valueitem.next();
  }
  var swapto = swapto_valueitem.children('div.dataedit').children('input');

  var tmp = swapfrom.val();
  swapfrom.val(swapto.val());
  swapto.val(tmp);
  
  commit_field_form($(event.target).closest('form.field_edit_form'), reload_detailbox);
  event.preventDefault();
  return false;
};

function commit_field_form(form, on_error_callback) {
  var fieldname = $(form).children("input[name='field']").val();
  var type = $('#detailbox > .identity').children("input[name='type']").val();
  var oid = $('#detailbox > .identity').children("input[name='oid']").val();
  $(form).ajaxSubmit({
    success: function(){reload_detailbox(function(){reload_table_rows(type, [oid]);});},
    error: function(xhr){show_error_dialog(xhr.responseText, on_error_callback);}
  });
  return false;
};

function commit_toggle_form(event) {
  var type = $('#detailbox > .identity').children("input[name='type']").val();
  var oid = $('#detailbox > .identity').children("input[name='oid']").val();
  $(event.target).ajaxSubmit({
    success: function(){reload_detailbox(function(){reload_table_rows(type, [oid]);});},
    error: function(xhr){show_error_dialog(xhr.responseText);}
  });
  event.preventDefault();
  return false;
};

function highlight_editable_item(event) {
  var target = $(event.target).closest('.clickableitem').children('div.dataview');
  target.addClass('dataviewhighlighted');

  target.children('div.dataeditbutton')
    .css('display', 'inline')
    .children('img.clickablebutton').unbind().click(show_editable_item);

  if (target.closest('.valueslist').find('input').filter(':visible').size() < 1) {
    target.siblings('div.dataupdown').css('display', 'inline');
    target.siblings('div.dataupdown').children('img.orderedit').unbind().click(commit_order_change);
  }
};

function un_highlight_editable_item(event) {
  var target = $(event.target).closest('.clickableitem').children('div.dataview');
  target.removeClass('dataviewhighlighted');
  target.children('div.dataeditbutton').hide();
  target.siblings('div.dataupdown').hide();
};

function show_editable_item(event) {
  var group = $(event.target).closest('.clickableitem,.memoitem');
  group.children('.dataview').hide();
  group.children('.dataedit').css('display', 'inline');
  group.children('.dataupdown').hide();

  if (group.children('.dataedit.combobox,.dataedit.selector').size() > 0) {
    /* combo box or selector setup */
    var box = group.children('.dataedit.combobox,.dataedit.selector');
    box.children('div.comboinput').hide();
    box.children('div.comboselect,div.selectorbox').children('select')
      .unbind()
      .blur(rollback_selectable_item)
      .blur(rollback_editable_item)
      .change(change_selectable_item)
      .focus();
  }
  else if (group.children('.dataedit.memoarea').size() > 0) {
    /* textarea memo setup */
    var inputarea = group.children('.dataedit').children('textarea');
    inputarea.addClass('datainput')
      .unbind()
      .focus(function(){this.select();})
      .focus();
    group.children('.dataedit').children('input[name="memoupdate"]')
      .click(function(e){$(e.target).closest('form.field_edit_form').submit(); return false;});
    group.children('.dataedit').children('input[name="memocancel"]')
      .click(rollback_editable_area);
  }
  else {
    /* normal ajax input text setup */
    var inputbox = group.children('.dataedit').children('input');
    inputbox.addClass('datainput')
      .unbind()
      .focus(function(){this.select();})
      .blur(rollback_editable_item)
      .keypress(function(e){if(e.which == 13){$(e.target).closest('form.field_edit_form').submit();};})
      .focus();
  }

};

function rollback_selectable_item(event) {
  var pre_val = $(event.target).closest('.clickableitem').children('.dataview').attr('title');
  var selectable = $(event.target).closest('.dataedit').children('.div.comboselect').children('select');
  if (pre_val == '') { selectable.val('___blank'); }
  else { selectable.val(pre_val); }
};

function rollback_editable_area(event) {
  var group = $(event.target).closest('.memoitem');
  group.children('div.dataedit').find('textarea[name="value"]').val(group.find('textarea.valueholder').val());
  group.children('.dataedit').hide();
  group.children('.dataview').show();
};

function rollback_editable_item(event) {
  var group = $(event.target).closest('.clickableitem');
  group.children('div.dataedit').find("input[name='value']").val(group.children('.dataview').attr('title'));
  group.children('.dataedit').hide();
  group.children('.dataview').show();
};

function show_add_item(event) {
  var div1 = $(event.target).closest('div.field').siblings('ul.valueslist').children('li.addinput');
  var div2 = div1.children('div');
  div1.show();
  div2.show();

  div2.children('input')
    .addClass('datainput')
    .unbind()
    .focus(function(){this.select();})
    .blur(hide_add_item)
    .keypress(function(e){if(e.which == 13){$(e.target).closest('form.field_edit_form').submit();};})
    .focus();
};

function hide_add_item(event) {
  var target = $(event.target).closest('li.addinput');
  $(event.target).val('');
  target.hide();
};

function change_selectable_item(event) {
  var selected_val = $(event.target).val();
  if (selected_val == '___blank') {
    return false;
  }
  else if (selected_val == '___input') {
    $(event.target).unbind();
    switch_combobox_input(event);
  }
  else {
    $(event.target).closest('.dataedit').find("input[name='value']").val(selected_val);
    commit_field_change(event);
  }
};

function switch_combobox_input(event) {
  var dataedit = $(event.target).closest('.combobox');
  dataedit.children('div.comboselect').hide();
  dataedit.children('div.comboinput').show();
  dataedit.children('div.comboinput').children('input')
    .addClass('datainput')
    .unbind()
    .focus(function(){this.select();})
    .blur(rollback_selectable_item)
    .blur(rollback_editable_item)
    .keypress(function(e){if(e.which == 13){$(e.target).closest('form.field_edit_form').submit();};})
    .focus();
};

function searchFieldCheck ( elem ) {
  var e = $( elem );
  if ( typeof( e.attr('name') ) != 'undefined' ) {
    var vName = e.attr('name').replace('field','value');
    var vText = $("td > input[name="+ vName +"]");
    var vSelect = $("td > select[name="+ vName +"]");
    if ( e.val() === 'status' ) {
      if (vSelect.attr('disabled')) {
        vSelect.attr('disabled', false);
        vSelect.show();
        vText.attr('disabled', true);
        vText.hide();
      }
    }
    else {
      if (vText.attr('disabled')) {
        vSelect.attr('disabled', true);
        vSelect.hide();
        vText.val('');
        vText.attr('disabled', false);
        vText.show();
      }
    }
  }
}

function searchFieldCheckInit ( elem ) {
  searchFieldCheck( elem );
  $(elem).change(function(){
    searchFieldCheck( elem );
  });
}

function appendSortbarAfter ( elem, target_class ) {
  var bar = $('<tr class="sortbar"></tr>');
  bar.append('<th class="sortpad border_left">&nbsp;</th>');
  bar.append('<th class="sortbtn" target="displayname">ホスト名</th>');
  bar.append('<th class="sortpad">&nbsp;</th>');
  bar.append('<th class="sortbtn" target="ipaddresses">IPアドレス</th>');
  bar.append('<th class="sortpad">&nbsp;</th>');
  bar.append('<th class="sortpad">&nbsp;</th>');
  bar.append('<th class="sortbtn" target="service">サービス名</th>');
  bar.append('<th class="sortpad">&nbsp;</th>');
  bar.append('<th class="sortbtn" target="hwid">HWID</th>');
  bar.append('<th class="sortpad">&nbsp;</th>');
  bar.append('<th class="sortbtn" target="rackunit">Rackunit</th>');
  bar.append('<th class="sortbtn" target="alert">監視</th>');
  bar.append('<th class="sortpad">&nbsp;</th>');
  bar.append('<th class="sortpad border_right">&nbsp;</th>');
  bar.children('th.sortbtn').each(function(){
    $(this).attr('title', $(this).text()+'でソート');
  });
  if ( target_class ) {
    bar.attr( 'target', target_class ); 
  }
  elem.after( bar );
  return bar;
}

function appendHyperVisorSortbarAfter ( elem, target_class ) {
  var bar = $('<tr class="sortbar"></tr>');
  bar.append('<th class="sortpad border_left">&nbsp;</th>');
  bar.append('<th class="sortbtn" target="displayname">ホスト名</th>');
  bar.append('<th class="sortbtn" target="cpu">CPU Free</th>');
  bar.append('<th class="sortbtn" target="memory">MEM Free</th>');
  bar.append('<th class="sortbtn" target="disk">HDD Free</th>');
  bar.append('<th class="sortbtn" target="service">サービス名</th>');
  bar.append('<th class="sortpad">&nbsp;</th>');
  bar.append('<th class="sortbtn" target="hwid">HWID</th>');
  bar.append('<th class="sortpad">&nbsp;</th>');
  bar.append('<th class="sortbtn" target="rackunit">Rackunit</th>');
  bar.append('<th class="sortbtn" target="alert">監視</th>');
  bar.append('<th class="sortpad">&nbsp;</th>');
  bar.append('<th class="sortpad border_right">&nbsp;</th>');
  bar.children('th.sortbtn').each(function(){
    $(this).attr('title', $(this).text()+'でソート');
  });
  if ( target_class ) {
    bar.attr( 'target', target_class ); 
  }
  elem.after( bar );
  return bar;
}

function sortByColumn ( e ) {
  var elem = $(e);
  var numeric_sort_pattern = /^host_(cpu|memory|disk)$/;
  var target_class = elem.parent('tr').attr('target');
  var target_column = 'host_' + elem.attr('target');
  var target = [];
  var sort_field_fetch = function ( v ) {
    return $(v).children('td.'+target_column).text().replace(/^\s+/,"");
  };
  if ( target_column.match( numeric_sort_pattern ) ) {
    sort_field_fetch = function ( v ) {
      return parseInt( $(v).children('td.'+target_column).text() );
    };
  }

  elem.parent('tr').parent('tbody').children('tr').each( function(){
    if ( $(this).attr('class').match('host_outline') ) {
      if ( $($(this).children('td').get(0)).attr('class') == target_class || target_class == 'all' ) {
        target.push( $(this) );
        $(this).remove();
      }
    }
  } );
  var psUrl;
  if( elem.attr('order') == 'asc' ) {
    elem.attr('order','desc');
    $('span.sortorder').text('↓');
    $('span.sortorder').attr('title', '降順');
    target.sort(function(a,b){
      return ( sort_field_fetch(b) > sort_field_fetch(a) ? 1 : -1 );
    });
    psUrl = buildSortUrl( target_column, 'desc', target_class );
    history.pushState(null, elem.text()+':'+'降順', psUrl);
  }
  else if( elem.attr('order') == 'desc' ) {
    elem.attr('order','asc');
    $('span.sortorder').text('↑');
    $('span.sortorder').attr('title', '昇順');
    target.sort(function(a,b){
      return ( sort_field_fetch(a) > sort_field_fetch(b) ? 1 : -1 );
    });
    psUrl = buildSortUrl( target_column, 'asc', target_class );
    history.pushState(null, elem.text()+':'+'昇順', psUrl);
  }
  else {
    $('th.sortbtn').attr('order', false);
    $('span.sortorder').remove();
    elem.attr('order','asc');
    elem.html(elem.html()+'<span class="sortorder" title="昇順">↑</span>');
    target.sort(function(a,b){
      return ( sort_field_fetch(a) > sort_field_fetch(b) ? 1 : -1 );
    });
    psUrl = buildSortUrl( target_column, 'asc', target_class );
    history.pushState(null, elem.text()+':'+'昇順', psUrl);
  }
  $.each( target.reverse(), function(i, e){
    $(e).click(function(ee){
      toggle_item_selection(ee, 'host');
    });
    elem.parent('tr').after(e);
  });
}

function getParams () {
  var rtn;
  if ( location.search ) {
    rtn = {};
    $.each( location.search.substring(1).split(/&/), function(i, kv) {
      var m = kv.split(/=/);
      var key = m[0];
      var val = m[1];
      rtn[key] = val;
    } );
  }
  return rtn;
}

function serializeParams ( params ) {
  var kv = [];
  $.each( params, function( key, val ){
    kv.push( key + '=' + val );
  });
  return kv.join('&');
}

function buildSortUrl ( sortby, order, sort_stat ) {
  var params = getParams() || {} ;
  params.sortby = sortby;
  params.order = order;
  params.sort_stat = sort_stat;
  return location.pathname + '?' + serializeParams( params );
}

function sortByUrl () {
  var params = getParams();
  if ( params ) {
    if ( params.sortby ) {
      params.order = params.order ? params.order : 'asc' ;
      params.sort_stat = params.sort_stat ? params.sort_stat : 'host_status_in_service' ;
      var dom_order = params.order == 'asc' ? 'desc' : 'asc' ;
      var order_label = params.order == 'desc' ? '↓'  : '↑' ;
      var order_title = params.order == 'desc' ? '降順' : '昇順' ;
      var sortby = params.sortby.replace(/^host_/,"");
      var elem = $('tr.sortbar[target='+params.sort_stat+'] > th.sortbtn[target='+sortby+']');
      elem.attr('order', dom_order);
      elem.click();
      elem.html(elem.html()+'<span class="sortorder" title="'+order_title+'">'+order_label+'</span>');
    }
  }
}

function select_hypervisor(e){
  var elem = $(e);
  var name = elem.attr('name');
  var input = elem.closest('td').find('input[name='+name+']');
  var loading = elem.closest('td').find('span.loading');
  var host_box = elem.closest('div.hostadd_item.cloneable');
  var host_num = host_box.find('input.cloneable_number').val();
  var f = function ( field_name ) { 
    var name = field_name+host_num;
    return host_box.find('input[name='+ name +'],select[name='+ name +']');
  };
  var hv = function ( attr_name ) {
    return elem.children(':selected').attr( attr_name );
  };
  if ( elem.val() == 'OTHER' ) {
    elem.hide().attr('disabled',true);
    input.show().attr('disabled',false);
  }
  else if ( elem.val().length > 0 ) {
    f('type').val('Xen(DomU)');
    f('hwinfo').children('option').each(function( i, opt ){
      if ( $(opt).text() == 'xen' ) {
        f( 'hwinfo' ).val( $(opt).attr('value') );
      }
    });
    $.each( ['rackunit','hwid'], function( i, k ) {
      f( k ).val( hv( k ) );
    });
    $.each( ['os'], function( i, k ) {
      f( k ).children('option').each(function( j, opt ){
        if ( $(opt).text() == hv( k ) ) {
          f( k ).val( $(opt).attr('value') );
        }
      });
    });
  }
  var selected_hv = elem.children(':selected');
  if ( selected_hv.size() > 0 ) {
    if ( selected_hv.attr('ip') ) {
      var exclude = $.grep( $('input'), function(n, i){
        return ( $(n).attr('name').match(/^localips\d+$/) && $(n).val().length > 0 );
      }).map(function(n){return $(n).val();});
      suggest_ip( selected_hv.attr('ip'), exclude, function(json){
        $.each( elem.closest('div.hostadd_item.cloneable').find('input'), function(i, n){
          if ( $(n).attr('name').match(/^localips\d+$/) ) {
            $(n).val(json.localip);
          }
        });
      });
    }
  }
}

function get_hypervisors(elem, cb){
  var srv_id = elem.val();
  $.ajax({
    url: '/ybz/hosts/suggest/service/'+srv_id+'.json',
    success: function(hvlist){
      var list = [];
      $.each(hvlist, function(i,hv){
        list.push( hv_to_option( hv ) );
      });
      cb(list);
    }
  });
}

function set_suggests(hvlist){
  $('div.hidden.suggested_items').empty();
  $.each(hvlist, function(i,hv){
    $('div.hidden.suggested_items').append(hv);
  });
}

function hv_to_option(hv){
  var host = hv.host;
  var option = $('<option />');
  option.attr({
    'class': 'hypervisor_item',
    'value': host.oid,
    'cpu': host.content.cpu,
    'disk': host.content.disk,
    'hwid': host.content.hwid,
    'hwinfo': host.content.hwinfo,
    'memory': host.content.memory,
    'os': host.content.os,
    'rackunit': host.content.rackunit,
    'ip': host.localip
  });
  option.text( host.display+' | '+host.content.rackunit );
  if ( host.content.globalips.length > 0 ) {
    option.text( option.text()+' | ['+host.content.globalips.join(', ')+']' );
  }
  return option;
}

function get_suggests(){
  return $('div.hidden.suggested_items').html();
}

function suggest_head(){
  return $('<option />').val('').text('(選択なし)');
}

function suggest_foot(label){
  label = label ? label : 'その他のハイパーバイザ';
  return $('<option />').val('OTHER').text(label);
}

function set_resultbox(hvlist){
  var resultbox = get_resultbox();
  var select = resultbox.children('select');
  select.html('');
  $.each(hvlist, function(i,hv){
    select.append(hv);
  });
  if ( select.children('option').size() > 0 ) {
    resultbox.show();
    select.prepend(suggest_head()).append(suggest_foot('入力された値で予測')).attr('size', select.children('option').size());
  }
  else {
    resultbox.hide();
  }
}

function get_resultbox(){
  return $('div.hidden.resultbox');
}

function find_from_suggested(e){
  var query = $(e).val();
  var select = $(e).closest('td').find('select');
  var select_foot = select.children('option[value=OTHER]');
  var resultbox = get_resultbox();
  set_resultbox( 
    $.grep( $(get_suggests()), function(n, i){
      return $(n).text().match(query) ? true : false;
    })
  );
  resultbox.css({
    'top': parseInt($(e).position().top) + 26,
    'left': parseInt($(e).position().left)
  }).unbind('change').change(function(){
    var selected = $(this).find(':selected').clone();
    var selected_value = selected.attr('value');
    if (selected_value == 'OTHER') {
      guess_dom0(query, function(hvlist){
        if (typeof(hvlist[0]) != 'undefined') {
          if ( select.children('option[value='+hvlist[0].host.oid+']').size() < 1 ) {
            select_foot.before( hv_to_option(hvlist[0]) );
          }
          select.val( hvlist[0].host.oid ).change();
          select.show().attr('disabled',false);
          resultbox.hide().attr('disabled',true);
          $(e).hide().attr('disabled',true);
        }
      });
    }
    else {
      if ( select.children('option[value='+selected_value+']').size() < 1 ) {
        select_foot.before( selected );
      }
      select.val(selected_value).change();
      select.show().attr('disabled',false);
      resultbox.hide().attr('disabled',true);
      $(e).hide().attr('disabled',true);
    }
  });
}

function guess_dom0(str, cb){
  $.ajax({
    url: '/ybz/hosts/suggest/guess.json?q='+str,
    success: cb
  });
}

function suggest_ip(dom0_ip, exclude, cb){
  var params = {
    'ip': dom0_ip,
    'ex[]': exclude
  };
  $.ajax({
    url: '/ybz/ipaddress/suggest.json',
    data: params,
    success: cb
  });
}

function item_clone_kb_shortcut(){
  $($('div.listclone').get(0)).click();
  $('span.hostadd_item_count').text($('div.listclone').size());
}
