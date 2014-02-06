require 'sinatra'
require "sinatra/reloader" if development?
require 'active_record'
require 'digest/sha1'
require 'pry'
require 'uri'
require 'open-uri'
require 'digest/sha1'
# require 'nokogiri'

###########################################################
# Configuration
###########################################################

set :public_folder, File.dirname(__FILE__) + '/public'

configure :development, :production do
    ActiveRecord::Base.establish_connection(
       :adapter => 'sqlite3',
       :database =>  'db/dev.sqlite3.db'
     )
end

# Handle potential connection pool timeout issues
after do
    ActiveRecord::Base.connection.close
end

# turn off root element rendering in JSON
ActiveRecord::Base.include_root_in_json = false

# set up session 
set :sessions => true
register do
  def auth (type)
    condition do
      if (session[:user_id])
        user = User.find_by_id(session[:user_id])
        id = user.id unless !user
      end
      redirect "/login" unless session[:user_id] && session[:user_id] == id
      ##redirect "/login" unless session[:user_id] && session[:user_id] == User.find(session[:user_id]).id
    end
  end
end


###########################################################
# Models
###########################################################
# Models to Access the database through ActiveRecord.
# Define associations here if need be
# http://guides.rubyonrails.org/association_basics.html

class Link < ActiveRecord::Base
    has_many :clicks

    validates :url, presence: true

    before_save do |record|
        record.code = Digest::SHA1.hexdigest(url)[0,5]
    end
end

class User < ActiveRecord::Base
end

class Click < ActiveRecord::Base
    belongs_to :link, counter_cache: :visits
end

loggedInUser = 0
###########################################################
# Routes
###########################################################
get '/', :auth => :user do
    erb :index
end

get '/login' do
  erb :login
  # return if loggedInUser == 0
  # session[:username] = User.find( loggedInUser ).username
  # session[:user_id] = loggedInUser # User.find_by_username('bob').id
  # "Hello #{session[:username]}"
end

get '/links', :auth => :user do
    links = Link.order("created_at DESC")
    links.map { |link|
        link.as_json.merge(base_url: request.base_url)
    }.to_json
end

post '/login' do
  user = User.find_by_username(params[:username])
  if !user || user.password_hash != Digest::SHA1.hexdigest(params[:password]+user.password_salt)[0,63]
    session[:user_id] = nil
    redirect to '/login'
  else
    session[:user_id] = user.id
    redirect to '/'
  end
end

post '/user' do
  if params[:password] != params[:password_confirm]
    puts "Password #{params[:password]} doesn't match #{params[:password_confirm]}"
    return "passwords don't match!"#redirect to '/login' # TODO display message instead?
  end
  username = params[:username]
  password_salt = Digest::SHA1.hexdigest( Random.rand( 10**10 ).to_s )
  password_hash = Digest::SHA1.hexdigest(params[:password]+ password_salt)[0,63]
  User.create(username: username, password_hash: password_hash, password_salt: password_salt)
  session[:user_id] = User.find_by_username( username ).id
  redirect to '/'
end

post '/links', :auth => :user do
    data = JSON.parse request.body.read
    uri = URI(data['url'])
    raise Sinatra::NotFound unless uri.absolute?
    link = Link.find_by_url(uri.to_s) ||
           Link.create( url: uri.to_s, title: get_url_title(uri) )
    link.as_json.merge(base_url: request.base_url).to_json
end

get '/:url', :auth => :user do
    link = Link.find_by_code params[:url]
    raise Sinatra::NotFound if link.nil?
    link.clicks.create!
    redirect link.url
end

###########################################################
# Utility
###########################################################

def read_url_head url
    head = ""
    url.open do |u|
        begin
            line = u.gets
            next  if line.nil?
            head += line
            break if line =~ /<\/head>/
        end until u.eof?
    end
    head + "</html>"
end

def get_url_title url
    # Nokogiri::HTML.parse( read_url_head url ).title
    result = read_url_head(url).match(/<title>(.*)<\/title>/)
    result.nil? ? "" : result[1]
end
