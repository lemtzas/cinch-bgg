# Cinch-BGG - BoardGameGeek plugin

## Description

This is a BoardGameGeek plugin for Cinch bots. Handcrafted for #boardgames on freenode.

## Installation

### RubyGems

You can install the latest Cinch-BGG gem using RubyGems

    gem install cinch-bgg

### GitHub

Alternatively you can check out the latest code directly from Github

    git clone http://github.com/caitlin/cinch-bgg.git

## Usage

Install the gem and load it in your Cinch bot:

    require "cinch"
    require "cinch/plugins/bgg"

    bot = Cinch::Bot.new do
      configure do |c|
        # add all required options here
        c.plugins.plugins = [Cinch::Plugins::Bgg] # optionally add more plugins
      end
    end

    bot.start


## Commands

### !bgg

The bot will reply with "Title (Year) - Rating - Rank - Designer(s) - Mechanics - BGG Link"
e.g. "Dominion (2008) - 7.94377 - Rank: 11 - Designer: Donald X. Vaccarino - Mechanics: Card Drafting, Deck / Pool Building, Hand Management - http://boardgamegeek.com/boardgame/36218"

### !bgguser

The bot will reply with "Username - Collection Size - Top 5 Games - BGG Profile Link"
e.g. "nolemonplease - Collection: 94 - Top 5: Battlestar Galactica, Space Alert, Mage Knight: Board Game, Trajan, Troyes - http://boardgamegeek.com/user/nolemonplease"

