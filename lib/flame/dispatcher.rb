# frozen_string_literal: true

require 'gorilla-patch/symbolize'

require_relative 'dispatcher/request'
require_relative 'dispatcher/response'
require_relative 'dispatcher/cookies'

require_relative 'dispatcher/static'
require_relative 'dispatcher/routes'

require_relative 'errors/route_not_found_error'

module Flame
	## Helpers for dispatch Flame::Application#call
	class Dispatcher
		GEM_STATIC_FILES = File.join __dir__, '..', '..', 'public'

		attr_reader :request, :response

		include Flame::Dispatcher::Static
		include Flame::Dispatcher::Routes

		## Initialize Dispatcher from Application#call
		## @param app_class [Class] application class
		## @param env Rack-environment object
		def initialize(app_class, env)
			@app_class = app_class
			@env = env
			@request = Flame::Dispatcher::Request.new(env)
			@response = Flame::Dispatcher::Response.new
		end

		## Start of execution the request
		def run!
			catch :halt do
				try_options ||
					try_static ||
					try_static(dir: GEM_STATIC_FILES) ||
					try_route ||
					halt(404)
			end
			response.write body unless request.http_method == :HEAD
			response.finish
		end

		## Acccess to the status of response
		## @param value [Ineger, nil] integer value for new status
		## @return [Integer] current status
		## @example Set status value
		##   status 200
		def status(value = nil)
			response.status ||= 200
			response.headers['X-Cascade'] = 'pass' if value == 404
			value ? response.status = value : response.status
		end

		## Acccess to the body of response
		## @param value [String, nil] string value for new body
		## @return [String] current body
		## @example Set body value
		##   body 'Hello World!'
		def body(value = nil)
			value ? @body = value : @body ||= ''
		end

		using GorillaPatch::Symbolize

		## Parameters of the request
		def params
			@params ||= request.params.symbolize_keys(deep: true)
		end

		## Session object as Hash
		def session
			request.session
		end

		## Cookies object as Hash
		def cookies
			@cookies ||= Cookies.new(request.cookies, response)
		end

		## Application-config object as Hash
		def config
			@app_class.config
		end

		## Build a path to the given controller and action, with any expected params
		##
		## @param ctrl [Flame::Controller] class of controller
		## @param action [Symbol] method of controller
		## @param args [Hash] parameters for method of controller
		## @return [String] path for requested method, controller and parameters
		## @example Path for `show(id)` method of `ArticlesController` with `id: 2`
		##   path_to ArticlesController, :show, id: 2 # => "/articles/show/2"
		## @example Path for `new` method of `ArticlesController` with params
		##   path_to ArticlesController, :new, params: { author_id: 1 }
		##   # => "/articles/new?author_id=1"
		def path_to(ctrl, action = :index, args = {})
			path = @app_class.router.path_of(ctrl, action)
			raise Errors::RouteNotFoundError.new(ctrl, action) unless path
			query = Rack::Utils.build_nested_query args.delete(:params)
			query = nil if query&.empty?
			path = path.assign_arguments(args)
			path = '/' if path.empty?
			Addressable::URI.new(path: path, query: query).to_s
		end

		## Interrupt the execution of route, and set new optional data
		##   (otherwise using existing)
		## @param new_status [Integer, nil]
		##   set new HTTP status code
		## @param new_body [String, nil] set new body
		## @param new_headers [Hash, nil] merge new headers
		## @example Halt, no change status or body
		##   halt
		## @example Halt with 500, no change body
		##   halt 500
		## @example Halt with 404, render template
		##   halt 404, render('errors/404')
		## @example Halt with 200, set new headers
		##   halt 200, 'Cats!', 'Content-Type' # => 'animal/cat'
		def halt(new_status = nil, new_body = nil, new_headers = {})
			status new_status if new_status
			body new_body || (default_body_of_nearest_route if body.empty?)
			response.headers.merge!(new_headers)
			throw :halt
		end

		## Add error's backtrace to @env['rack.errors'] (terminal or file)
		## @param error [Exception] exception for class, message and backtrace
		def dump_error(error)
			error_message = [
				"#{Time.now.strftime('%Y-%m-%d %H:%M:%S')} - " \
				"#{error.class} - #{error.message}:",
				*error.backtrace
			].join("\n\t")
			@env[Rack::RACK_ERRORS].puts(error_message)
		end

		## Generate default body of error page
		def default_body
			# response.headers[Rack::CONTENT_TYPE] = 'text/html'
			"<h1>#{Rack::Utils::HTTP_STATUS_CODES[status]}</h1>"
		end

		## All cached tilts (views) for application by Flame::Render
		def cached_tilts
			@app_class.cached_tilts
		end

		private

		## Return response if HTTP-method is OPTIONS
		def try_options
			return unless request.http_method == :OPTIONS
			allow = @app_class.router.routes.dig(request.path)&.allow
			halt 404 unless allow
			response.headers['Allow'] = allow
		end
	end
end
