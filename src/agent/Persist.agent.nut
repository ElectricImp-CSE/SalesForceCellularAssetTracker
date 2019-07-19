// -----------------------------------------------------------------------
// Persistant Storage File
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

enum PERSIST_ERASE_SCOPE {
    ALL,
    SF_AUTH,
    SF_TOKEN,
    SF_AUTH_TYPE,
    SF_INSTANCE_URL
}

// Manages Persistant Storage  
// Dependencies: Agent storage (ie server.save, server.load)
class Persist {

    _persist = null;
    _sfAuth = null;

    constructor() {
        _persist = server.load();
        if ("sfAuth" in _persist) { 
            _sfAuth = _persist.sfAuth;
        } else {
            _sfAuth = {};
        }
    }

    function erase(scope = PERSIST_ERASE_SCOPE.ALL) {
        // Update class vars
        switch(scope) {
            case PERSIST_ERASE_SCOPE.ALL:
                _persist = {};
                break;
            case PERSIST_ERASE_SCOPE.SF_AUTH:
                if ("sfToken" in _persist) _persist.rawdelete("sfToken");
                _sfAuth = {};
                _persist.sfAuth <- _sfAuth;
                break;
            case PERSIST_ERASE_SCOPE.SF_TOKEN:
                if ("sfToken" in _persist) _persist.rawdelete("sfToken");
                if ("token" in _sfAuth) _sfAuth.rawdelete("token");
                _persist.sfAuth <- _sfAuth;
                break;
            case PERSIST_ERASE_SCOPE.SF_AUTH_TYPE:
                if ("type" in _sfAuth) _sfAuth.rawdelete("type");
                _persist.sfAuth <- _sfAuth;
                break;
            case PERSIST_ERASE_SCOPE.SF_INSTANCE_URL:
                if ("instURL" in _sfAuth) _sfAuth.rawdelete("instURL");
                _persist.sfAuth <- _sfAuth;
                break;
        }
        // Update agent persistant storage
        server.save(_persist);
    }

    function getSFToken() {
        return ("token" in _sfAuth) ? _sfAuth.token : null;
    }

    function setSFToken(token) {
        if (token != getSFToken()) {
            ::debug("[Persist] Updating stored salesforce token.");
            _sfAuth.token <- token;
            _storeSFAuth();
        }
    }

    function getSFInstanceURL() {
        return ("instURL" in _sfAuth) ? _sfAuth.instURL : null;
    }

    function setSFInstanceURL(instURL) {
        if (instURL != getSFInstanceURL()) {
            ::debug("[Persist] Updating stored salesforce instance URL.");
            _sfAuth.instURL <- instURL;
            _storeSFAuth();
        }
    }

    function getSFAuthType() {
        return ("auth" in _sfAuth) ? _sfAuth.auth : null;
    }

    function setSFAuthType(auth) {
        if (auth != getSFAuthType()) {
            ::debug("[Persist] Updating stored salesforce auth type.");
            _sfAuth.auth <- auth;
            _storeSFAuth();
        }
    }

    function _storeSFAuth() {
        _persist.sfAuth <- _sfAuth;
        server.save(_persist);
    }

}

// End Persistant Storage File
// -----------------------------------------------------------------------