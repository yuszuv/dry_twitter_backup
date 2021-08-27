#!/usr/bin/env ruby

# simple script to backup all my twitter followings and followers, so that I now can get rid of all
# the stuff that steals my attention ... and FOMO make me to do at least one single backup.
# ... And the best of all ... monads, dry-monaads, DRY-MONADS :)
# Jan jan@sternprodukt.de
# Licence: MIT

require 'rubygems'
require 'bundler/setup'

require 'dotenv/load'
require 'byebug'
require "twitter"
require "json"
require "dry/monads"
require "dry/files"
require "dry/cli"
require "dry/transformer/all"
require "bundler/setup"

module TwitterBackup
  module CLI
    module Commands
      extend Dry::CLI::Registry

      class CreateBackup < Dry::CLI::Command
        include Dry::Monads[:result]

        desc "Create a backup of all twitter setup (followers, ...)"

        def call(*)
          case Actions::DoBackup.new.()
            in Success(_) then puts "... yeah"
            in Failure[error_code, *payload] then p [error_code, payload]
            in x then p x
          end
        end
      end

      class Version < Dry::CLI::Command
        desc "Print version"

        def call(*)
          puts "1.0.0"
        end
      end

      register "version", Version, aliases: ["v", "-v", "--version"]
      register "create",  CreateBackup
    end
  end

  # create your own local registry for transformation functions
  module Functions
    extend Dry::Transformer::Registry

    import Dry::Transformer::HashTransformations
    import Dry::Transformer::ArrayTransformations
  end

  module Actions
    class DoBackup
      include Dry::Monads[:do, :result, :try]

      def call
        puts "... fetching data"
        json = yield fetch_data.fmap(&data_mapper)

        puts "... writing to disk"
        yield write_to_file(json)

        Success(json)
      end

      def data_mapper
        t(:map_values,
          t(:map_array,
            t(-> { _1.to_hash })
              .>>(t(:symbolize_keys))
              .>>(t(:accept_keys, [:id, :id_str, :name, :screen_name]))
           )
         )
      end

      private

      def write_to_file(blob)
        Try[Dry::Files::IOError] do
          f    = Dry::Files.new

          writer = f.method(:write)
          path   = f.expand_path( "./twitter_backup.json", __dir__)
          output = JSON.pretty_generate(blob)

          writer.(path, output)
        end.to_result
      end

      def fetch_data
        Try[Twitter::Error] do
          { friends: twitter_client.friends.to_a,
            followers: twitter_client.followers.to_a }
        end.to_result
      end

      def twitter_client
        client = Twitter::REST::Client.new do |config|
          config.consumer_key        = ENV['CONSUMER_KEY']
          config.consumer_secret     = ENV['CONSUMER_SECRET']
          config.access_token        = ENV['ACCESS_TOKEN']
          config.access_token_secret = ENV['ACCESS_TOKEN_SECRET']
        end
      end

      def t(*args)
        Functions[*args]
      end
    end
  end
end

Dry::CLI.new(TwitterBackup::CLI::Commands).call
