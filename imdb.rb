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
    env = ENV['NEO4J_ENV'] && "development"
    $stderr.puts env
    if env == "development"
      require 'net-http-spy'
      Net::HTTP.http_logger_options = {:verbose => true} 
    end

  Config.server = ENV['NEO4J_HOST'] ||'ec2-184-73-42-24.compute-1.amazonaws.com'
  Config.directory = '/' + (ENV['NEO4J_INSTANCE'] ||'imdb')
  Config.authentication = 'basic'
  Config.username = ENV['NEO4J_LOGIN'] ||'imdb'
  Config.password = ENV['NEO4J_PASSWORD']||'dbmi'

end

before do
  @neo = Neography::Rest.new()
#  @neo = Neography::Rest.new({
#    :server => ENV['NEO4J_HOST'],
#    :directory => "/#{ENV['NEO4J_INSTANCE']}",
#    :authentication => 'basic',
#    :username => ENV['NEO4J_LOGIN'] ,
#    :password => ENV['NEO4J_PASSWORD']
#    })
#  @bacon = @neo.get_node_index("exact", "name", URI.escape("Bacon, Kevin")).first
  @time = Time.now.to_f
  @times = []
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

def trace(name, data = nil)
    size = ""
    size = " "+(data.to_s.length/1024).to_s+" kB" if data
    time = Time.now.to_f
    @times << [name.to_s + size , ((time - @time)*1000).to_i]
    @time = time
end

post '/search' do
  @search =  params["search"].downcase
  @escaped_search = URI.escape(@search)
  #@exact_movies = @neo.get_node_index("exact", "title", @escaped_search)
  #@exact_actors = @neo.get_node_index("exact", "name", @escaped_search)
  @search_movies = @neo.get_node_index("search", "title.part", @escaped_search)
  trace(:search_movies,@search_movies)
  @search_actors = @neo.get_node_index("search", "name.part", @escaped_search)
  trace(:search_actors,@search_actors)
  @search_actors=expand_word_node(@search_actors,"PART_OF_NAME", "name")
  trace(:expand_actors,@search_actors)
  @search_movies=expand_word_node(@search_movies,"PART_OF_TITLE", "title")
  trace(:expand_movies,@search_movies)

#  $stderr.puts @search_actors.inspect
#  $stderr.puts @search_movies.inspect
  haml :search_results
end

def node_id(node)
  node["self"].split("/").last
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
  trace(:movie)
  @roles = @neo.traverse(@movie, "node", neighbours("ACTS_IN","in"))
  trace(:fetch_roles_nodes,@roles)
  @roles = @neo.traverse(@movie, "path", neighbours("ACTS_IN","in"))
  trace(:fetch_roles_path,@roles)
  @roles = @neo.traverse(@movie, "fullpath", neighbours("ACTS_IN","in"))
  trace(:fetch_roles_fullpath,@roles)
  @roles = @roles.collect{ | path |
      { "actor_name" => path["end"]["data"]["name"],
        "actor_link" => "/actor/" + node_id(path["end"]),
        "data" => path["relationships"].last["data"] }
      }.flatten.sort{ | node1, node2 | (node1["data"]["role"]||"") <=> (node2["data"]["role"]||"")}
  trace(:parse_roles,@roles)
  @bacon_path = @neo.get_path(@movie, 2122, {"type"=> "ACTS_IN"}, depth=6, algorithm="shortestPath")
  trace(:bacon_path,@bacon_path)
  @bacon_nodes = @bacon_path["nodes"].collect{ |n| @neo.get_node(n)}
  trace(:bacon_nodes,@bacon_nodes)
  haml :show_movie
end

get '/movie2/:id' do
  @movie = @neo.get_node(params[:id])
  trace(:movie)

  @roles = @neo.get_node_relationships(@movie, "in", "ACTS_IN")
  trace(:fetch_movie_relationships,@roles)
  @roles.each do |role|
    node = @neo.get_node(role["start"])
    role["actor_name"] = node["data"]["name"]
    role["actor_link"] = "/actor/" + node["self"].split('/').last
  end
  trace(:fetch_movie_actors,@roles)

  @bacon_path = @neo.get_path(@movie, 2122, {"type"=> "ACTS_IN"}, depth=6, algorithm="shortestPath")
  trace(:bacon_path)
  @bacon_nodes = @bacon_path["nodes"].collect{ |n| @neo.get_node(n)}
  trace(:bacon_nodes)
  haml :show_movie
end

get '/actor/:id' do
  @actor = @neo.get_node(params[:id])
  trace(:actor)

  @roles = @neo.traverse(@actor, "fullpath", neighbours("ACTS_IN","out"))
  trace(:fetch_roles,@roles)

  @roles = @roles.collect{ | path |
      { "movie_title" => path["end"]["data"]["title"],
        "movie_link" => "/movie/" + node_id(path["end"]),
        "data" => path["relationships"].last["data"] }
      }.flatten.sort{ | node1, node2 | (node1["data"]["role"]||"") <=> (node2["data"]["role"]||"")}
  trace(:parse_roles,@roles)


  @bacon_path = @neo.get_path(@actor, 2122, {"type"=> "ACTS_IN"}, depth=6, algorithm="shortestPath")
  trace(:bacon_path,@bacon_path)
  @bacon_nodes = @bacon_path["nodes"].collect{ |n| @neo.get_node(n)}
  trace(:bacon_nodes,@bacon_nodes)

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
