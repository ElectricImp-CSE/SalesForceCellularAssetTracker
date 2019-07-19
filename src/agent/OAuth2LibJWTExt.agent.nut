// -----------------------------------------------------------------------
// Patch for OAuth2 Library JWT Flow Client
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

// Patch for OAuth2 Library, JWT Flow Client class
// Dependencies: OAuth2 library 
class OAuth2LibJWTExt extends OAuth2.JWTProfile.Client {

    // Processes response from OAuth provider
    // Parameters:
    //          resp  - httpresponse instance
    //
    // Returns: Nothing
    function _doTokenCallback(resp) {
        if (resp.statuscode == 200) {
            // Cache the new token, pull in the expiry a little just in case
            local body = http.jsondecode(resp.body);
            local err = client._extractToken(body);
            userCallback(client._accessToken, err, body);
        } else {
            // Error getting token
            local err = "Error getting token: " + resp.statuscode + " " + resp.body;
            ::log("[OAuth2LibJWTExt]: " + err);
            userCallback(null, err, resp);
        }
    }    

}

// End Patch for OAuth2 Library JWT Flow Client
// -----------------------------------------------------------------------