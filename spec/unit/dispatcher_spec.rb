# frozen_string_literal: true

## Test controller for Dispatcher
class DispatcherController < Flame::Controller
	def index; end

	def foo; end

	def create; end

	def hello(name)
		"Hello, #{name}!"
	end

	def baz(var = nil)
		"Hello, #{var}!"
	end

	def test
		'Route content'
	end

	def action_with_after_hook
		'Body of action'
	end

	def redirect_from_before; end

	protected

	def execute(action)
		request.env[:execute_before_called] ||= 0
		request.env[:execute_before_called] += 1
		halt redirect :foo if action == :redirect_from_before
		super
		nil if action == :action_with_after_hook
	end
end

## Test application for Dispatcher
class DispatcherApplication < Flame::Application
	mount DispatcherController, '/'
end

describe Flame::Dispatcher do
	before do
		@init = lambda do |method: 'GET', path: '/hello/world', query: nil|
			@env = {
				Rack::REQUEST_METHOD => method,
				Rack::PATH_INFO => path,
				Rack::RACK_INPUT => StringIO.new,
				Rack::RACK_ERRORS => StringIO.new,
				Rack::QUERY_STRING => query
			}
			Flame::Dispatcher.new(DispatcherApplication, @env)
		end
		@dispatcher = @init.call
	end

	describe 'attrs' do
		it 'should have request reader' do
			@dispatcher.request.should.be.instance_of Flame::Dispatcher::Request
		end

		it 'should have response reader' do
			@dispatcher.response.should.be.instance_of Flame::Dispatcher::Response
		end
	end

	describe '#initialize' do
		it 'should take @app_class variable' do
			@dispatcher.instance_variable_get(:@app_class)
				.should.equal DispatcherApplication
		end

		it 'should take @env variable' do
			@dispatcher.instance_variable_get(:@env)
				.should.equal @env
		end

		it 'should take @request variable from env' do
			@dispatcher.request.env.should.equal @env
		end

		it 'should initialize @response variable' do
			@dispatcher.response.should.be.instance_of Flame::Dispatcher::Response
		end
	end

	describe '#run!' do
		it 'should return respond from existing route' do
			respond = @dispatcher.run!.last
			respond.status.should.equal 200
			respond.body.should.equal ['Hello, world!']
		end

		it 'should return respond from existing route with nil in after-hook' do
			respond = @init.call(path: 'action_with_after_hook').run!.last
			respond.status.should.equal 200
			respond.body.should.equal ['Body of action']
		end

		it 'should return status 200 for existing route with empty body' do
			respond = @init.call(path: 'foo').run!.last
			respond.status.should.equal 200
			respond.body.should.equal ['']
		end

		it 'should return content of existing static file' do
			respond = @init.call(path: 'test.txt').run!.last
			respond.status.should.equal 200
			respond.body.should.equal ["Test static\n"]
		end

		it 'should return content of existing static file in gem' do
			respond = @init.call(path: 'favicon.ico').run!.last
			respond.status.should.equal 200
			favicon_file = File.join __dir__, '../../public/favicon.ico'
			respond.body.should.equal [File.read(favicon_file)]
		end

		it 'should return content of existing static file before route executing' do
			respond = @init.call(path: 'test').run!.last
			respond.status.should.equal 200
			respond.body.should.equal ["Static file\n"]
		end

		it 'should return 404 if neither route nor static file was found' do
			respond = @init.call(path: 'bar').run!.last
			respond.status.should.equal 404
			respond.body.should.equal ['<h1>Not Found</h1>']
		end

		it 'should return 404 for route with required argument by path without' do
			respond = @init.call(path: 'hello').run!.last
			respond.status.should.equal 404
			respond.body.should.equal ['<h1>Not Found</h1>']
		end

		it 'should not return body for HEAD methods' do
			respond = @init.call(method: 'HEAD').run!.last
			respond.status.should.equal 200
			respond.body.should.equal []
		end

		it 'should return 405 for not allowed HTTP-method with Allow header' do
			respond = @init.call(method: 'POST').run!.last
			respond.headers['Allow'].should.equal 'GET, OPTIONS'
			respond.status.should.equal 405
		end

		describe 'OPTIONS HTTP-method' do
			before do
				@respond = @init.call(method: 'OPTIONS').run!.last
			end

			should 'return 200 for existing route' do
				@respond.status.should.equal 200
			end

			should 'return 404 for not-existing route' do
				dispatcher = @init.call(method: 'OPTIONS', path: '/hello')
				respond = dispatcher.run!.last
				respond.status.should.equal 404
			end

			should 'not return body' do
				@respond.body.should.equal ['']
			end

			should 'contain `Allow` header with appropriate HTTP-methods' do
				dispatcher = @init.call(method: 'OPTIONS', path: '/')
				respond = dispatcher.run!.last
				respond.headers['Allow'].should.equal 'GET, POST, OPTIONS'
			end

			should 'not return `Allow` header for not-existing route' do
				dispatcher = @init.call(method: 'OPTIONS', path: '/hello')
				respond = dispatcher.run!.last
				respond.headers.key?('Allow').should.equal false
			end

			should 'return `Allow` header for route with optional parameters' do
				dispatcher = @init.call(method: 'OPTIONS', path: '/baz')
				respond = dispatcher.run!.last
				respond.headers.key?('Allow').should.equal true
			end
		end
	end

	describe '#status' do
		it 'should return 200 by default' do
			@dispatcher.status.should.equal 200
		end

		it 'should take status' do
			@dispatcher.status 101
			@dispatcher.status.should.equal 101
		end

		it 'should set status to response' do
			@dispatcher.status 101
			@dispatcher.response.status.should.equal 101
		end

		it 'should set X-Cascade header for 404 status' do
			@dispatcher.status 404
			@dispatcher.response['X-Cascade'].should.equal 'pass'
		end
	end

	describe '#body' do
		it 'should set @body variable' do
			@dispatcher.body 'Hello!'
			@dispatcher.instance_variable_get(:@body).should.equal 'Hello!'
		end

		it 'should get @body variable' do
			@dispatcher.body 'Hello!'
			@dispatcher.body.should.equal 'Hello!'
		end
	end

	describe '#params' do
		it 'should return params from request with Symbol keys' do
			@init.call(path: '/hello', query: 'name=world&when=now').params
				.should.equal Hash[name: 'world', when: 'now']
		end

		it 'should not be the same Hash as params from request' do
			dispatcher = @init.call(path: '/hello', query: 'name=world&when=now')
			dispatcher.params.should.not.be.same_as dispatcher.request.params
		end

		it 'should cache Hash of params' do
			dispatcher = @init.call(path: '/hello', query: 'name=world&when=now')
			dispatcher.params.should.be.same_as dispatcher.params
		end

		it 'should not break with invalid %-encoding query' do
			lambda do
				dispatcher = @init.call(path: '/foo', query: 'bar=%%')
				dispatcher.params
			end
				.should.not.raise(ArgumentError)
		end
	end

	describe '#session' do
		it 'should return Object from Request' do
			@dispatcher.session.should.be.same_as @dispatcher.request.session
		end
	end

	describe '#cookies' do
		it 'should return instance of Flame::Cookies' do
			@dispatcher.cookies.should.be.instance_of Flame::Dispatcher::Cookies
		end

		it 'should cache the object' do
			@dispatcher.cookies.should.be.same_as @dispatcher.cookies
		end
	end

	describe '#config' do
		it 'should return config from app' do
			@dispatcher.config
				.should.be.same_as @dispatcher.instance_variable_get(:@app_class).config
		end
	end

	describe '#halt' do
		it 'should just throw without changes if no arguments' do
			-> { @dispatcher.halt }.should.throw(:halt)
			@dispatcher.status.should.equal 200
			@dispatcher.body.should.equal @dispatcher.default_body
		end

		it 'should take new status and write default body' do
			-> { @dispatcher.halt 500 }.should.throw(:halt)
			@dispatcher.status.should.equal 500
			@dispatcher.body.should.equal @dispatcher.default_body
		end

		it 'should not write default body for status without entity body' do
			-> { @dispatcher.halt 101 }.should.throw(:halt)
			@dispatcher.status.should.equal 101
			@dispatcher.body.should.be.empty
		end

		it 'should take new body' do
			-> { @dispatcher.halt 404, 'Nobody here' }.should.throw(:halt)
			@dispatcher.status.should.equal 404
			@dispatcher.body.should.equal 'Nobody here'
		end

		it 'should take new headers' do
			-> { @dispatcher.halt 200, 'Cats!', 'Content-Type' => 'animal/cat' }
				.should.throw(:halt)
			@dispatcher.status.should.equal 200
			@dispatcher.body.should.equal 'Cats!'
			@dispatcher.response.headers['Content-Type'].should.equal 'animal/cat'
		end

		it 'should take Controller#redirect method' do
			url = 'http://example.com'
			controller = DispatcherController.new(@dispatcher)
			-> { @dispatcher.halt controller.redirect(url, 301) }
				.should.throw(:halt)
			@dispatcher.status.should.equal 301
			@dispatcher.response.location.should.equal url
		end
	end

	describe '#dump_error' do
		before do
			@error = RuntimeError.new 'Just an example error'
			@error.set_backtrace(caller)
		end

		it 'should write full information to @env[Rack::RACK_ERRORS]' do
			@dispatcher.dump_error(@error)
			@dispatcher.instance_variable_get(:@env)[Rack::RACK_ERRORS].string
				.should match_words(
					Time.now.strftime('%Y-%m-%d %H:%M:%S'),
					@error.class.name, @error.message # , __FILE__ (because of minitest)
				)
		end
	end

	describe '#default_body' do
		it 'should return default body as <h1> for any setted status' do
			@dispatcher.status 200
			@dispatcher.default_body.should.equal '<h1>OK</h1>'

			@dispatcher.status 404
			@dispatcher.default_body.should.equal '<h1>Not Found</h1>'

			@dispatcher.status 500
			@dispatcher.default_body.should.equal '<h1>Internal Server Error</h1>'
		end

		should 'not be called from `execute`' do
			dispatcher = @init.call(path: 'redirect_from_before')
			dispatcher.run!
			dispatcher.request.env[:execute_before_called].should.equal 1
		end
	end

	it 'should not break for invalid %-encoding in requests' do
		lambda do
			dispatcher = @init.call(path: '/foo', query: 'bar=%%')
			dispatcher.run!
			dispatcher.status.should.equal 400
			dispatcher.body.should.equal '<h1>Bad Request</h1>'
		end
			.should.not.raise(ArgumentError)
	end
end
