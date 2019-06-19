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

// Manages Salesforce OAuth2 via JWT Flow  
// Dependencies: OAuth2 library 
// Initializes: OAuth2 library
class SalesForceOAuth2JWT {

    client = null;

    constructor() {
        // NOTE: 365 day cert created on 6/18/19
        local userSettings = { 
            "iss" : "@{SF_CONSUMER_KEY}",
            "jwtSignKey" : @"@{SF_JWT_PVT_KEY}", 
            "sub" : "@{SF_USERNAME}",
            "scope" : ""
        };

        local providerSettings = {
            "tokenHost" : SF_AUTH_URL
        }

        client = OAuth2.JWTProfile.Client(providerSettings, userSettings);
    }

    function getToken(cb) {
        local token = client.getValidAccessTokenOrNull();
        if (token != null) {
            // We have a valid token already
            ::debug("Salesforce access token aquired.");
            cb(null, token);
        } else {
            // Acquire a new access token
            client.acquireAccessToken(function(newToken, err) {
                cb(err, newToken);
            }.bindenv(this));
        }
    }
}