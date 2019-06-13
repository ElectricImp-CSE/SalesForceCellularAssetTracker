# Salesforce Cellular Asset Tracker #

## Overview #

This is software for a cellular asset tracker. The tracker monitors GPS location and temperature, reporting data to Salesforce at a set interval. If a change in the GPS location is noted the device will report it's new location immediately. 

Please note: 
- This version of the software is not battery efficient. As use cases are specified the code can then be optimized to conserve battery base for that use case. 
- Onboard breakout board temperature sensor is currently used for temperature monitoring. Future software will update to use a bluetooth temperature sensor.


## Hardware #

Basic tracker hardware:

- impC001 cellular module
- impC001 breakout board
- u-blox M8N GPS module
- [3.7V 2000mAh battery from Adafruit](https://www.adafruit.com/product/2011?gclid=EAIaIQobChMIh7uL6pP83AIVS0sNCh1NNQUsEAQYAiABEgKFA_D_BwE)

Optional/Future improvements: 

- WiFi/bluetooth click
- BLE iBeacon temperature sensor 

## Setup ##

### Ublox Assist Now ### 

This project uses u-blox AssistNow services, and requires and account and authorization token from u-blox. To apply for an account register [here](http://www.u-blox.com/services-form.html). 

### Salesforce Configuration ### 

TODO: add instructions re: setting up Salesforce account, creating connected app, etc.

** device flow auth (do this for getting started)
** jwt flow auth (this is recommended for production)

### Electric Imp Configuration ### 

TODO: add instructions re: setting up EI account

This project has been written using [VS code plug-in](https://github.com/electricimp/vscode). All configuration settings and pre-processed files have been excluded. Follow the instructions [here](https://github.com/electricimp/vscode#installation) to install the plug-in and create a project. 

Replace the **src** folder in your newly created project with the **src** folder found in this repository

TODO: add salesforce creds to imp.config file.

Update settings/imp.config "device_code", "agent_code", and "builderSettings" to the following (updating the UBLOX_ASSISTNOW_TOKEN with your u-blox Assist Now authorization token):

```
    "device_code": "src/device/Main.device.nut"
    "agent_code": "src/agent/Main.agent.nut"
    "builderSettings": {
        "variable_definitions": {
            "UBLOX_ASSISTNOW_TOKEN" : "<YOUR-UBLOX-ASSIST-NOW-TOKEN-HERE>"
        }
    }
```

### Offline logging ###

For development purposes uart logging is recommended to see offline device logs. Current code uses hardware.uartDCAB (A: RTS, B: CTS, C: RX, D: TX) for uart logging. 

## Customization ##

Settings are all stored as constants. Modify to customize the application. To save power put the device to sleep between reporting intervals (Note: The impC001 takes ~40s to connect.)

TODO: add listeners from salesforce (bayeux client) for updating settings (ie temp thresholds, reporting intervals etc)

# License

Code licensed under the [MIT License](./LICENSE).