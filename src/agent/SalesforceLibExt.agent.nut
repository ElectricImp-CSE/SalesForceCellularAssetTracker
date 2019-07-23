// -----------------------------------------------------------------------
// Patch for Salesforce Library
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

// Patch for Salesforce Library  
// Dependencies: Salesforce library 
class SalesforceExt extends Salesforce {

    _token = null;

    constructor(sfVersion = null) {
        if (sfVersion != null) _version = sfVersion;
    }

    // Function to set credentials (used to be done in constructor), only needed if 
    // login function is used
    function configureLoginCredentials(consumerKey, consumerSecret) {
        _clientId = consumerKey;
        _clientSecret = consumerSecret;
    }

    function setUserId(id) {
        _userUrl = id;
    }

    function getUser(cb = null) {
        local err = "";
        if (!isLoggedIn()) err += "AUTH_ERR: No authentication information. ";
        if (_userUrl == null) err += "No user id available, cannot get user.";
        
        if (err.len > 0) {
            err = "[SalesforceExt] "+ err;
            if (cb) {
                cb(err, null);
                return;
            } else {
                throw err;
            }
        }
        
        local headers = {
            "Authorization": "Bearer " + _token,
            "content-type": "application/json",
            "accept": "application/json"
        }

        local req = http.get(_userUrl, headers);
        return _processRequest(req, cb);
    }

}

// End Patch for Salesforce Library
// -----------------------------------------------------------------------