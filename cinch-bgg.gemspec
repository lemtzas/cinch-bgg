# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name        = "cinch-bgg"
  s.version     = "0.0.7"
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Caitlin Woodward"]
  s.email       = ["caitlin@caitlinwoodward.me"]
  s.homepage    = "https://github.com/caitlin/cinch-bgg"
  s.summary     = %q{Gives Cinch IRC bots access to BoardGameGeek data}
  s.description = %q{Gives Cinch IRC bots access to BoardGameGeek data}

  s.add_dependency("cinch", "~> 2.0")
  s.add_dependency("nokogiri", "~> 1.5.2")

  s.files         = `git ls-files`.split("\n")
  s.require_paths = ["lib"]
end