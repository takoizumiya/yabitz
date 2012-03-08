# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
  ### smart search ###
  get %r!/ybz/smartsearch(\.json|\.csv)?! do |ctype|
    authorized?
    searchparams = request.params['keywords'].strip.split(/\s+/)
    @page_title = "簡易検索 結果"
    @service_results = []
    @results = []
    @brick_results = []
    searchparams.each do |keyword|
      search_props = Yabitz::SmartSearch.kind(keyword)
      search_props.each do |type, name, model|
        if model == :service
          @service_results.push([name + ": " + keyword, Yabitz::SmartSearch.search(type, keyword)])
        elsif model == :brick
          @brick_results.push([name + ": " + keyword, Yabitz::SmartSearch.search(type, keyword)])
        else
          @results.push([name + ": " + keyword, Yabitz::SmartSearch.search(type, keyword)])
        end
      end
    end

    Stratum.preload(@results.map(&:last).flatten, Yabitz::Model::Host) if @results.size > 0 and @results.map(&:last).flatten.size > 0
    case ctype
    when '.json'
      response['Content-Type'] = 'application/json'
      # ignore service/brick list for json
      @results.map(&:last).flatten.to_json
    when '.csv'
      response['Content-Type'] = 'text/csv'
      # ignore service/brick list for csv
      Yabitz::Model::Host.build_raw_csv(Yabitz::Model::Host::CSVFIELDS_LL, @results.map(&:last).flatten)
    else
      @copypastable = true
      @service_unselectable = true
      @brick_unselectable = true
      haml :smartsearch, :locals => {:cond => searchparams.join(' ')}
    end
  end
end
