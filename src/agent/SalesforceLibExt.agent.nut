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

// Patch for Salesforce Library

// Patch for Salesforce Library  
// Dependencies: Salesforce library 
class SalesforceExt extends Salesforce {

    _token      = null;
    _sfVersion  = null;

    constructor(sfVersion = null) {
        if (sfVersion != null) _sfVersion = sfVersion;
    }

    // Function to set credentials (used to be done in constructor), only needed if 
    // login function is used
    function configureLoginCredentials(consumerKey, consumerSecret) {
        _clientId = consumerKey;
        _clientSecret = consumerSecret;
    }

    function setUserUrl(url) {
        _userUrl = url;
    }

    function getUser(cb = null) {
        if (!isLoggedIn()) throw "AUTH_ERR: No authentication information."
        if (_userUrl == null && cb) cb("Salesforce: No user URL set, cannot get user.", null); 

        local headers = {
            "Authorization": "Bearer " + _token,
            "content-type": "application/json",
            "accept": "application/json"
        }

        local req = http.get(_userUrl, headers);
        return _processRequest(req, cb);
    }

}
