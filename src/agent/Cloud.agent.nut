// -----------------------------------------------------------------------
// Salesforce Cloud Service File 
@
@ // MIT License
@
@ // Copyright 2019 Electric Imp
@
@ // SPDX-License-Identifier: MIT
@
@ // Permission is hereby granted, free of charge, to any person obtaining a copy
@ // of this software and associated documentation files (the "Software"), to deal
@ // in the Software without restriction, including without limitation the rights
@ // to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
@ // copies of the Software, and to permit persons to whom the Software is
@ // furnished to do so, subject to the following conditions:
@
@ // The above copyright notice and this permission notice shall be
@ // included in all copies or substantial portions of the Software.
@
@ // THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
@ // EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
@ // MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
@ // EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
@ // OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
@ // ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
@ // OTHER DEALINGS IN THE SOFTWARE.

// Salesforce Event Strings Test App
const SF_EVENT_NAME       = "Device_Condition__e";
const SF_EVENT_DATA_LAT   = "Latitude__c";
const SF_EVENT_DATA_LNG   = "Longitude__c";
const SF_EVENT_DATA_TEMP  = "Temperature__c";
const SF_EVENT_DATA_HUMID = "Humidity__c";
const SF_EVENT_DEV_ID     = "Device_Id__c";

// Salesforce Event Strings Striker App
// const SF_EVENT_NAME           = "Tote_Location_Changed__e";
// const SF_EVENT_DATA_LAT       = "Latitude__c";
// const SF_EVENT_DATA_LNG       = "Longitude__c";
// const SF_EVENT_DATA_SIG       = "Signal_Strength__c";
// const SF_EVENT_DATA_BEACON_ID = "Beacon_Id__c";
// const SF_EVENT_DEV_ID         = "Tote_Id__c";

const SF_VERSION              = "v46.0";

enum SF_AUTH_TYPE {
    JWT, 
    DEVICE
}

enum SF_ERROR_CODES {
    MISSING_FIELD = "REQUIRED_FIELD_MISSING",
    INVALID_SESSION_ID = "INVALID_SESSION_ID"
}

// Manages Cloud Service Communications  
// NOTE: Current code only supports sending events to Salesforce

// Dependencies: Salesforce library, OAuth2 library, SalesforceLibExt, 
// Saleforce OAuth2JWT, Saleforce OAuth2Device, Persist
// Initializes: Salesforce library, OAuth2 library, SalesforceLibExt, 
// Saleforce OAuth2JWT and Saleforce OAuth2Device
class Cloud {

    _force       = null;
    _oauth       = null;
    _persist     = null;

    _sendUrl     = null;
    _impDeviceId = null;
    _authType    = null;

    constructor(persist) {

        _impDeviceId = imp.configparams.deviceid;
        _sendUrl = format("sobjects/%s/", SF_EVENT_NAME);

        // Store reference to persistant storage class instance
        _persist = persist;
        // Use this for testing auth, comment out when not testing auth
        // Erases everything in server.save
        // _persist.erase();

        // Select DEVICE or JWT Authentication
        _authType = SF_AUTH_TYPE.DEVICE;
        if (_authType != _persist.getSFAuthType()) {
            // Erase stored Salesforce auth data if we have changed how
            // we are authenticating
            _persist.erase(PERSIST_ERASE_SCOPE.SF_AUTH);
            _persist.setSFAuthType(_authType);
        }

        // Initialize Saleforce library 
        _force = Salesforce(SF_VERSION);
        // Try to retrieve instance URL
        local instanceURL = _persist.getSFInstanceURL();
        if (instanceURL != null) _force.setInstanceUrl(instanceURL);
        
        // Authorize device
        _authorize();
    }

    function send(data) {
        local body = _formatReport(data);
        if (!_force.isLoggedIn()) {
            ::error("[Cloud] Not logged into Salesforce. Unable to send data: ");
            ::debug(body);
        } else {
            ::debug("[Cloud] Sending data to Salesforce:");
            ::debug(body);
            _force.request("POST", _sendUrl, body, _onReportSent.bindenv(this)); 
        }        
    }

    function _onReportSent(err, respData) {
        if (err) {
            ::debug("[Cloud] Salesforce reporting error occurred: ");
            ::error(err);
        } else {
            ::debug("[Cloud] Salesforce readings sent successfully");
        }
    }

