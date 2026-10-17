require 'net/http'
uri = URI('http://127.0.0.1:3000/')
http = Net::HTTP.new(uri.host, uri.port)
http.open_timeout = 3
http.read_timeout = 5
response = http.get(uri.request_uri)
exit((200..399).include?(response.code.to_i) ? 0 : 1)
