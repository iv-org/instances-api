# "instances.invidio.us" (which is a status page)
# Copyright (C) 2019  Omar Roth
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require "http/client"
require "kemal"
require "uri"

Kemal::CLI.new ARGV

macro rendered(filename)
  render "src/instances/views/#{{{filename}}}.ecr"
end

alias Instance = NamedTuple(flag: String?, region: String?, stats: JSON::Any?, type: String, uri: String, monitor: JSON::Any?)

INSTANCES = {} of String => Instance

spawn do
  loop do
    monitors = [] of JSON::Any
    page = 1
    loop do
      begin
        response = JSON.parse(HTTP::Client.get(URI.parse("https://uptime.invidio.us/api/getMonitorList/89VnzSKAn?page=#{page}")).body)

        monitors += response["psp"]["monitors"].as_a
        page += 1

        if response["psp"]["perPage"].as_i * page > response["psp"]["totalMonitors"].as_i
          break
        end
      rescue ex
        error_message = response.try &.["errorStats"]?
        error_message ||= ex.message
        puts "Exception pulling monitors: #{error_message}"
        next
      end
    end

    body = HTTP::Client.get(URI.parse("https://raw.githubusercontent.com/wiki/omarroth/invidious/Invidious-Instances.md")).body
    headers = HTTP::Headers.new

    body.scan(/\[(?<host>[^ \]]+)\]\((?<uri>[^\)]+)\)( .(?<region>[\x{1f100}-\x{1f1ff}]{2}))?/mx).each do |md|
      region = md["region"]?.try { |region| region.codepoints.map { |codepoint| (codepoint - 0x1f1a5).chr }.join("") }
      flag = md["region"]?

      uri = URI.parse(md["uri"])
      host = md["host"]

      case type = host.split(".")[-1]
      when "onion"
      when "i2p"
      else
        type = uri.scheme.not_nil!
        client = HTTP::Client.new(uri)
        client.connect_timeout = 5.seconds
        client.read_timeout = 5.seconds
        begin
          stats = JSON.parse(client.get("/api/v1/stats", headers).body)
        rescue ex
          stats = nil
        end
      end

      monitor = monitors.select { |monitor| monitor["name"].try &.as_s == host }[0]?
      INSTANCES[host] = {flag: flag, region: region, stats: stats, type: type, uri: uri.to_s, monitor: monitor}
    end

    sleep 1.minute
    Fiber.yield
  end
end

before_all do |env|
  env.response.headers["X-XSS-Protection"] = "1; mode=block"
  env.response.headers["X-Content-Type-Options"] = "nosniff"
  env.response.headers["Referrer-Policy"] = "same-origin"
  env.response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains; preload"
end

get "/" do |env|
  sort_by = env.params.query["sort_by"]?
  sort_by ||= "users"

  instances = sort_instances(INSTANCES, sort_by)

  rendered "index"
end

get "/instances.json" do |env|
  env.response.content_type = "application/json; charset=utf-8"
  sort_by = env.params.query["sort_by"]?
  sort_by ||= "users"

  instances = sort_instances(INSTANCES, sort_by)

  if env.params.query["pretty"]?.try &.== "1"
    instances.to_pretty_json
  else
    instances.to_json
  end
end

error 404 do |env|
  env.redirect "/"
  halt env, status_code: 302, response: ""
end

static_headers do |response, filepath, filestat|
  response.headers.add("Cache-Control", "max-age=86400")
end

def sort_instances(instances, sort_by)
  sort_proc = ->(instance : Tuple(String, Instance)) { instance[0] }
  instances = instances.to_a

  case sort_by
  when .starts_with? "name"
    instances.sort_by! { |name, instance| name }
  when .starts_with? "version"
    instances = instances.sort_by { |name, instance| "#{instance[:stats]?.try &.["software"]?.try &.["version"].as_s.split("-")[0] || "0.0.0"}#{name}" }.reverse
  when .starts_with? "type"
    instances.sort_by! { |name, instance| instance[:type] }
  when .starts_with? "signup"
    instances.sort_by! { |name, instance| instance[:stats]?.try &.["openRegistrations"]?.try { |bool| bool.as_bool ? 0 : 1 } || 2 }
  when .starts_with? "location"
    instances.sort_by! { |name, instance| instance[:region]? || "ZZ" }
  when .starts_with? "health"
    instances = instances.sort_by { |name, instance| instance[:monitor]?.try &.["weeklyRatio"]["ratio"].as_s.to_f || 0.0 }.reverse
  when .starts_with? "users"
    instances = instances.sort_by { |name, instance| instance[:stats]?.try &.["usage"]?.try &.["users"]["total"].as_i || 0 }.reverse
  end

  instances.reverse! if sort_by.ends_with?("-reverse")
  instances
end

gzip true
public_folder "assets"

Kemal.config.powered_by_header = false
Kemal.run