    function _formatReport(rawReport) {
        local report = { [SF_EVENT_DEV_ID] = _impDeviceId };
        report[SF_EVENT_DATA_HUMID] <- ("humid" in rawReport) ? rawReport.humid : 0;
        report[SF_EVENT_DATA_TEMP]  <- ("temp" in rawReport) ? rawReport.temp : 0;
        report[SF_EVENT_DATA_LAT]   <- ("lat" in rawReport) ? rawReport.lat.tofloat() : 0;
        report[SF_EVENT_DATA_LNG]   <- ("lng" in rawReport) ? rawReport.lng.tofloat() : 0;

        return http.jsonencode(report);

        /* Data formatting comments:
            Salesforce expects: 
            { 
            "Humidity__c" : 123,  
            "Latitude__c" : 12.123, 
            "Longitude__c": 12.123, 
            "Temperature__c": 12.2, 
            "Device_Id__c": "16charstring" 
            }

            Raw report data: 
            { 
            "lat"        : "37.3954260", 
            "lng"        : "-122.1023625", 
            "temp"       : 27.04978, 
            "humid"      : 40.791862,
            "ts"         : 1560814813, 
            "battStatus" : 
                { 
                "percent"  : 88.828125, 
                "capacity" : 2143.5 
                }, 
            "fix"        : 
                { 
                "secToFix"   : 65.886002, 
                "lng"        : -1221023625, 
                "fixType"    : 3, 
                "lat"        : 373954260, 
                "numSats"    : 7, 
                "accuracy"   : 9.7880001, 
                "time"       : "2019-06-17T23:35:08Z", 
                "secTo1stFix": 38.909 
                }
            }
        */
    }

    function _authorize() {
        local token = _persist.getSFToken();
        if (token != null) {
            // Set token
            _force.setToken(token);

            // Ping Saleforce to see if token is valid
            // NOTE: SF must recognize device or ping will fail
            local pingData = { [SF_EVENT_DEV_ID] = _impDeviceId };
            _force.request("POST", _sendUrl, http.jsonencode(pingData), _onAuthPing.bindenv(this));
        } else {
            _triggerOAuthFlow();
        }
    }

    function _onAuthPing(err, resp) {
        if (err != null) { 
            ::debug("[Cloud] " + err);

            try {
                // Try to parse response to get error code
                local body = http.jsondecode(resp.body);
                local e = (typeof body == "array") ? body[0] : body;
                local errIsTable = (typeof e == "table");

                local errCode = (errIsTable && "errorCode" in e) ? e.errorCode : null;
                ::debug("[Cloud] ping error code: " + errCode);

                switch (errCode) {
                    case SF_ERROR_CODES.MISSING_FIELD:
                        ::debug("[Cloud] Used stored token to authorize device with Salesforce");
                        return;
                    case SF_ERROR_CODES.INVALID_SESSION_ID:
                        ::debug("[Cloud] Stored token expired");
                        break;
                    default: 
                        ::debug("[Cloud] Salesforce send ping unexpected error occurred: ");
                        ::error(resp.body);
                }
            } catch(e) {
                ::debug("[Cloud] ping error unable to parse response: " + e);
            }

            // Our stored token is bad, erase it from storage and SF instance
            ::debug("[Cloud] Erasing stored token. Starting new authentication with Salesforce.");
            _persist.setSFToken(null);
            _force.setToken(null);
            // Try to re-authorize
            _triggerOAuthFlow();
        } else {
            ::debug("[Cloud] Used stored token to authorize device with Salesforce, statuscode: " + resp.statuscode);
        }
    }

    function _triggerOAuthFlow() {
        switch (_authType) {
            case SF_AUTH_TYPE.JWT:
                ::debug("[Cloud] OAuth type: JWT");
                _oauth = SalesForceOAuth2JWT();
                break;
            case SF_AUTH_TYPE.DEVICE:
            ::debug("[Cloud] OAuth type: DEVICE");
                _oauth = SalesForceOAuth2Device();
                break;
            default: 
                ::error("[Cloud] Unexpected authorization type. Not logging into Salesforce");
        }

        // Authorize device/get token
        _oauth.getToken(_onGetOAuthToken.bindenv(this))
    }

    function _onGetOAuthToken(err, token, resp) {
        if (err) {
            ::error("[Cloud] Unable to log into Salesforce: " + err);
            return;
        }

        if (resp != null) {
            local parsed = _force.processAuthResp(resp);
            if (parsed.err == null) {
                local body = parsed.data;
                _persist.setSFToken(token);
                _persist.setSFInstanceURL(body.instance_url);
                if ("id" in body) _persist.setSFUserId(body.id);
            } else {
                ::error("[Cloud] Unable parse Salesforce auth response: " + parsed.err);
            }
        } else {
            ::debug("[Cloud] Token handler did not contain HTTP response");
        }

    }

}

// End Salesforce Cloud Service File
// -----------------------------------------------------------------------