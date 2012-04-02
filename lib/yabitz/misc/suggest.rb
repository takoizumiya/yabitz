# -*- coding: utf-8 -*-

require_relative '../model'

module Yabitz
  module Suggest
    def self.hosts ( srv )
      mem_normalizer = lambda { |mem|
        rtn = 0;
        mem_ptn = /^(\d+?)(G|M)/
        if mem
          if mem.match(mem_ptn)
            m = mem.match(mem_ptn)
            rtn = m[2] == 'G' ? m[1].to_i * 1024 : m[1].to_i
          end 
        end
        return rtn
      }

      cpu_normalizer = lambda { |cpu|
        rtn = 0;
        cpu_ptn = /^(\d+)\s/
        if cpu
          if cpu.match(cpu_ptn)
            m = cpu.match(cpu_ptn)
            rtn = m[1].to_i
          end
        end
        return rtn
      }

      gip_normalizer = lambda { |gip|
        return gip.size > 0 ? 1 : 0;
      }

      hosts = Yabitz::Model::Host.query(:service => srv).select{|h| 
        h.status == Yabitz::Model::Host::STATUS_IN_SERVICE
      }.flatten.sort{ | a, b |
        gip_normalizer.call( b.globalips ) <=> gip_normalizer.call( a.globalips )
      }.sort{ | a, b |
        mem_normalizer.call( b.memory ) <=> mem_normalizer.call( a.memory )
      }.sort{ | a, b |
        cpu_normalizer.call( b.cpu ) <=> cpu_normalizer.call( a.cpu )
      }
    end
  end
end

