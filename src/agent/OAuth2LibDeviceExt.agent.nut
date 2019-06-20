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

// Patch for OAuth2 Library

// Patch for OAuth2 Library, Device Flow Client class
// Dependencies: OAuth2 library 
class OAuth2LibDeviceExt extends OAuth2.DeviceFlow.Client {

    // Sends Device Authorization Request to provider's device authorization endpoint.
    // Parameters:
    //          tokenReadyCallback  - The handler to be called when access token is acquired
    //                                or error is observed. The handle's signature:
    //                                  tokenReadyCallback(token, error), where
    //                                      token   - access token string
    //                                      error   - error description string
    //
    //          notifyUserCallback  -  The handler to be called when user action is required.
    //                                  https://tools.ietf.org/html/draft-ietf-oauth-device-flow-05#section-3.3
    //                                  The handler's signature:
    //                                      notifyUserCallback(verification_uri, user_code), where
    //                                          verification_uri  - the URI the user need to use for client authorization
    //                                          user_code         - the code the user need to use somewhere at authorization server
    //
    function _requestCode(tokenCallback, notifyUserCallback) {
        if (_isBusy()) {
                _log("Resetting ongoing session with token id: " + _currentTokenId);
                _reset();
        }

        // incrementing the token # to cancel the previous one
        _currentTokenId++;

        local data = {
            "scope": _scope,
            "client_id": _clientId,
            "response_type": _grantType     // ** Change from library, line added 
        };

        _doPostWithHttpCallback(_loginHost, data, _requestCodeCallback,
                                [tokenCallback, notifyUserCallback]);
        _changeStatus(Oauth2DeviceFlowState.REQUEST_CODE);

        return null;
    }

    // Sends Device Access Token Request to provider's token host.
    //          cb  - The handler to be called when access token is acquired
    //                 or error is observed. The handle's signature:
    //                    tokenReadyCallback(token, error), where
    //                        token   - access token string
    //                        error   - error description string
    // Returns:
    //      error description if Client doesn't wait device authorization from the user
    //                        or if time to wait for user action has expired,
    //      Null otherwise
    function _poll(cb) {
        // is it user call?
        if (_status != Oauth2DeviceFlowState.WAIT_USER) {
            return "Invalid status. Do not call _poll directly";
        }

        if (date().time > _expiresAt) {
            _reset();
            local msg = "Token acquiring timeout";
            _log(msg);
            cb(null, msg);
            return msg;
        }

        local data = {
            "client_id"     : _clientId,
            "code"          : _deviceCode,
            "grant_type"    : "device",         // ** Change from library, variable updated 
        };

        if (null != _clientSecret)  data.client_secret <- _clientSecret;

        _doPostWithHttpCallback(_tokenHost, data, _doPollCallback, [cb]);
    }


    // Extracts data from  Device Authorization Response
    // Parameters:
    //      respData    - a table parsed from http response body
    //
    // Returns:
    //      error description if the table doesn't contain required keys,
    //      Null otherwise
    function _extractPollData(respData) {
        if (!("verification_uri" in respData) ||        // ** Change from library, slot name updated
            !("user_code"        in respData) ||
            !("device_code"      in respData)) {
                return "Response doesn't contain all required data";
        }
        _verificationUrl = respData.verification_uri;   // ** Change from library, variable updated
        _userCode        = respData.user_code;
        _deviceCode      = respData.device_code;

        if ("interval"   in respData) _pollTime  = respData.interval;

        if("expires_in"  in respData) _expiresAt = respData.expires_in + date().time;
        else                          _expiresAt = date().time + OAUTH2_DEFAULT_POLL_TIME_SEC;

        return null;
    }
}