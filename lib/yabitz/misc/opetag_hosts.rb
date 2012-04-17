# -*- coding: utf-8 -*-

require_relative '../model'

module Yabitz
  module Opetag
    def self.hosts(opetag)
      return Yabitz::Model::TagChain.query(:tagchain => opetag).map{|t|
        Yabitz::Model::TagChain.retrospect(t.oid).select{|rt|
          last_tagchain = rt.tagchain.pop
          rt.tagchain.push( last_tagchain )
          last_tagchain == opetag
        }.map(&:host)
      }.flatten
    end
    def self.hosts_summary(opetag)
      hosts = self.hosts(opetag)
      summary = {}
      hosts.map{|h|
        if ! summary[h.status]
          summary[h.status] = 0
        end
        summary[h.status] = summary[h.status] + 1
      }
      return summary
    end
    def self.hosts_summary_string(opetag)
      summary = self.hosts_summary(opetag)
      labels = [];
      Yabitz::Model::Host::STATUS_LIST.map{|status|
        if summary[status]
          labels.push(Yabitz::Model::Host.status_title(status) + ':' + summary[status].to_s)
        end
      }
      return labels.join(', ')
    end
  end
end
