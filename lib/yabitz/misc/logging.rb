# -*- coding: utf-8 -*-

require 'stratum'

module Yabitz
  module Logging
    def self.log_auth(username, msg, oid=nil, sourceip='')
      Stratum.conn do |c|
        unless (oid.nil? || oid == '') then
          c.query("INSERT INTO auth_log SET username=?,msg=?,oid=?,sourceip=?", username, msg, oid, sourceip)
        else
          c.query("INSERT INTO auth_log SET username=?,msg=?,sourceip=?", username, msg, sourceip)
        end
      end
    end
  end
end
