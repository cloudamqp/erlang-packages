require "net/http"
require "json"

class Packagecloud
  def initialize(token = ENV.fetch("PACKAGECLOUD_TOKEN"))
    @http = Net::HTTP.start("packagecloud.io", use_ssl: true)
    @token = token
    @packages = packages
    @distributions = distributions
  end

  def exists?(dist_name, name)
    @packages.any? { |p| p["filename"] == name && p["distro_version"] == dist_name }
  end

  def upload(dist_name, file)
    puts "Uploading #{File.basename file.path} (#{(file.size / 1024.0**2).round(1)} MB)"
    file.rewind
    request = Net::HTTP::Post.new("/api/v1/repos/cloudamqp/erlang/packages.json")
    request.basic_auth(@token, "")
    form_data = [["package[distro_version_id]", dist_id(dist_name).to_s],
                 ["package[package_file]", file]]
    request.set_form form_data, "multipart/form-data"
    response = @http.request(request)
    case response
    when Net::HTTPCreated
      package = JSON.parse(response.body)
      puts "#{package['filename']} for #{package['distro_version']} uploaded"
    else raise "Unexpected response: #{response} #{response.body}"
    end
  end

  def dist_id(name)
    @distributions.each_value do |type|
      type.each do |dist|
        dist["versions"].each do |v|
          dist_name = "#{dist['index_name']}/#{v['index_name']}"
          return v["id"] if dist_name == name
        end
      end
    end
  end

  private

  def packages
    packages = []
    (1..).each do |page|
      path = "/api/v1/repos/cloudamqp/erlang/packages.json?per_page=250&page=#{page}"
      request = Net::HTTP::Get.new(path)
      request.basic_auth(@token, "")
      resp = @http.request request
      raise "Unexpected response: #{resp} #{resp.body}" unless Net::HTTPOK === resp

      data = JSON.parse(resp.body)
      break if data.empty?
      packages.concat data
    end
    packages
  end

  def distributions
    request = Net::HTTP::Get.new("/api/v1/distributions.json")
    request.basic_auth(@token, "")
    resp = @http.request request
    raise "Unexpected response: #{resp} #{resp.body}" unless Net::HTTPOK === resp

    JSON.parse resp.body
  end
end
