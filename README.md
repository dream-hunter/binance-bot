# binance-bot

Development just started...

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
