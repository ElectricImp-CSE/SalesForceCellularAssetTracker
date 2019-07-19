# Salesforce Cellular Asset Tracker #

## Overview ##

This is software for a cellular asset tracker. The tracker monitors GPS location and temperature, reporting data to Salesforce at a set interval. If a change in the GPS location is noted the device will report it's new location immediately. 

Please note: 
- This version of the software is not battery efficient. As use cases are specified the code can then be optimized to conserve battery base for that use case. 
- Onboard breakout board temperature sensor is currently used for temperature monitoring. As use cases are specified external temperature sensors (ie bluetooth) can be used instead.

## Hardware ##

Basic tracker hardware:

- impC001 cellular module
- impC001 breakout board
- u-blox M8N GPS module
- [3.7V 2000mAh battery from Adafruit](https://www.adafruit.com/product/2011?gclid=EAIaIQobChMIh7uL6pP83AIVS0sNCh1NNQUsEAQYAiABEgKFA_D_BwE)

## Setup ##

### Ublox Assist Now ### 

This project uses u-blox AssistNow services, and requires and account and authorization token from u-blox. To apply for an account register [here](http://www.u-blox.com/services-form.html). Please note this process may take a couple days before a token is issued.

### Salesforce Configuration ### 

TODO: Add instructions re: setting up Salesforce account, creating events etc.

See [platform event trailhead](https://trailhead.salesforce.com/en/content/learn/modules/platform_events_basics/platform_events_define_publish) for how to create a platform event. This code uses the REST API to publish events.  

Platform event and custom field names are stored as constants in the agent > Cloud.agent.nut file. Current code uses the following names: 
```
const SF_EVENT_NAME       = "Device_Condition__e";
const SF_EVENT_DATA_LAT   = "Latitude__c";
const SF_EVENT_DATA_LNG   = "Longitude__c";
const SF_EVENT_DATA_TEMP  = "Temperature__c";
const SF_EVENT_DATA_HUMID = "Humidity__c";
const SF_EVENT_DEV_ID     = "Device_Id__c";
```

### Salesforce Authentication ###

To authenticate your device with Salesforce you will need to create a *Salesforce Connected Application*. The settings are slightly different based on you you choose to authenticate with Salesforce. Select either the [Device OAuth Flow](#device-oauth-flow) or [JWT OAuth Flow](#jwt-oauth-flow) and follow the setup instructions in that section. Then, when finished with the steps in the authentication section, skip ahead to the [Electric Imp Configuration](#electric-imp-configuration) section to continue setting up your project.

#### Device OAuth Flow ####

The OAuth2.0 Device flow may be easier when getting started but is not recommended for production, since each device will require a physical log-in from a browser. In this flow the imp will log a url and a code that will used to load a Salesforce log-in page. That log-in will then authorize the device to send data to Salesforce. 

##### Create A Salesforce Connected Application #####

- Log into Salesforce
- Select *Setup* then in the sidebar under *Platform Tools* -> *Apps* select *App Manager*
- Click *New Connected App* and fill out the following:
    - Under *Basic Information*
        - Enter a name for your app
        - Enter your email
    - Under *API (Enable OAuth Settings)*
        - Check Enable OAuth Settings
        - Enter a callback URL, ie `http://localhost:1717/OauthRedirect` 
        - Check *Enable for Device Flow*
        - Add the following OAuth Scopes 
            - Access and manage your data (api)
            - Perform requests on your behalf at any time (refresh_token, offline_access)
            - Provide access to your data via the Web (web)
    - Click *Save*
- Copy down your **Consumer Key** and **Consumer Secret**. These will need to be added to your Squirrel code.

##### Authorizing Your Device #####

These steps will need to be followed once your device starts to run the Squirrel application code. Please skim through them so you are familiar with what you need to look out for. 

Once your device is running, you will see logs similar to the following:  

```
2019-06-21 14:23:14-0700 [Agent]  [INFO]: -----------------------------------------------------------------
2019-06-21 14:23:14-0700 [Agent]  [INFO]: [SalesForceOAuth2Device] Salesforce: Authorization is pending. Please grant access
2019-06-21 14:23:14-0700 [Agent]  [INFO]: [SalesForceOAuth2Device] URL: https://login.salesforce.com/setup/connect
2019-06-21 14:23:14-0700 [Agent]  [INFO]: [SalesForceOAuth2Device] Code: 6VL44ZGC
2019-06-21 14:23:14-0700 [Agent]  [INFO]: -----------------------------------------------------------------
2019-06-21 14:23:20-0700 [Agent]  [OAuth2DeviceFlow] Polling error:authorization_pending
```

Copy and paste the URL in a web browser, then copy and paste the alpha numeric code (ie 6VL44ZGC) into the form on that webpage. You will be re-directed to a salesforce log-in page (if you are not currently logged into Salesforce). Once you log in you will see the following logs from your imp device:

```
2019-06-21 14:23:24-0700 [Agent]  [OAuth2DeviceFlow] Polling error:authorization_pending
2019-06-21 14:23:30-0700 [Agent]  [OAuth2DeviceFlow] Polling error:authorization_pending
2019-06-21 14:23:35-0700 [Agent]  [OAuth2DeviceFlow] Polling success
2019-06-21 14:23:35-0700 [Agent]  [OAuth2DeviceFlow] Change status of session1 from 2 to 0
```

Your device is now authorized and will begin sending data to Salesforce.

Please skip ahead to [Electric Imp Configuration](#electric-imp-configuration) section to continue setting up your project.

#### JWT OAuth Flow ####

The OAuth2.0 JWT flow is recommended for production. The JWT bearer flow supports the RSA SHA256 algorithm, which uses an uploaded certificate as the signing secret. In this example we will use `openssl` to generate a certificate. 

##### Generate Certificate #####

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

##### Create A Salesforce Connected Application #####

- Log into Salesforce
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

##### Edit Salesforce OAuth Policies #####

Edit the policies to enable the connected app to circumvent the manual login process. Under your application:

- Select or Click *Manage*
- Click *Edit Policies*
    - Under *OAuth policies* 
        - Select *Admin approved users are pre-authorized* from *Permitted Users* dropdown
    - Click *Save*
 
##### Create Salesforce Permission Set #####

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

#### Connecting Your Device ####

Sign up for an Electric Imp account [here](https://impcentral.electricimp.com), then follow the instructions in this [getting started guide](https://developer.electricimp.com/gettingstarted/impc001breakoutboard) to connect your impC001 using blinkUp. Make a note of your Device Id. You will want to add this device to your project/device group.

#### Configuring a VS Code Project ####

To make the code scalable and maintainable, this project has been written using [VS code plug-in](https://github.com/electricimp/vscode). All configuration settings and the pre-processed squirrel files have been excluded, so sensitive keys are not exposed. Follow the instructions [here](https://github.com/electricimp/vscode#installation) to install the plug-in and create a project. 

#### Updating Project Configuration Settings ####

Update settings/imp.config file. This file will store your application's sensitive keys and should never be committed to Github.

- *device_code* value should be changed to "src/device/Main.device.nut"
- *agent_code* value should be changed to "src/agent/Main.agent.nut"
- *builderSettings* table should be updated with your application's secret keys
    - *UBLOX_ASSISTNOW_TOKEN* value should be updated with your u-blox Assist Now authorization token
    - *SF_CONSUMER_KEY* value should be updated with your Salesforce connected app's consumer key
    - *SF_CONSUMER_SECRET* value should be updated with your Salesforce connected app's consumer secret
- If using the JWT Authentication flow you will need to update these *builderSettings* as well:
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
      "SF_AUTH_URL" : "https://login.salesforce.com/services/oauth2/token",
      "SF_CONSUMER_KEY" : "<YOUR-SALESFORCE-CONSUMER-KEY-HERE>",
      "SF_CONSUMER_SECRET" : "<YOUR-SALESFORCE-CONSUMER-SECRET-HERE>",
      "SF_JWT_PVT_KEY" : "<YOUR-SALESFORCE-JWT-PRIVATE-KEY-HERE>",
      "SF_USERNAME" : "<YOUR-SALESFORCE-USERNAME>"
    }
  }
}
```

#### Updating Project Code ####

Replace the **src** folder in your newly created project with the **src** folder found in this repository. 

Next we need to make sure the code is configured to authenticate the same way you have configured in your Salesforce connected app. Navigate to the *src/agent/Cloud.agent.nut file*. In the constructor look for the line that sets the `_authType` variable, and set it up to match your auth flow configuration. 

For *JWT OAuth Flow* set it to the following: 

```
// Select Device or JWT Authentication
_authType = SF_AUTH_TYPE.JWT;
```

For *Device OAuth Flow* set it to the following: 
```
// Select Device or JWT Authentication
_authType = SF_AUTH_TYPE.DEVICE;
```

#### Deploying Your Application Code ####

You are now ready to upload and deploy your application code. To deploy code:

- Open the Command Palette by selecting *Command Palette...* from the *View* menu
- In the pop-up type/select *imp: Deploy Project*

or 

- Use the keyboard shortcut `CTRL+SHIFT+X`

You may need to select your device if it is not assigned to your device group yet. Once your device is assigned, you should now see device logs in the *OUTPUT* tab. 

If you used the [Device OAuth Flow](#device-oauth-flow) look for in the logs to find the URL and Code to authorize your device. See detailed instructions on how to use them [here](#authorizing-your-device).

### Offline logging ###

For development purposes this project also supports uart logging, this is recommended if you need to see logs when a device is running offline. Current code uses hardware.uartDCAB (A: RTS, B: CTS, C: RX, D: TX) for uart logging. 

## Customization ##

Settings are all stored as constants. Modify to customize the application. To save power put the device to sleep between reporting intervals (Note: The impC001 takes ~40s to connect.)

Possible optimizations: 

- Update code to support BLE temperature sensor
- Add temperature and humidity thresholds that send alerts when crossed
- Add listeners from Salesforce (Bayeux client) for updating settings (ie temp thresholds, reporting intervals etc)
- Update the device code to disconnect and sleep between check-ins and reporting to conserve power

# License #

Code licensed under the [MIT License](./LICENSE).
