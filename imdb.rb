# uses the neography gem, see: https://github.com/maxdemarzi/neography
# see http://wiki.neo4j.org/content/Using_the_Neo4j_Server_with_Ruby

require 'rubygems'
require "neography"
require "sinatra"

set :haml, :format => :html5 

before '/*' do
  @neo = Neography::Rest.new({
    :server => ENV['NEO4J_HOST'],
    :directory => "/#{ENV['NEO4J_INSTANCE']}",
    :authentication => 'basic',
    :username => ENV['NEO4J_LOGIN'] , 
    :password => ENV['NEO4J_PASSWORD']
    })

# @neo = Neography::Rest.new
end


get '/' do
   '<h2>Neo4j Imdb</h2>' + @neo.get_root.inspect
end

get '/actors' do
  '<h2>Movies</h2>'
end


get '/movies' do
  '<h2>Actors</h2>'
end