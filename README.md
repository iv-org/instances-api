# [api.invidious.io/](https://api.invidious.io/)

[![Build Status](https://github.com/iv-org/instances-api/workflows/api.invidious.io%20CI/badge.svg)](https://github.com/iv-org/instances-api/actions)

Status page for [Invidious](https://github.com/iv-org/invidious) instances, sourced from [the documentation](https://docs.invidious.io/instances/).

## Installation

```bash
$ git clone https://github.com/iv-org/instances-api
$ cd instances-api
$ shards install
$ crystal build src/instances.cr --release
```

## Usage

```bash
$ ./instances -h
    -b HOST, --bind HOST             Host to bind (defaults to 0.0.0.0)
    -p PORT, --port PORT             Port to listen for connections (defaults to 3000)
    -s, --ssl                        Enables SSL
    --ssl-key-file FILE              SSL key file
    --ssl-cert-file FILE             SSL certificate file
    -h, --help                       Shows this help
```

## Contributing

1. Fork it (<https://github.com/iv-org/instances-api/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Omar Roth](https://github.com/omarroth) - original creator
