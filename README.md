# binance-bot

Development just started...

## Installation

### 1. Required software:
```
sudo dnf/apt/pkg install perl cpanminus screen git
```

### 2. Perl modules:
```
cpanm App::cpanoutdated
cpan-outdated -p | cpanm --sudo
cpanm IO::Async Net::Async::WebSocket::Client JSON DateTime IO::Async::SSL LWP::Protocol::https --sudo
sudo dnf/apt/pkg install perl-REST-Client
```
### 3. Downloading binance-bot
```
git clone https://github.com/dream-hunter/binance-bot.git
```

### 4. Downloading REST-API library
```
cd binance-bot
git clone https://github.com/dream-hunter/binance-rest-api-pl.git
```

### 5. Prepare config file
```
cp config.json.example config.json
```
Edit config.json according to the config explanation below.

### 6. Test started
```
/usr/bin/env perl binance-bot
```

## Config explanation

System uses JSON format in config file. To run the bot, you need to copy config.json.example to config.json and edit some parameters. There are three major sections: API, WSS and Markets.

### API


Basic configuration:
```
    "API" : {
        "url"       : "https://api.binance.com/api/v3",
        "apikey"    : "",
        "apisecret" : ""
    }
```

This section contains information for API handlers.

"url" - API endpoint.

Known list of binance API endpoints:
```
https://api.binance.com:
https://api1.binance.com
https://api2.binance.com
https://api3.binance.com
https://api4.binance.com
```
"apikey"/"apisecret" - The user must create their own API key and secret for their Binance account.

### WSS

Web socket uses to configure WSS endpoints.

Basic configuration:
```
    "WSS" : {
        "host" : "stream.binance.com",
        "port" : "443"
    }
```

Known endpoints:
```
wss://stream.binance.com:9443
wss://stream.binance.com:443
```

### Markets

Basic configuration:
```
    "Markets" : {
        "btcusdt" : {
            "buy" : {
                "trend"         : 0,
                "maxtrend"      : 1000,
                "stepforward"   : 2,
                "stepback"      : 3,
                "diffratelow"   : 0.15,
                "diffratehigh"  : 0.3,
                "minspread"     : -7,
                "historycheck"  : 336,
                "emamethod"     : 0,
                "orderprice"    : 15,
                "nextbuyorder"  : 0.975
            },
            "sell": {
                "trend"         : 0,
                "maxtrend"      : 1000,
                "stepforward"   : 2,
                "stepback"      : 3,
                "nextsellorder" : 0.03
            }
        },
        "ethusdt" : {
            "buy" : {
                "trend"         : 0,
                "maxtrend"      : 1000,
                "stepforward"   : 2,
                "stepback"      : 3,
                "diffratelow"   : 0.15,
                "diffratehigh"  : 0.3,
                "minspread"     : -7,
                "historycheck"  : 336,
                "emamethod"     : 1,
                "orderprice"    : 15,
                "nextbuyorder"  : 0.975
            },
            "sell": {
                "trend"         : 0,
                "maxtrend"      : 1000,
                "stepforward"   : 2,
                "stepback"      : 3,
                "nextsellorder" : 0.03
            }
        }
    }
```

This section describes behaviour of each market. In process of trading bot compares current values with configuration. If all tests passed, it performs a buy or sell.

## Update Log

2024-05-19

- Added watchdog for WSS
- Minor Fixes
