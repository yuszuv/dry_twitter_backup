#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'

require 'concurrent'
require 'dotenv/load'
require 'byebug'
require "twitter"
require "json"
require 'dry/effects'
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
            in Success() | Success(_) then puts "Yeah 🎉"
            in Failure(x) then puts "ERROR: #{x.message}"
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

  module Functions
    extend Dry::Transformer::Registry

    import Dry::Transformer::HashTransformations
    import Dry::Transformer::ArrayTransformations
  end

  module Actions
    class DoBackup
      include Dry::Effects::Handler.State(:fetching_data)
      include Dry::Effects.State(:fetching_data)
      include Dry::Effects::Handler.State(:writing_data)
      include Dry::Effects.State(:writing_data)
      include Dry::Effects.Defer
      include Dry::Effects::Handler.Defer #(executor: :immediate)
      include Dry::Monads[:do, :result, :try, :task]

      def call
        # dry-effects to the rescue: printing dots while waiting for api request to finish
        print "Fetching data ..."
        json = with_defer do
          is_fetching, result = with_fetching_data(true) do
            defer do
              j = yield fetch_data.fmap(&data_mapper)
              # j = [{ name: 'bar' }]
              self.fetching_data = false
              j
            end
          end

          defer { print_dots(is_fetching) }

          wait(result).tap{ puts ' done' }
        end

        print "Writing to disk ..."
        with_defer do
          is_writing, result = with_writing_data(true) do
            defer do
              x = yield write_to_file(json)
              self.writing_data = false
              x
            end
          end

          defer { print_dots(is_writing) }

          wait(result).tap { puts ' done' }
        end

        Success()
      end

      private

      def print_dots(state)
        while state do sleep 0.1 and print '.' end
      end

      def fetch_data
        Try[Twitter::Error] do
          { friends: twitter_client.friends.to_a,
            followers: twitter_client.followers.to_a }
        end.to_result
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

      def write_to_file(blob)
        Try[Dry::Files::IOError] do
          f    = Dry::Files.new

          writer = f.method(:write)
          path   = f.expand_path( "./twitter_backup.json", __dir__)
          output = JSON.pretty_generate(blob)

          writer.(path, output)
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
