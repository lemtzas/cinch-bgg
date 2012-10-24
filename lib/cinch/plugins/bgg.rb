require 'cinch'
require 'open-uri'
require 'nokogiri'
require File.expand_path(File.dirname(__FILE__)) + '/lib/bgg_api'

module Cinch
  module Plugins
    class Bgg
      include Cinch::Plugin

      USERS_FILE = "data/users"

      match /bgg (.+)/i,        method: :bgg
      match /bggme/i,           method: :bggself
      match /bgguser (.+)/i,    method: :bgguser
      match /bgguser -u (.+)/i, method: :bggactualuser

      match /link_bgg (.+)/i,   method: :link_to_bgg

      match /whohas (.+)/i,     method: :who_has_game

      def initialize(*args)
        super

        @bgg = BggApi.new
        @community = load_community
      end

      def bgg(m, title)
        game = search_bgg(m, title)
        unless game.nil?
          m.reply "#{game.name} (#{game.year}) - #{game.rating} - Rank: #{game.game_rank} - Designer: #{game.designers.join(", ")} - Mechanics: #{game.mechanics.join(", ")} - " <<
            "http://boardgamegeek.com/boardgame/#{game.id}", true
        end
      end

      def bgguser(m, nick)
        unless nick.start_with?("-u ")
          if self.in_community?(nick)
            name = self.find_bgg_by_irc(nick)
            user = search_for_user(name)
            m.reply "#{user.name} - Collection: #{user.collection.size} - Top 5: #{user.top_games.first(5).join(", ")} - http://boardgamegeek.com/user/#{user.name}", true
          else
            m.reply "There's no \"#{nick}\" in the community. To link yourself and join the community, \"!link_bgg bgg_username\". To search by actual bgg username, \"!bgguser -u bgg_username\".", true
          end
        end
      end

      def bggself(m)
        self.bgguser(m.user.nick)
      end

      def bggactualuser(m, nick)
        user = search_for_user(nick)
        m.reply "#{user.name} - Collection: #{user.collection.size} - Top 5: #{user.top_games.first(5).join(", ")} - http://boardgamegeek.com/user/#{user.name}", true        
      end

      def link_to_bgg(m, username)
        @community[m.user.nick] = username
        File.open(USERS_FILE, 'w') do |file|
          @community.each do |irc_nick, bgg_name|
            file.write("#{irc_nick},#{bgg_name}\n")
          end
        end
        m.reply "You are now added to the community!", true
      end

      def who_has_game(m, title)
        game = search_bgg(m, title)
        unless game.nil?
          community = @community.dup
          community.each{ |irc, bgg| community[irc] = search_for_user(bgg, { :id => game.id }) }
          
          community.keep_if{ |irc, user| user.collection.include? game.id.to_s }
            m.reply "Owning \"#{game.name}\": #{community.keys.join(", ")}", true
        end
      end

      #--------------------------------------------------------------------------------
      # Protected
      #--------------------------------------------------------------------------------
      protected

      def search_bgg(m, search_string)
        search_results = @bgg.search({:query => search_string, :type => 'boardgame', :exact => 1})
        if search_results['total'] == "0"
          search_results = @bgg.search({:query => search_string, :type => 'boardgame'})
        end
        search_results = search_results["item"].map { |i| i['id'].to_i }
        
        # this is dumb, find a better way
        if search_results.empty?
          m.reply "\"#{title}\" not found", true
        elsif search_results.size > 50
          m.reply "\"#{title}\" was too broad of a search term", true
        else
          results = search_results.map do |id|
            Game.new(id, get_info_for_game(id))
          end
          response = results.sort{ |x, y| x.rank <=> y.rank }.first
        end
        response
      end

      def get_info_for_game(game_id)
        unless File.exists?("data/#{game_id}.xml")
          open("data/games/#{game_id}.xml", "wb") do |file|
            open("http://boardgamegeek.com/xmlapi2/thing?id=#{game_id}&stats=1") do |uri|
               file.write(uri.read)
            end
          end
        end
        Nokogiri::XML(File.open("data/games/#{game_id}.xml"))
      end

      def search_for_user(name, collection_options = {})
        user = @bgg.user({:name => name, :hot => 1, :top => 1})      
        collection = @bgg.collection({:username => name, :own => 1, :stats => 1}.merge(collection_options))   
        puts "="*80
        puts collection.inspect
        puts "="*80
                  
        user = User.new(name, user, collection)
        puts "="*80
        puts user.inspect
        puts "="*80
        user
      end

      def load_community
        users_file = File.open(USERS_FILE)
        users = {}
        users_file.lines.each do |line|
          nicks = line.gsub("\n", "").split(",")
          users[nicks.first] = nicks.last
        end        
        users
      end

      def find_bgg_by_irc(irc_nick)
        @community[irc_nick]
      end

      def in_community?(irc_nick)
        self.find_bgg_by_irc(irc_nick) != nil
      end

    end

    class Game
      attr_accessor :id, :rating, :rank, :name, :year, :minplayers, :maxplayers, :playingtime, :categories, :mechanics, :designers, :publishers
      
      NOT_RANKED_RANK = 10001

      def initialize(id, xml)
        self.id          = id
        self.rating      = xml.css('statistics ratings average')[0]['value'].to_f
        self.rank        = xml.css('statistics ratings ranks rank')[0]["value"]
        # if ranked, convert the value to integer; if not, set the value of the rank to the last possible
        self.rank        = self.rank == "Not Ranked" ? NOT_RANKED_RANK : self.rank.to_i
        self.name        = xml.css('name')[0]['value']
        self.year        = xml.css('yearpublished')[0]['value'].to_i
        self.minplayers  = xml.css('minplayers')[0]['value'].to_i
        self.maxplayers  = xml.css('maxplayers')[0]['value'].to_i
        self.playingtime = xml.css('playingtime')[0]['value'].to_i
        self.categories  = xml.css('link[type=boardgamecategory]').map{ |l| l['value'] }
        self.mechanics   = xml.css('link[type=boardgamemechanic]').map{ |l| l['value'] }
        self.designers   = xml.css('link[type=boardgamedesigner]').map{ |l| l['value'] }
        self.publishers  = xml.css('link[type=boardgamepublisher]').map{ |l| l['value'] }
      end
      
      # Since we are resetting the not ranked values, let's make sure  we return the correct values
      #
      def game_rank
        (self.rank == NOT_RANKED_RANK) ? "Not Ranked" : self.rank  
      end
    end

    class User

      attr_accessor :name, :top_games, :hot_games, :collection

      def initialize(username, user_xml, collection_xml)
        self.name       = username
        self.top_games  = user_xml["top"].nil? ? nil : user_xml["top"].select{|h| h["domain"] == "boardgame" }.first["item"].map{ |g| g["name"] }
        self.hot_games  = user_xml["hot"].nil? ? nil : user_xml["hot"].select{|h| h["domain"] == "boardgame" }.first["item"].map{ |g| g["name"] }
        self.collection = {}
        unless collection_xml["item"].nil?
          collection_xml["item"].each do |g| 
            self.collection[g["objectid"]] = {}
            self.collection[g["objectid"]]["name"]      = g["name"].first["content"] 
            self.collection[g["objectid"]]["for_trade"] = g["status"].first["fortrade"] 
            self.collection[g["objectid"]]["want"]      = g["status"].first["want"] 
            self.collection[g["objectid"]]["plays"]     = g["numplays"].first
            self.collection[g["objectid"]]["ratings"]   = g["stats"].first["rating"].first["value"]
          end
        end
      end

    end
  end
end
