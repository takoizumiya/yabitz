# -*- coding: utf-8 -*-

require_relative '../model'

module Yabitz
  module UnitNormalizer
    def self.memory ( mem )
      rtn = 0;
      mem_ptn = /^([\d\.]+?)(G|M)/
      if mem
        if mem.match(mem_ptn)
          m = mem.match(mem_ptn)
          rtn = m[2] == 'G' ? m[1].to_i * 1024 : m[1].to_i
        end 
      end
      return rtn
    end

    def self.cpu ( cpu )
      rtn = 1;
      cpu_ptn = /^(\d+)\s/
      if cpu
        if cpu.match(cpu_ptn)
          m = cpu.match(cpu_ptn)
          rtn = m[1].to_i
        end
      end
      return rtn
    end

    def self.disk ( disk )
      rtn = 0;
      disk_ptn = /^([\d\.]+)(G|T)/
      if disk
        disk.gsub(/\s/,"")
        if disk.match(disk_ptn)
          m = disk.match(disk_ptn)
          rtn = m[2] == 'T' ? m[1].to_i * 1024 : m[1].to_i
        end
      end
      return rtn
    end
  end

  class HyperVisor
    def initialize ( host )
      @host = host
      @memory_assigned = host.children.map{|child|Yabitz::UnitNormalizer.memory(child.memory)}.inject{|x,y|x+y} || 0
      @cpu_assigned = host.children.map{|child|Yabitz::UnitNormalizer.cpu(child.cpu)}.inject{|x,y|x+y} || 0
      @disk_assigned = host.children.map{|child|Yabitz::UnitNormalizer.disk(child.disk)}.inject{|x,y|x+y} || 0
    end
    attr_reader :host, :memory_assigned, :cpu_assigned
    def memory_unassigned ()
      return Yabitz::UnitNormalizer.memory( @host.memory ) - @memory_assigned
    end
    def cpu_unassigned ()
      return Yabitz::UnitNormalizer.cpu( @host.cpu ) - @cpu_assigned
    end
    def disk_unassigned ()
      return Yabitz::UnitNormalizer.disk( @host.disk ) - @disk_assigned
    end
    def to_tree
      return {
        :host => @host.to_tree,
        :memory_assigned => @memory_assigned.to_s + 'MB',
        :memory_unassigned => self.memory_unassigned.to_s + 'MB',
        :cpu_assigned => @cpu_assigned.to_s + 'cores',
        :cpu_unassigned => self.cpu_unassigned.to_s + 'cores',
        :disk_assigned => @disk_assigned.to_s + 'GB',
        :disk_unassigned => self.disk_unassigned.to_s + 'GB'
      }
    end
  end

  module Suggest
    def self.hosts ( srv )
      return Yabitz::Model::Host.query(:service => srv).select{|h| 
        h.status == Yabitz::Model::Host::STATUS_IN_SERVICE
      }.flatten.map{ | host |
        Yabitz::HyperVisor.new( host )
      }.sort{ | a, b |
        b.memory_unassigned <=> a.memory_unassigned
      }.sort{ | a, b |
        b.cpu_unassigned <=> a.cpu_unassigned
      }
    end
  end
end
