require 'cinch'
require 'open-uri'
require 'nokogiri'

module Cinch
  module Plugins
    class Bgg
      include Cinch::Plugin

      match /bgg (.+)/i,     method: :bgg
      match /bgguser (.+)/i, method: :bgguser

      def bgg(m, title)
        results = search_bgg(title)
        if results == "not found"
          m.reply "#{m.user.nick}: \"#{title}\" not found"
        elsif results == "too big"
          m.reply "#{m.user.nick}: \"#{title}\" was too broad of a search term"
        else
          game = results.sort{ |x, y| x.rank <=> y.rank }.first
          m.reply "#{m.user.nick}: #{game.name} (#{game.year}) - #{game.rating} - Rank: #{game.game_rank} - Designer: #{game.designers.join(", ")} - Mechanics: #{game.mechanics.join(", ")} - " <<
            "http://boardgamegeek.com/boardgame/#{game.id}"
        end
      end

      def bgguser(m, name)
        user = search_for_user(name)
        m.reply "#{m.user.nick}: #{user.name} - Collection: #{user.collection.size} - Top 5: #{user.top_games.first(5).join(", ")} - http://boardgamegeek.com/user/#{user.name}"
      end

      #--------------------------------------------------------------------------------
      # Protected
      #--------------------------------------------------------------------------------
      protected

      def search_bgg(search_string)
        search_results_xml = Nokogiri::XML(open("http://boardgamegeek.com/xmlapi2/search?query=#{search_string.gsub(" ", "%20")}&type=boardgame&exact=1").read)
        if search_results_xml.css('items')[0]['total'] == "0"
          search_results_xml = Nokogiri::XML(open("http://boardgamegeek.com/xmlapi2/search?query=#{search_string.gsub(" ", "%20")}&type=boardgame").read)
        end
        search_results = search_results_xml.css('item').map { |i| i['id'].to_i }
        
        # this is dumb, find a better way
        if search_results.empty?
          response = "not found"
        elsif search_results.size > 50
          response = "too big"
        else
          response = search_results.map do |id|
            Game.new(id, get_info_for_game(id))
          end
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

      def search_for_user(name)
        user_xml = Nokogiri::XML(open("http://boardgamegeek.com/xmlapi2/user?name=#{name}&hot=1&top=1").read)
        collection_xml = Nokogiri::XML(open("http://boardgamegeek.com/xmlapi2/collection?username=#{name}&own=1").read)
        User.new(name, user_xml, collection_xml)
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
        self.top_games  = user_xml.css("top item").map{ |g| g["name"] }
        self.hot_games  = user_xml.css("hot item").map{ |g| g["name"] }
        self.collection = {}
        collection_xml.css("items item").each do |g| 
          self.collection[g["objectid"]] = g.css("name")[0].content
        end
      end

    end
  end
end
