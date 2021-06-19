# Fetch a country's emoji flag from their country code (ISO 3166 alpha-2).
#
# A flag is made out of two regional indicator symbols.
# So in order to convert from an ISO 3166 alpha-2 code into unicode we'll have to
# add a specific offset to each character to make them into the required regional
# indicator symbols. This offset is exactly 0x1f1a5.
#
# Reference implementation https://schinckel.net/2015/10/29/unicode-flags-in-python/
private def fetch_flag(country_code)
  return country_code.codepoints.map { |codepoint| (codepoint + 0x1f1a5).chr }.join("")
end

# Extracts the nested modified information containing source url and changes.
private def extract_modified_information(modified_hash)
  if modified = modified_hash.as_h?
    return Modified.new(
      source: modified["source"].as_s,
      changes: modified["changes"].as_s
    )
  end
end

# Extracts information common to all instance types.
private def extract_prerequisites(instance_data)
  uri = URI.parse(instance_data["url"].to_s)
  host = uri.host

  # Fetch country data
  region = instance_data["country"].to_s
  flag = fetch_flag(region)

  privacy_policy = instance_data["privacy_policy"].as_s?
  owner = {name: instance_data["owner"].to_s.split("/")[-1].to_s, url: instance_data["owner"].as_s}
  modified = extract_modified_information(instance_data["modified"])
  notes = instance_data["notes"].as_a?

  mirrors = [] of Mirrors
  instance_data["mirrors"].as_a?.try &.each do |m|
    mirrors << Mirrors.new(
      url: m["url"].as_s,
      region: m["country"].as_s,
      flag: fetch_flag(m["country"].as_s)
    )
  end

  return uri, host, region, flag, privacy_policy, owner, modified, notes, mirrors
end

def prepare_http_instance(instance_data, instances_storage, monitors)
  uri, host, region, flag, privacy_policy, owner, modified, notes, mirrors = extract_prerequisites(instance_data)

  # Fetch status information
  if status = instance_data["status"].as_h?
    status_url = status["url"].as_s
  else
    status_url = nil
  end

  ddos_mitm_protection = instance_data["ddos_mitm_protection"].as_s?

  client = HTTP::Client.new(uri)
  client.connect_timeout = 5.seconds
  client.read_timeout = 5.seconds

  begin
    stats = JSON.parse(client.get("/api/v1/stats").body)
  rescue ex
    stats = nil
  end

  monitor = monitors.try &.select { |monitor| monitor["name"].try &.as_s == host }[0]?
  return {
    region:               region,
    flag:                 flag,
    stats:                stats,
    type:                 "https",
    uri:                  uri.to_s,
    status_url:           status_url,
    privacy_policy:       privacy_policy,
    ddos_mitm_protection: ddos_mitm_protection,
    owner:                owner,
    modified:             modified,
    mirrors:              mirrors,
    notes:                notes,
    monitor:              monitor || instances_storage[host]?.try &.[:monitor]?,
  }
end

def prepare_onion_instance(instance_data, instances_storage)
  uri, host, region, flag, privacy_policy, owner, modified, notes, mirrors = extract_prerequisites(instance_data)

  associated_clearnet_instance = instance_data["associated_clearnet_instance"].as_s?

  if CONFIG["fetch_onion_instance_stats"]?
    begin
      args = Process.parse_arguments("--socks5-hostname '#{CONFIG["tor_sock_proxy_address"]}:#{CONFIG["tor_sock_proxy_port"]}' 'http://#{uri.host}/api/v1/stats'")
      response = nil
      Process.run("curl", args: args) do |result|
        data = result.output.read_line
        response = JSON.parse(data)
      end

      stats = response
    rescue ex
      stats = nil
    end
  else
    stats = nil
  end

  return {
    region:                       region,
    flag:                         flag,
    stats:                        stats,
    type:                         "onion",
    uri:                          uri.to_s,
    associated_clearnet_instance: associated_clearnet_instance,
    privacy_policy:               privacy_policy,
    owner:                        owner,
    modified:                     modified,
    mirrors:                      mirrors,
    notes:                        notes,
    monitor:                      nil,
  }
end
