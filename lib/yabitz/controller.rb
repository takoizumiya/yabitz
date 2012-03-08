# -*- coding: utf-8 -*-


Dir::glob('lib/yabitz/controller/*.rb').each{ |file|
  require_relative file.sub('lib/yabitz/','').sub('.rb', '')
}
