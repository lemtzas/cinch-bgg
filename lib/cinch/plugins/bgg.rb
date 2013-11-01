require 'cinch'
require 'open-uri'
require 'nokogiri'

module Cinch
  module Plugins
    class Bgg
      include Cinch::Plugin

      USERS_FILE   = "users_list"
      USERS_SUBDIR = "users"
      GAMES_SUBDIR = "games"

      match /bgg (.+)/i,        method: :bgg
      match /bggme/i,           method: :bggself
      match /bgguser (.+)/i,    method: :bgguser
      match /bgguser -u (.+)/i, method: :bggactualuser

      match /link_bgg (.+)/i,   method: :link_to_bgg

      match /whohas (.+)/i,      method: :who_has_game
      match /whotrading (.+)/i,  method: :who_is_trading_game
      match /whowants (.+)/i,    method: :who_wants_game
      match /whorated (.+)/i,    method: :who_rated_game
      match /whoplayed (.+)/i,   method: :who_played_game


      def initialize(*args)
        super

        @data_dir  = config[:data_dir]
        @community = load_community
      end

      def bgg(m, title)
        game = search_bgg(m, title)
        unless game.nil?
          m.reply "#{m.user.nick}: #{game.name} (#{game.year}) - #{game.rating} - Rank: #{game.game_rank} - Designer: #{game.designers.join(", ")} - Mechanics: #{game.mechanics.join(", ")} - " <<
            "http://boardgamegeek.com/boardgame/#{game.id}"
        end
      end

      def bgguser(m, nick)
        unless nick.start_with?("-u ")
          if self.in_community?(nick)
            name = self.find_bgg_by_irc(nick)
            user = search_for_user(m, name)
            self.show_user_details(m, user)
          else
            m.reply "There's no \"#{nick}\" in the community. To link yourself and join the community, \"!link_bgg bgg_username\". To search by actual bgg username, \"!bgguser -u bgg_username\".", true
          end
        end
      end

      def bggself(m)
        self.bgguser(m, m.user.nick)
      end

      def bggactualuser(m, nick)
        user = search_for_user(m, nick)
        self.show_user_details(m, user)
      end

      def show_user_details(m, user)
        top5 = (user.top_games.empty? ? "" : "- Top 5: #{user.top_games.first(5).join(", ")} ")
        m.reply "#{user.name} - Collection: #{user.owned.size} #{top5}- http://boardgamegeek.com/user/#{user.name}", true
      end

      def link_to_bgg(m, username)
        @community[m.user.nick] = username
        File.open("#{@data_dir}#{USERS_FILE}", 'w') do |file|
          @community.each do |irc_nick, bgg_name|
            file.write("#{irc_nick},#{bgg_name}\n")
          end
        end
        m.reply "You are now added to the community!", true
      end

      def who_has_game(m, title)
        self.who_what_a_game(m, title, :owned, "Owning")
      end

      def who_is_trading_game(m, title)
        self.who_what_a_game(m, title, :trading, "Trading")
      end

      def who_wants_game(m, title)
        self.who_what_a_game(m, title, :wanted, "Wants")
      end

      def who_rated_game(m, title)
        self.who_what_a_game(m, title, :rated, "Rated", "rating")
      end

      def who_played_game(m, title)
        self.who_what_a_game(m, title, :played, "Played", "plays")
      end

      def who_what_a_game(m, title, action, string, with_number_info = nil)
        game = search_bgg(m, title)
        unless game.nil?
          community = @community.dup
          community.each{ |irc, bgg| community[irc] = search_for_user(m, bgg, { :id => game.id, :use_cache => true }) }

          community.keep_if{ |irc, user| user.send(action).include? game.id.to_s }
          user_info = []
          community.each do |irc, user|
            number_info = with_number_info.nil? ? "" : " (#{user.send(action)[game.id.to_s][with_number_info].to_s})"
            user_info << "#{self.dehighlight_nick(irc)}#{number_info}"
          end

          # If we have number info, use it to sort the user info.
          # The sort criterion is the number inside the brackets (extracted via regex).
          # We multiply this by -1 to have it sort descending.
          if !with_number_info.nil?
            user_info = user_info.sort_by { |info| info[/\((.*?)\)/, 1].to_f * -1 }
          end

          # Reply, breaking the response into acceptable lines.
          self.reply_with_line_breaks(m, string, game.name, user_info)
        end
      end

      # This function replies to the requesting user with `user_info` results, broken into "acceptable" lines.
      def reply_with_line_breaks(m, string, game_name, user_info)
        # This keeps track of the largest string so far that's "acceptable".
        acceptable_string = ""

        # This keeps track of the next string we plan to text for "acceptability".
        potential_string = ""

        # This is the index of the next bit of user info we plan to add to the potential string.
        index_to_add = 0

        while index_to_add < user_info.length do
          # Reset our strings.
          acceptable_string = ""
          potential_string = ""

          # Create the beginning of a new potential string.
          # We only want the info type and game name the first time.
          if index_to_add == 0
            potential_string += "#{string} \"#{game_name}\": "
          end
          potential_string += user_info[index_to_add]
          index_to_add += 1

          # Add to our potential string until we run out of user info or the potential string is unacceptable.
          while index_to_add < user_info.length && is_acceptable?(potential_string) do
            # Our potential string is acceptable!
            acceptable_string = potential_string

            # Add to our potential string.
            potential_string += ", " + user_info[index_to_add]
            index_to_add += 1
          end

          # If our potential string is too long, use the acceptable string and rewind.
          # Otherwise, we've hit the end of the list—use the potential string and we're done!
          if !is_acceptable?(potential_string)
            m.reply(acceptable_string, true)
            index_to_add -= 1
          else
            m.reply(potential_string, true)
          end
        end
      end

      # This function describes string "acceptability".
      def is_acceptable?(string)
        string.length < 200
      end

      #--------------------------------------------------------------------------------
      # Protected
      #--------------------------------------------------------------------------------
      protected

      def search_bgg(m, search_string)
        search_results_xml = Nokogiri::XML(self.connect_to_bgg(m){ open("http://boardgamegeek.com/xmlapi2/search?query=#{search_string.gsub(" ", "%20")}&type=boardgame&exact=1") }.read)
        if search_results_xml.css('items')[0]['total'] == "0"
          search_results_xml = Nokogiri::XML(self.connect_to_bgg(m){ open("http://boardgamegeek.com/xmlapi2/search?query=#{search_string.gsub(" ", "%20")}&type=boardgame") }.read)
        end
        search_results = search_results_xml.css('item').map { |i| i['id'].to_i }

        if search_results.empty?
          m.reply "\"#{search_string}\" not found", true
        elsif search_results.size > 50
          m.reply "\"#{search_string}\" was too broad of a search term", true
        else
          results = search_results.map do |id|
            Game.new(id, get_info_for_game(id))
          end
          response = results.sort{ |x, y| x.rank <=> y.rank }.first
        end
        response
      end

      def get_info_for_game(game_id)
        unless File.exists?("#{@data_dir}#{GAMES_SUBDIR}/#{game_id}.xml")
          open("#{@data_dir}#{GAMES_SUBDIR}/#{game_id}.xml", "wb") do |file|
            open("http://boardgamegeek.com/xmlapi2/thing?id=#{game_id}&stats=1") do |uri|
               file.write(uri.read)
            end
          end
        end
        Nokogiri::XML(File.open("#{@data_dir}#{GAMES_SUBDIR}/#{game_id}.xml"))
      end

      def search_for_user(m, name, collection_options = {})
        use_cache = collection_options[:use_cache] || false
        game_id   = collection_options[:id] || nil

        search_game_id_str = (game_id.nil? ? "" : "&id=#{game_id}")
        user_xml = Nokogiri::XML(self.connect_to_bgg(m){ open("http://boardgamegeek.com/xmlapi2/user?name=#{name}&hot=1&top=1#{search_game_id_str}")}.read)
        collection_xml = get_collection_data_for_user(name, use_cache)
        User.new(name, user_xml, collection_xml)
      end

      def get_collection_data_for_user(name, using_cache = false)
        file_url = "#{@data_dir}#{USERS_SUBDIR}/#{name}.xml"
        unless using_cache
          open(file_url, "w") do |file|
            open("http://boardgamegeek.com/xmlapi2/collection?username=#{name}&stats=1" ) do |uri|
               file.write(uri.read)
            end
          end
        end
        Nokogiri::XML(File.open(file_url))
      end

      def load_community
        users_file = File.open("#{@data_dir}#{USERS_FILE}")
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

      def dehighlight_nick(nickname)
        nickname.chars.to_a * 8203.chr('UTF-8')
      end

      def connect_to_bgg(m)
        if block_given?
          begin
            yield
          rescue Exception => e
            case e
              when Timeout::Error
                error = 'BGG timeout'
              when Errno::ECONNREFUSED
                error = 'BGG connection refused'
              when Errno::ECONNRESET
                error = 'BGG connection reset'
              when Errno::EHOSTUNREACH
                error = 'BGG host not reachable'
              else
                error = "BGG unknown #{e.to_s}"

            end
            m.reply "#{error}. Please try again.", true
          end
        end
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
          self.collection[g["objectid"]]              = {}
          self.collection[g["objectid"]]["name"]      = g.css("name")[0].content
          self.collection[g["objectid"]]["own"]       = g.css("status")[0]['own'].to_i
          self.collection[g["objectid"]]["for_trade"] = g.css("status")[0]['fortrade'].to_i
          self.collection[g["objectid"]]["want"]      = g.css("status")[0]['want'].to_i
          self.collection[g["objectid"]]["plays"]     = g.css("numplays")[0].content.to_i
          self.collection[g["objectid"]]["rating"]    = g.css("stats")[0].css("rating")[0]['value']
        end
      end

      def owned
        self.collection.select{ |id, game| game["own"] == 1 }
      end

      def trading
        self.collection.select{ |id, game| game["for_trade"] == 1 }
      end

      def wanted
        self.collection.select{ |id, game| game["want"] == 1 }
      end

      def rated
        self.collection.reject{ |id, game| game["rating"] == "N/A" }
      end

      def played
        self.collection.select{ |id, game| game["plays"] > 0 }
      end

    end
  end
end
