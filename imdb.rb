# uses the neography gem, see: https://github.com/maxdemarzi/neography
# see http://wiki.neo4j.org/content/Using_the_Neo4j_Server_with_Ruby

require 'rubygems'
require 'neography'
require 'sinatra/base'
require 'uri'


module Neography
  class Rest
    def get_type(type)
        case type
          when :node, "nodes", :nodes, "nodes"
            "node"
          when :relationship, "relationship", :relationships, "relationships"
            "relationship"
          when :path, "path", :paths, "paths"
            "path"
          when :fullpath, "fullpath", :fullpaths, "fullpaths"
            "fullpath"
          else
            "node"
        end
      end
  end
end

class Imdb < Sinatra::Base
set :haml, :format => :html5 
set :app_file, __FILE__

include Neography


configure do
    env = ENV['NEO4J_ENV'] || "development"

    if env == "development"
      require 'net-http-spy'
      Net::HTTP.http_logger_options = {:verbose => true} 
    end

  Config.server = ENV['NEO4J_HOST']
  Config.authentication = 'basic'
  Config.username = ENV['NEO4J_LOGIN']
  Config.password = ENV['NEO4J_PASSWORD']

end

before do
  @neo = Neography::Rest.new({
    :server => ENV['NEO4J_HOST'],
#    :directory => "/#{ENV['NEO4J_INSTANCE']}",
    :authentication => 'basic',
    :username => ENV['NEO4J_LOGIN'] , 
    :password => ENV['NEO4J_PASSWORD']
    })
  @bacon = @neo.get_node_index("exact", "name", URI.escape("Bacon, Kevin")).first
end


helpers do
  def link_to(url, text=url, opts={})
    attributes = ""
    opts.each { |key,value| attributes << key.to_s << "=\"" << value << "\" "}
    "<a href=\"#{url}\" #{attributes}>#{text}</a>"
  end
end

get '/' do
  haml :search_results
end

def expand_word_node(word_nodes, type, name_param)
  return nil if !word_nodes
  word_nodes.collect { |word_node|
    @neo.traverse(word_node, :node, neighbours(type, "out")).collect{ | node |
      { "self" => node["self"], "data" => node["data"] }
    }
  }.flatten.sort{ | node1, node2 | node1["data"][name_param] <=> node2["data"][name_param]}
end

post '/search' do
  @search =  params["search"].downcase
  @escaped_search = URI.escape(@search)
  #@exact_movies = @neo.get_node_index("exact", "title", @escaped_search)
  #@exact_actors = @neo.get_node_index("exact", "name", @escaped_search)
  @search_movies = @neo.get_node_index("search", "title.part", @escaped_search)
  @search_actors = @neo.get_node_index("search", "name.part", @escaped_search)

  @search_actors=expand_word_node(@search_actors,"PART_OF_NAME", "name")
  @search_movies=expand_word_node(@search_movies,"PART_OF_TITLE", "title")

#  $stderr.puts @search_actors.inspect
#  $stderr.puts @search_movies.inspect
  haml :search_results
end

def neighbours(type, direction)
  {"order" => "depth first",
                 "uniqueness" => "node global",
                 "relationships" => [{"type"=> type, "direction" => direction}],
                 "return filter" => {"language" => "builtin", "name" => "all but start node"},
                 "depth"         => 1}
end

get '/movie/:id' do
  @movie = @neo.get_node(params[:id])

  @roles = @neo.traverse(@movie, "fullpath", neighbours("ACTS_IN","in")).collect{ | path |
      { "actor_name" => path["end"]["data"]["name"],
        "actor_link" => "/actor/" + path["end"]["self"].split("/").last,
        "data" => path["relationships"].last["data"] }
      }.flatten.sort{ | node1, node2 | (node1["data"]["role"]||"") <=> (node2["data"]["role"]||"")}

  @bacon_path = @neo.get_path(@movie, 2122, {"type"=> "ACTS_IN"}, depth=6, algorithm="shortestPath")
  @bacon_nodes = @bacon_path["nodes"].collect{ |n| @neo.get_node(n)}
  
  haml :show_movie
end

get '/actor/:id' do
  @actor = @neo.get_node(params[:id])

  @roles = @neo.traverse(@actor, "fullpath", neighbours("ACTS_IN","out")).collect{ | path |
      { "movie_title" => path["end"]["data"]["title"],
        "movie_link" => "/movie/" + path["end"]["self"].split("/").last,
        "data" => path["relationships"].last["data"] }
      }.flatten.sort{ | node1, node2 | (node1["data"]["role"]||"") <=> (node2["data"]["role"]||"")}


  @bacon_path = @neo.get_path(@actor, 2122, {"type"=> "ACTS_IN"}, depth=6, algorithm="shortestPath")
  @bacon_nodes = @bacon_path["nodes"].collect{ |n| @neo.get_node(n)}

  haml :show_actor
end

get '/v2' do
   '<h2>Neo4j Imdb</h2>' + Neography.ref_node.inspect + '<br\>' + '<h3>Node Indexes</h3>' + @neo.list_node_indexes.inspect + '<h3>Node Indexes</h3>' + @neo.list_relationship_indexes.inspect 
end

get '/actor_v2/:id' do
  @actor = Node.load(params[:id])  
  @roles = @actor.rels("ACTS_IN").outgoing

  haml :show_actor_v2
end

get '/movie_v2/:id' do
  @movie = Node.load(params[:id])  
  @roles = @movie.rels("ACTS_IN").incoming

  haml :show_movie_v2
end


  run! if app_file == $0
end
