// MIT License

// Copyright 2019 Electric Imp

// SPDX-License-Identifier: MIT

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
// EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
// OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

// Salesforce JWT OAuth2 Application File

const SF_AUTH_URL = "https://login.salesforce.com/services/oauth2/token";

// Manages Salesforce OAuth2 via Device Flow  
// Dependencies: OAuth2 library 
// Initializes: OAuth2 library
class SalesForceOAuth2Device {

    client = null;

    constructor() {
        local userConfig = { 
            "clientId"     : "@{SF_CONSUMER_KEY}",
            "clientSecret" : "@{SF_CONSUMER_SECRET}",
            "scope"        : "api refresh_token"
        };

        local providerConfig = {
            "loginHost" : SF_AUTH_URL, 
            "tokenHost" : SF_AUTH_URL,
            "grantType" : "device_code"
        }

        client = OAuth2.DeviceFlow.Client(providerConfig, userConfig);
    }

    function getToken(cb) {
        local token = client.getValidAccessTokenOrNull();
        if (token != null) {
            // We have a valid token already
            ::debug("Salesforce access token aquired.");
            cb(null, token);
        } else {
            // Acquire a new access token
            local status = client.acquireAccessToken(
                function(resp, err) {
                    cb(err, newToken);
                }.bindenv(this), 
                function(url, code) {
                    ::log("Salesforce: Authorization is pending. Please grant access");
                    ::log("URL: " + url);
                    ::log("Code: " + code);
                }.bindenv(this)
            );

            if (status != null) ::error("Salesforce: Client is already performing request (" + status + ")");
        }
    }

}


//             local data = {
//                  "scope": _scope,
//                  "client_id": _clientId,
// +                "response_type": _grantType
//              };
 
//              _doPostWithHttpCallback(_loginHost, data, _requestCodeCallback,
//              local data = {
//                  "client_id"     : _clientId,
//                  "code"          : _deviceCode,
// -                "grant_type"    : _grantType,
// +                "grant_type"    : "device",
//              };
 
//              if (null != _clientSecret)  data.client_secret <- _clientSecret; 
//          //          callbackArgs    - additional arguments to the handler
//          function _doPostWithHttpCallback(url, data, callback, callbackArgs) {
//              local body = http.urlencode(data);
// +            print(body);
//              local context = {
//                  "client" : this,
//                  "func"   : callback,     
//          //      error description if the table doesn't contain required keys,
//          //      Null otherwise
//          function _extractPollData(respData) {
// -            if (!("verification_url" in respData) ||
// +            if (!("verification_uri" in respData) ||
//                  !("user_code"        in respData) ||
//                  !("device_code"      in respData)) {
//                      return "Response doesn't contain all required data";
//              }
// -            _verificationUrl = respData.verification_url;
// +            _verificationUrl = respData.verification_uri;
//              _userCode        = respData.user_code;
//              _deviceCode      = respData.device_code;       
//              }
//          }
//      } // end of Client
// -}