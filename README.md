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

TODO: add instructions re: setting up Salesforce account, creating events etc.

### Device OAuth Flow ### 

The OAuth2.0 Device flow may be easier when getting started but is not recommended for production. 

NOTE: This flow is not supported by the current code base yet. Please use JWT OAuth Flow. 

### JWT OAuth Flow ###

The OAuth2.0 JWT flow is recommended for production. The JWT bearer flow supports the RSA SHA256 algorithm, which uses an uploaded certificate as the signing secret. In this example we will use `openssl` to generate a certificate. 

#### Generate Certificate ####

- Somewhere outside of your project directory create a folder that will not be shared to store your certificates for this application. It is important to keep track of these files since they contain sensitive information that others can use to compromise your system.

    `mkdir salesforce_cell_tracker_certificates`

- Change directories into your certificates folder

    `cd salesforce_cell_tracker_certificates`

- From inside certificates folder, generate an RSA private key

    `openssl genrsa -des3 -passout pass:x -out server.pass.key 2048`

- Create a key file from the server.pass.key file

    `openssl rsa -passin pass:x -in server.pass.key -out server.key`

- Delete the server.pass.key

    `rm server.pass.key`

- Request and generate the certificate

    `openssl req -new -key server.key -out server.csr`

- You will be asked to enter information to create a certificate. Enter everything except: 
    - Enter a period (.) to skip entering an optional company name
    - You will not need a challenge password, so just press `Enter`. The Certificate Authorities use this password to authenticate the certificate owner when they want to revoke their certificate. Because it’s a self-signed certificate, there’s no way to revoke it via CRL (Certificate Revocation List).

- Generate the SSL certificate

    `openssl x509 -req -sha256 -days 365 -in server.csr -signkey server.key -out server.crt`

- You should now have 3 files in this folder 
    - `server.crt` - your site certificate, this will be uploaded to your connected app
    - `server.csr` 
    - `server.key` - this is the key that will be used in your code to authenticate your device

#### Create And Configure Salesforce Connected Application ####

Log into salesforce. 

##### Create App #####

- Select *Setup* then in the sidebar under *Platform Tools* -> *Apps* select *App Manager*
- Click *New Connected App* and fill out the following:
    - Under *Basic Information*
        - Enter a name for your app
        - Enter your email
    - Under *API (Enable OAuth Settings)*
        - Check Enable OAuth Settings
        - Enter a callback URL, ie `http://localhost:1717/OauthRedirect` 
        - Check *Use digital signatures*
            - Click *Choose file* and select the `server.crt` file you just created
        - Add the following OAuth Scopes 
            - Access and manage your data (api)
            - Perform requests on your behalf at any time (refresh_token, offline_access)
            - Provide access to your data via the Web (web)
    - Click *Save*
- Copy down your **Consumer Key** and **Consumer Secret**. These will need to be added to your Squirrel code.

##### Edit Policies #####

Edit the policies to enable the connected app to circumvent the manual login process. Under your application:

- Select or Click *Manage*
- Click *Edit Policies*
    - Under *OAuth policies* 
        - Select *Admin approved users are pre-authorized* from *Permitted Users* dropdown
    - Click *Save*
 
##### Create Permission Set #####

Create a permission set and assign pre-authorized users for this connected app.

- Select *Setup* then in the sidebar under *Administration* -> *Users* select *Permission Sets*
- Click *New*
    - Enter a *Label* 
    - Click *Save* 
- Click on your new permission set label
- Click *Manage Assignments*
- Click *Add Assignments*
    - Check the box to select the User that matches your username
    - Click *Assign* & *Done*
- Navigate back to your connected app
    - In the sidebar under *Platform Tools* -> *Apps* select *App Manager*
    - In the list of of apps find your app and under the dropdown arrow on the left select *Manage*
    - Scroll down to the *Permission Sets* section and click the *Manage Permission Sets* button
    - Select the permission set that matches your new permission set label
    - Click *Save*

### Electric Imp Configuration ### 

Sign up for an Electric Imp account [here](https://impcentral.electricimp.com), then follow the instructions in this [getting started guide](https://developer.electricimp.com/gettingstarted/impc001breakoutboard) to connect your impC001 using blinkUp. Make a note of your Device Id. You will want to add this device to your project/device group.

This project has been written using [VS code plug-in](https://github.com/electricimp/vscode). All configuration settings and pre-processed files have been excluded. Follow the instructions [here](https://github.com/electricimp/vscode#installation) to install the plug-in and create a project. 

Replace the **src** folder in your newly created project with the **src** folder found in this repository

Update settings/imp.config file. This file will store your application's sensitive keys and should never be committed to Github.

- *device_code* value should be changed to "src/device/Main.device.nut"
- *agent_code* value should be changed to "src/agent/Main.agent.nut"
- *builderSettings* table should be updated with your application's secret keys
    - *UBLOX_ASSISTNOW_TOKEN* value should be updated with your u-blox Assist Now authorization token
    - *SF_CONSUMER_KEY* value should be updated with your Salesforce connected app's consumer key
    - *SF_CONSUMER_SECRET* value should be updated with your Salesforce connected app's consumer secret
    - *SF_JWT_PVT_KEY* value should be updated with the contents of the private key file generated with openssl in the [JWT Auth Flow Generate Certificate](#generate-certificate). NOTE: This file may need to be altered slightly so the contents become a single line separated with the new line char `\n` instead of a multi-line string
    - *SF_USERNAME* value should be updated with the account username that matches your connected app's account permissions

Example imp.config file: 
```
{
  "cloudURL": "https://api.electricimp.com/v5",
  "ownerId": "<YOUR-EI-OWNER-ID>",
  "deviceGroupId": "<YOUR-EI-DEVICE-GROUP-ID>",
  "device_code": "src/device/Main.device.nut",
  "agent_code": "src/agent/Main.agent.nut",
  "builderSettings": {
    "variable_definitions": {
      "UBLOX_ASSISTNOW_TOKEN": "<YOUR-UBLOX-ASSIST-NOW-TOKEN-HERE>",
      "SF_CONSUMER_KEY" : "<YOUR-SALESFORCE-CONSUMER-KEY-HERE>",
      "SF_CONSUMER_SECRET" : "<YOUR-SALESFORCE-CONSUMER-SECRET-HERE>",
      "SF_JWT_PVT_KEY" : "<YOUR-SALESFORCE-JWT-PRIVATE-KEY-HERE>",
      "SF_USERNAME" : "<YOUR-SALESFORCE-USERNAME>"
    }
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