require 'socket'

RSpec.configure do |config|
  config.before(:suite) do
    host = ENV.fetch('TOGOVAR_REDIS_HOST', 'localhost')
    port = ENV.fetch('TOGOVAR_REDIS_PORT', '6379')

    begin
      TCPSocket.open(host, port.to_i).close
    rescue
      message = <<~MSG
        cannot connect to redis running on #{host}:#{port}
        start redis server by following command:
        ```
        bundle exec foreman start -f Procfile.dev -c elasticsearch=1,kibana=1,redis=1
        ```
      MSG

      abort message
    end
  end
end
