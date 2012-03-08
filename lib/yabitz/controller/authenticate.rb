# -*- coding: utf-8 -*-

require 'sinatra/base'

require 'haml'

class Yabitz::Application < Sinatra::Base
  ### 認証 ###
  get '/ybz/authenticate/login' do
    protected!
    if request.referer.nil? or request.referer.empty? or request.referer == '/'
      redirect '/ybz/services'
    end
    redirect request.referer
  end

  get '/ybz/authenticate/logout' do
    session[:username] = ""
    redirect '/ybz/services'
  end

  get '/ybz/authenticate/basic' do
    protected!
    "ok"
  end

  post '/ybz/authenticate/form' do
    pair = request.params().values_at(:username, :password)
    user = Yabitz::Model::AuthInfo.authenticate(*pair, request.ip)
    unless user
      response['WWW-Authenticate'] = %(Basic realm=BASIC_AUTH_REALM)
      throw(:halt, [401, "Not Authorized\n"])
    end
    "ok"
  end

end
