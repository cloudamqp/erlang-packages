require "net/http"
require "json"

class Github
  def initialize(token = ENV.fetch("GITHUB_TOKEN"))
    @auth = { Authorization: "Bearer #{token}" }
  end

  def releases(&blk)
    Net::HTTP.start("api.github.com", use_ssl: true) do |api|
      1.upto(10).each do |page|
        resp = api.get("/repos/erlang/otp/releases?per_page=100&&page=#{page}", @auth)
        raise "Unexpected response: #{resp} #{resp.body}" unless Net::HTTPOK === resp
        releases = JSON.parse(resp.body)
        break if releases.empty?
        releases.each(&blk)
      end
    end
  end
end
