# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
	add_filter '/spec/'
end
SimpleCov.start

if ENV['CODECOV']
	require 'codecov'
	SimpleCov.formatter = SimpleCov::Formatter::Codecov
end

require_relative '../lib/flame'

require 'minitest/bacon'
require 'minitest/reporters'
Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new]

require 'pry-byebug'

def match_words(*words)
	regexp = words.map! { |word| "(?=.*#{Regexp.escape(word)})" }.join
	->(obj) { obj.match(/#{regexp}/m) }
end

def equal_routes(*attrs_collection)
	routes = attrs_collection.map! { |attrs| Flame::Router::Route.new(*attrs) }
	->(array) { array.sort == routes.sort }
end
