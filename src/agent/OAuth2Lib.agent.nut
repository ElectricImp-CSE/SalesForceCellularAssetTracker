// -----------------------------------------------------------------------
// Updated OAuth2 Library v2.1.0

/** Authorization service default poll period */
const OAUTH2_DEFAULT_POLL_TIME_SEC      = 300;
/** Default access token time to live */
const OAUTH2_TOKEN_DEFAULT_TTL_SEC      = 3600;
/** Default device flow grant type recommended by RFE */
const OAUTH2_DEVICE_FLOW_GRANT_TYPE     = "urn:ietf:params:oauth:grant-type:device_code";
/** Default grant type for JWT authorization */
const OAUTH2_JWT_GRANT_TYPE             = "urn:ietf:params:oauth:grant-type:jwt-bearer";

/** OAuth2 Client possible states */
enum Oauth2DeviceFlowState {
    IDLE,           // Default state, there is no network activity
    REQUEST_CODE,   // Request device and user codes
    WAIT_USER,      // Poll authorization server
    REFRESH_TOKEN   // Refreshing an access token
};

/**
 * The agent-side library for OAuth 2.0 authentication and authorization flows. 
 *
 * @class
 */
class OAuth2 {
    static VERSION = "2.1.0";
}

/**
 * OAuth 2.0 sub-class that provides authorization flow with JSON Web Token (JWT)
 *
 * @class
 */
class  OAuth2.JWTProfile {

    /**
    * OAuth 2.0 sub-class that provides OAuth 2.0 with the JSON Web Token (JWT) profile 
    *   for Client Authentication and Authorization Grants as defined in 
    *   IETF RFC 7523 (https://tools.ietf.org/html/rfc7523). 
    *
    * @class
    */
    Client = class {

        /** OAuth2 provider's token endpoint */
        _tokenHost = null;

        /** Issuer of the JWT  */
        _iss = null;
        /** Private key for JWT sign  */
        _jwtSignKey = null;
        /** The scope of the access - https://tools.ietf.org/html/rfc6749#section-3.3  */
        _scope = null;
        /** Subject of the JWT  */
        _sub = null;

        /** Credentials used to access protected resources  */
        _accessToken = null;
        /** Access token death time  */
        _expiresAt = 0;

        /** Debug mode, enables/disables logs */
        _debug = false;

        /** Flag, whether to include HTTP response in user token callback */
        _includeResp = false;

        /**
        * Initializes JWT Client
        * @param {ProviderConfig} provider - a table with OAuth2 provider configuration 
        * @param {ClientParams}   user     - a table of client specific parameters
        * @param {ConfigSettings} settings - Optional, a table of settings for the JWT Client class
        */
        /**
        * @typedef {table} ProviderConfig  - a table with OAuth2 provider configuration
        * @property {string} [tokenHost]   - Required, the provider's token endpoint URI
        */
        /**
        * @typedef {table} ClientParams   - a table of client specific parameters
        * @property {string} [iss]        - Required, the JWT issuer
        * @property {string} [jwtSignKey] - Required, the JWT sign secret key
        * @property {string} [scope]      - Optional, the authorization scope, defualts to null
        * @property {string} [sub]        - Optional, the subject of the JWT, defaults to iss
        */
        /**
        * @typedef {table} ConfigSettings   - a table with class configuration settings
        * @property {boolean} [includeResp] - Optional, whether to include HTTP response in 
        *   TokenReadyCallback parameters, defaults to false
        * @property {boolean} [debug]       - Optional, whether to enable debug logging, defaults to false
        */
        constructor(provider, user, settings = {}) {
             if (!("tokenHost" in provider) ) {
                throw "Invalid Provider";
            }
            _tokenHost = provider.tokenHost;

             if (!("iss" in user)    ||
                 !("jwtSignKey" in user)) {
                throw "Invalid user config";
            }
            _iss = user.iss;
            _jwtSignKey = user.jwtSignKey;

            /** 
            * Mandatory field but GOOGLE skips it. From RFC 7523 docs - For client
            *   authentication, the subject MUST be the "client_id" of the OAuth client 
            */
            _sub = ("sub" in user) ? user.sub : _iss;

            /** 
            * From RFC 6749 docs - If the client omits the scope parameter when requesting
            *   authorization, the authorization server MUST either process the request using
            *   a pre-defined default value or fail the request indicating an invalid scope
            */
            if ("scope" in user) _scope = user.scope;

            if ("includeResp" in settings) _includeResp = settings.includeResp;
            if ("debug" in settings) _debug = settings.debug;
        }

        /**
        * Non-blocking way to retrieve access token, if access token is valid
        * 
        * @return {string/null} Access token or null if client is not authorized or 
        *   token is expired
        */
        function getValidAccessTokenOrNull() {
            return (isTokenValid()) ? _accessToken : null;
        }

        /**
        * Check if access token is valid
        * 
        * @return {boolean} if access token is valid
        */
        function isTokenValid() {
            return time() < _expiresAt;
        }

        /**
        * Starts access token acquisition procedure
        * 
        * @param {TokenReadyCallback} tokenReadyCallback - a function that is triggered   
        *   when the access token is aquired, takes 3 parameters. 
        */
        /**
        * The callback function that is triggered when an access token is aquired or an error 
        *   is encountered
        *
        * @callback TokenReadyCallback
        * @param {string/null} token - an access token, or null if an error was encountered
        * @param {string/null} error - null if no error was encountered or a string containing 
        *   a description of the error
        * @param {string/null} response - the http response, or null if no response body is available
        */
        function acquireAccessToken(tokenReadyCallback) {
            if (isTokenValid()) {
                // _triggerTokenReadyCb params: token, err, resp, cb
                _triggerTokenReadyCb(_accessToken, null, null, tokenReadyCallback);
                return;
            }

            local now = time();            
            local claimset = {
                "iss"   : _iss,
                "sub"   : _sub,
                "aud"   : _tokenHost,
                "exp"   : (now + OAUTH2_TOKEN_DEFAULT_TTL_SEC),
                "iat"   : now
            };
            if (_scope != null) claimset.scope <- _scope;

            local context = {
                "client": this,
                "userCallback": tokenReadyCallback
            };

            local header = _urlsafe(http.base64encode("{\"alg\":\"RS256\",\"typ\":\"JWT\"}"));
            local body = _urlsafe(http.base64encode(http.jsonencode(claimset)));
            local pvtKey = _decodePem(_jwtSignKey);

            if (pvtKey == null) {
                local err = "Error decoding JWT Sign Key";
                _log(err);
                // _triggerTokenReadyCb params: token, err, resp, cb
                _triggerTokenReadyCb(_accessToken, err, null, tokenReadyCallback);
                return;
            }

            crypto.sign(crypto.RSASSA_PKCS1_SHA256, header + "." + body, pvtKey,
                function(err, sig) {
                    if (err) {
                        _log(err);
                        // _triggerTokenReadyCb params: token, err, resp, cb
                        _triggerTokenReadyCb(_accessToken, err, null, tokenReadyCallback);
                        return;
                    }

                    local signature = _urlsafe(http.base64encode(sig));
                    local oauthreq = http.urlencode({
                        "grant_type" : OAUTH2_JWT_GRANT_TYPE,
                        "assertion"  : (header + "." + body + "." + signature)
                    });

                    _log("Making a request to the host: " + _tokenHost);
                    _log((header + "." + body + "." + signature));

                    // Post, get the token
                    local request = http.post(_tokenHost, {}, oauthreq);
                    _log("Sending token host request...");
                    request.sendasync(_doTokenCallback.bindenv(context));

                }.bindenv(this)
            );
        }

        // -------------------- PRIVATE METHODS -------------------- //

        // Helper, triggers token ready callback with or without HTTP response depending 
        // on settings
        function _triggerTokenReadyCb(token, err, httpResp, cb) {
            if (_includeResp) {
                cb(token, err, httpResp);
            } else {
                cb(token, err);
            }
        }

        // Processes response from OAuth provider
        // Parameters:
        //          resp  - httpresponse instance
        //
        // Returns: Nothing
        function _doTokenCallback(resp) {
            if (resp.statuscode == 200) {
                try {
                    // Cache the new token, pull in the expiry a little just in case
                    local response = http.jsondecode(resp.body);
                    local err = client._extractToken(response);
                    client._triggerTokenReadyCb(client._accessToken, err, resp, userCallback);
                } catch(e) {
                    local err = "Error parsing http response: " + e;
                    client._triggerTokenReadyCb(null, err, resp, userCallback);
                }
            } else {
                // Error getting token
                local err = "Error getting token: " + resp.statuscode + " " + resp.body;
                client._log(err);
                client._triggerTokenReadyCb(null, err, resp, userCallback);
            }
        }

        // Remove the armor, concatenate the lines, and base64 decode the text.
        function _decodePem(str) {
            local lines = split(str, "\n");
            // We really ought to iterate over the array until we find a starting line,
            // and then look for the matching ending line.
            if ((lines[0] == "-----BEGIN PRIVATE KEY-----"
                    && lines[lines.len() - 1] == "-----END PRIVATE KEY-----") ||
                (lines[0] == "-----BEGIN RSA PRIVATE KEY-----"
                    && lines[lines.len() - 1] == "-----END RSA PRIVATE KEY-----") ||
                (lines[0] == "-----BEGIN PUBLIC KEY-----"
                    && lines[lines.len() - 1] == "-----END PUBLIC KEY-----"))
            {
                local all = lines.slice(1, lines.len() - 1).reduce(@(a, b) a + b);
                return http.base64decode(all);
            }
            return null;
        }

        // Extracts data from  token request response
        // Parameters:
        //      respData    - a table parsed from http response body
        //
        // Returns:
        //      error description if the table doesn't contain required keys,
        //      Null otherwise
        function _extractToken(respData) {
            if (!("access_token"  in respData)) {
                return "Response doesn't contain all required data";
            }

            local now = time();
            _accessToken = respData.access_token;
            _expiresAt = ("expires_in" in respData) ? respData.expires_in + now : OAUTH2_TOKEN_DEFAULT_TTL_SEC + now;

            return null;
        }


        // Make already base64 encoded string URL safe
        function _urlsafe(s) {
            // Replace "+" with "-" and "/" with "_"
            while(1) {
                local p = s.find("+");
                if (p == null) break;
                s = s.slice(0,p) + "-" + s.slice(p+1);
            }
            while(1) {
                local p = s.find("/");
                if (p == null) break;
                s = s.slice(0,p) + "_" + s.slice(p+1);
            }
            return s;
        }

        // Records non-error event
        function _log(message) {
            if (_debug) {
                server.log("[OAuth2JWTProfile] " + message);
            }
        }

    }
}

/**
 * OAuth 2.0 sub-class that provides authorization flow for browserless and 
 *  input constrained devices. 
 *  https://tools.ietf.org/html/draft-ietf-oauth-device-flow-05
 *
 * @class
 */
class OAuth2.DeviceFlow {

    // Predefined configuration for Google Authorization service
    // NOTE: Removing would be a breaking change, however these should not live
    // in this library.
    GOOGLE =  {
        "loginHost" : "https://accounts.google.com/o/oauth2/device/code",
        "tokenHost" : "https://www.googleapis.com/oauth2/v4/token",
        "grantType" : "http://oauth.net/grant_type/device/1.0",
    };

    /**
    * OAuth 2.0 sub-class that provides OAuth 2.0 Device Flow Client role. 
    *
    * @class
    */
    Client = class  {

        /** Current number of issued token */
        _currentTokenId  = 0;
        /** The verification URI on the authorization server */
        _verificationUrl = null;
        /** The user verification code */
        _userCode        = null;
        /** The device verification code */
        _deviceCode      = null;
        /** Credentials used to access protected resources */
        _accessToken     = null;
        /** Credentials used to obtain access tokens */
        _refreshToken    = null;
        /** Interval between polling requests to the token endpoint */
        _pollTime        = OAUTH2_DEFAULT_POLL_TIME_SEC;
        /** Access token death time */
        _expiresAt       = 0;
        /** Timer used for polling requests */
        _pollTimer       = null;

        /** Status of a Client */
        _status          = Oauth2DeviceFlowState.IDLE;

        /** Client password */
        _clientSecret    = null;
        /** 
        * The client identifier.
        *   https://tools.ietf.org/html/rfc6749#section-2.2
        */
        _clientId        = null;
        /** 
        * The scope of the access
        *   https://tools.ietf.org/html/rfc6749#section-3.3
        */
        _scope           = null;
        /**
        * Used to store additional key/value pairs used in the HTTP request 
        * to retrieve a device authorization code (mainly for Salesforce compatibility)
        */
        _addReqCodeData  = null;
        /** Boolean if raw HTTP response should be passed to get token callback 
        * (mainly for Salesforce compatibility)
        */
        _includeResp     = null;

        /** OAuth2 provider's device authorization endpoint */
        _loginHost       = null;
        /** OAuth2 provider's token endpoint */
        _tokenHost       = null;
        /** OAuth2 grant type */
        _grantType       = null;

        /** Debug mode, records non-error events */
        _debug          = true;

        /**
        * Initializes Device Client
        * @param {ProviderConfig} provider - a table with OAuth2 provider configuration 
        * @param {ClientParams}   user     - a table of client specific parameters
        * @param {ConfigSettings} settings - Optional, a table of settings for the Device Client class
        */
        /**
        * @typedef {table} ProviderConfig  - a table with OAuth2 provider configuration
        * @property {string} [loginHost]   - Required, the provider's device authorization endpoint URI
        * @property {string} [tokenHost]   - Required, the provider's token endpoint URI
        * @property {string} [grantType]   - Optional, grant type
        */
        /**
        * @typedef {table} ClientParams     - a table with OAuth2 provider configuration
        * @property {string} [clientId]     - Required, client identifier
        * @property {string} [scope]        - Optional, the authorization scope, defualts to null
        * @property {string} [clientSecret] - Optional, client secret (password)
        */
        /**
        * @typedef {table} ConfigSettings   - a table with class configuration settings
        * @property {boolean} [includeResp] - Optional, whether to include HTTP response in 
        *   TokenReadyCallback parameters, defaults to false
        * @property {boolean} [debug]       - Optional, whether to enable debug logging, defaults to true
        */
        constructor(provider, params, settings = {}) {
            if ( !("loginHost" in provider) ||
                 !("tokenHost" in provider) ) {
                     throw "Invalid Provider";
            }
            _loginHost = provider.loginHost;
            _tokenHost = provider.tokenHost;
            _grantType = ("grantType" in provider) ? provider.grantType : OAUTH2_DEVICE_FLOW_GRANT_TYPE;

            if (!("clientId" in params)) {
                throw "Invalid Config";
            }
            _clientId = params.clientId;
            /** 
            * From RFC 6749 docs - If the client omits the scope parameter when requesting
            *   authorization, the authorization server MUST either process the request using
            *   a pre-defined default value or fail the request indicating an invalid scope
            */
            if ("scope" in params) _scope = params.scope;
            /** Not mandatory by RFE */
            if ("clientSecret" in params) _clientSecret = params.clientSecret;

            if ("includeResp" in settings) _includeResp = settings.includeResp;
            if ("enableLogs" in settings) _debug = settings.enableLogs;
            if ("addReqCodeData" in settings) _addReqCodeData = settings.addReqCodeData;
        };

        /**
        * Non-blocking way to retrieve access token, if token is authorized and valid
        * 
        * @return {string/null} Access token or null if client is not authorized or 
        *   token is expired
        */
        function getValidAccessTokenOrNull() {
            return (isAuthorized() && isTokenValid()) ? _accessToken : null;
        }

        /**
        * Check if access token is valid
        * 
        * @return {boolean} if access token is valid
        */
        function isTokenValid() {
            return time() < _expiresAt;
        }

        /**
        * Check if access token is authorized and able to refresh expired access token
        * 
        * @return {boolean} if access token is authorized
        */
        function isAuthorized() {
            return _refreshToken != null;
        }

        /**
        * Starts access token acquisition procedure. Depending on Client state may start
        * full client authorization procedure or just a token refresh
        * 
        * @param {TokenReadyCallback} tokenReadyCallback - a function that is triggered   
        *   when the access token is aquired or on error, takes 3 parameters. 
        * @param {NotifyUserCallback} notifyUserCallback - a function that is triggered   
        *   when user action is required, takes 2 parameters. 
        *
        * @param {boolean} - force, Optional, whether to start new acquisition procedure even if 
        *   previous request is not complete. Defaults to false.
        *
        * @return {string/null} - Null if no error was encountered, otherwise a string with 
        *   a description of the error (ie an authorization is already in progress, and force 
        *   flag is set to false)
        */
        /**
        * The callback function that is triggered when an access token is aquired or an error 
        *   is encountered. 
        *
        * @callback TokenReadyCallback
        * @param {string/null} token - an access token, or null if an error was encountered
        * @param {string/null} error - null if no error was encountered or a string containing 
        *   a description of the error
        * @param {string/null} response - the http response, or null if no response body is available
        */
        /**
        * The callback function that is triggered when user action is required
        *   https://tools.ietf.org/html/draft-ietf-oauth-device-flow-05#section-3.3
        *
        * @callback NotifyUserCallback
        * @param {string} verification_uri - the URI the user will need for client authorization
        * @param {string} user_code - the code the user will need to enter that will be sent to the
        *   authorization server. 
        */
        function acquireAccessToken(tokenReadyCallback, notifyUserCallback, force = false) {
            if (_isBusy() && !force) return "Token request is ongoing";

            if (isAuthorized()) {
                if (isTokenValid()) {
                    _triggerTokenReadyCb(_accessToken, null, null, tokenReadyCallback);
                    return null;
                } else {
                    return refreshAccessToken(tokenReadyCallback);
                }
            } else {
                return _requestCode(tokenReadyCallback, notifyUserCallback);
            }
        }

        /**
        * Starts refresh token procedure.
        * 
        * @param {TokenReadyCallback} cb - a function that is triggered   
        *   when the access token is aquired or on error, takes 3 parameters. 
        *
        * @return {string/null} - Null if no error was encountered, otherwise a string with 
        *   a description of the error
        */
        /**
        * The callback function that is triggered when an access token is aquired or an error 
        *   is encountered. 
        *
        * @callback TokenReadyCallback
        * @param {string/null} token - an access token, or null if an error was encountered
        * @param {string/null} error - null if no error was encountered or a string containing 
        *   a description of the error
        * @param {string/null} response - the http response, or null if no response body is available
        */
        function refreshAccessToken(cb) {
             if (!isAuthorized()) {
                 return "Unauthorized";
             }

             if (_isBusy()) {
                 _log("Resetting ongoing session with token id: " + _currentTokenId);
                 // incrementing the token # to cancel the previous one
                 _currentTokenId++;
             }

            local data = {
                "client_secret" : _clientSecret,
                "client_id"     : _clientId,
                "refresh_token" : _refreshToken,
                "grant_type"    : "refresh_token",
            };

            _doPostWithHttpCallback(_tokenHost, data, _doRefreshTokenCallback, [cb]);
            _changeStatus(Oauth2DeviceFlowState.REFRESH_TOKEN);

            return null;
        }


        // -------------------- PRIVATE METHODS -------------------- //

        // Helper, triggers token ready callback with or without HTTP response depending 
        // on settings
        function _triggerTokenReadyCb(token, err, httpResp, cb, reset = false, msg = null) {
            if (reset) _reset();
            local errMsg = (msg != null) ? msg + err : err;
            if (errMsg) _log(errMsg);
            if (_includeResp) {
                cb(token, err, httpResp);
            } else {
                cb(token, err);
            }
        }

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

            local data = (_addReqCodeData != null) ? _addReqCodeData : {};
            data.client_id <- _clientId;
            if (_scope != null) data.scope <- _scope;

            // NOTE: sf lib needs to add "response_type" to data with _grantType value

            _doPostWithHttpCallback(_loginHost, data, _requestCodeCallback,
                                    [tokenCallback, notifyUserCallback]);
            _changeStatus(Oauth2DeviceFlowState.REQUEST_CODE);

            return null;
        }

        // Device Authorization Response handler.
        // Parameters:
        //          resp                - httpresponse object
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
        // Returns: Nothing
        function _requestCodeCallback(resp, cb, notifyUserCallback) {
            try {
                local respData = http.jsondecode(resp.body);

                if (_extractPollData(respData) != null) {
                    // No URL/Code, response from server did not included required 
                    // info for user to authenticate device

                    // params: token, err, http resp, cb, reset, additional err log msg
                    _triggerTokenReadyCb(null, resp.body, null, cb, true, "Something went wrong during code request: ");
                    return;
                }
                _changeStatus(Oauth2DeviceFlowState.WAIT_USER);

                if (notifyUserCallback) notifyUserCallback(_verificationUrl, _userCode);
                _schedulePoll(cb);
            } catch (e) {
                // params: token, err, http resp, cb, reset, additional err log msg
                _triggerTokenReadyCb(null, "Provider data processing error: " + e, resp, cb, true);
            }
        }

        // Token refresh response handler
        // Parameters:
        //          resp  - httpresponse object
        //          cb    - The handler to be called when access token is acquired
        //                  or error is observed. The handle's signature:
        //                     tokenReadyCallback(token, error), where
        //                          token   - access token string
        //                          error   - error description string
        // Returns: Nothing
        function _doRefreshTokenCallback(resp, cb) {
            try {
                _changeStatus(Oauth2DeviceFlowState.IDLE);
                local respData = http.jsondecode(resp.body);

                if (_extractToken(respData) != null) {
                    // Server response did not include a token
                    // params: token, err, http resp, cb, reset, additional err log msg
                    _triggerTokenReadyCb(null, resp.body, resp, cb, true, "Something went wrong during refresh: ");
                } else {
                    _triggerTokenReadyCb(_accessToken, null, resp, cb);
                }
            } catch (e) {
                // params: token, err, http resp, cb, reset, additional err log msg
                _triggerTokenReadyCb(null, "Token refreshing error: " + e, resp, cb, true);
            }
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
            // Did user call _poll() directly
            if (_status != Oauth2DeviceFlowState.WAIT_USER) {
                return "Invalid status. Do not call _poll directly";
            }

            if (time() > _expiresAt) {
                // params: token, err, http resp, cb, reset, additional err log msg
                _triggerTokenReadyCb(null, "Token acquiring timeout", null, cb, true);
                return err;
            }

            local data = {
                "client_id"     : _clientId,
                "code"          : _deviceCode,
                "grant_type"    : _grantType,
            };
            if (_clientSecret != null)  data.client_secret <- _clientSecret;

            // NOTE: SF grant type is "device"

            _doPostWithHttpCallback(_tokenHost, data, _doPollCallback, [cb]);
        }

        // Handles Device Access Token Response.
        //          resp  - httpresponse object
        //          cb    - The handler to be called when access token is acquired
        //                  or error is observed. The handle's signature:
        //                     tokenReadyCallback(token, error), where
        //                        token   - access token string
        //                        error   - error description string
        // Returns:
        //      error description if Client doesn't wait device authorization from the user
        //                        or if time to wait for user action has expired,
        //      Null otherwise
        function _doPollCallback(resp, cb) {
            try {
                local respData = http.jsondecode(resp.body);
                local statusCode = resp.statuscode;

                if (statusCode == 200) {
                    if (_extractToken(respData) == null) {
                        _log("Polling success");
                        _changeStatus(Oauth2DeviceFlowState.IDLE);
                        // release memory
                        _cleanUp(false);
                        // params: token, err, http resp, cb, reset, additional err log msg
                        _triggerTokenReadyCb(_accessToken, null, resp, cb);
                    } else {
                        // params: token, err, http resp, cb, reset, additional err log msg
                        _triggerTokenReadyCb(null, "Invalid server response: " + respData.body, resp, cb, true);
                    }
                } else if ( (statusCode/100) == 4) {
                    local err = respData.error;
                    if (err == "authorization_pending") {
                        _log("Polling: " + err);
                        _schedulePoll(cb);
                    } else if (err == "slow_down") {
                        _log("Polling error: " + err);
                        _pollTime *= 2;
                        imp.wakeup(_pollTime, _poll.bindenv(this));
                    } else {
                        // All other errors pass to application
                        // params: token, err, http resp, cb, reset, additional err log msg
                        _triggerTokenReadyCb(null, "Polling error: " + err, resp, cb, true);
                    }
                } else {
                    // params: token, err, http resp, cb, reset, additional err log msg
                    _triggerTokenReadyCb(null, "Unexpected server response code: " + statusCode, resp, cb, true);
                }
            } catch (e) {
                // params: token, err, http resp, cb, reset, additional err log msg
                _triggerTokenReadyCb(null, "General server poll error: " + e, resp, cb, true);
            }
        }

        // Makes POST to given URL with provided body.
        // Parameters:
        //          url             - resource URL
        //          data            - request body
        //          callback        - The handler to process HTTP response
        //          callbackArgs    - additional arguments to the handler
        function _doPostWithHttpCallback(url, data, callback, callbackArgs) {
            local body = http.urlencode(data);
            local context = {
                "client" : this,
                "func"   : callback,
                "args"   : callbackArgs,
                "cnt"    : _currentTokenId
            };
            http.post(url, {}, body).sendasync(_doHttpCallback.bindenv(context));
        }

        // HTTP response intermediate handler.
        // Drops response if there is newest pending request.
        //
        // Parameters:
        //         resp -   httpresponse object
        //
        // Returns: Nothing
        function _doHttpCallback(resp) {
            if (cnt != client._currentTokenId) {
                client._log("Canceled session " + cnt);
                return;
            }
            local allArgs = [client, resp];
            allArgs.extend(args);
            func.acall(allArgs);
        }

        // Schedules next token request.
        // Parameters is the same as for _poll function
        function _schedulePoll(cb) {
            local cnt = _currentTokenId;
            local client = this;
            imp.wakeup(_pollTime, function() {
                if (cnt != client._currentTokenId) {
                    client._log("Canceled session " + cnt);
                    return;
                }
                client._poll(cb);
            });
        }

        // Extracts data from  Device Authorization Response
        // Parameters:
        //      respData    - a table parsed from http response body
        //
        // Returns:
        //      error description if the table doesn't contain required keys,
        //      Null otherwise
        function _extractPollData(respData) {
            // NOTE: Accept either url or uri for verification 
            local url = null;
            if ("verification_url" in respData) url = respData.verification_url;
            if ("verification_uri" in respData) url = respData.verification_uri;

            if (url == null ||
                !("user_code" in respData) ||
                !("device_code" in respData)) {
                    return "Response doesn't contain all required data";
            }
            _verificationUrl = url;
            _userCode        = respData.user_code;
            _deviceCode      = respData.device_code;

            local now = time();
            if ("interval" in respData) _pollTime = respData.interval;
            _expiresAt = ("expires_in" in respData) ? respData.expires_in + now : now + OAUTH2_DEFAULT_POLL_TIME_SEC;
            
            return null;
        }

        // Extracts data from  token request response
        // Parameters:
        //      respData    - a table parsed from http response body
        //
        // Returns:
        //      error description if the table doesn't contain required keys,
        //      Null otherwise
        function _extractToken(respData) {
            if (!("access_token" in respData)) {
                return "Response doesn't contain all required data";
            }

            local now = time();
            _accessToken = respData.access_token;
            // There is no refresh_token after token refresh
            if ("refresh_token" in respData) _refreshToken = respData.refresh_token;
            _expiresAt = ("expires_in" in respData) ? respData.expires_in + now : now + OAUTH2_TOKEN_DEFAULT_TTL_SEC;

            return null;
        }

        // Checks if Client performs token request procedure
        function _isBusy() {
            return (_status != Oauth2DeviceFlowState.IDLE);
        }

        // Resets Client state
        function _reset() {
            _cleanUp();
            _changeStatus(Oauth2DeviceFlowState.IDLE);
        }

        // Changes Client status
        function _changeStatus(newStatus) {
            _log("Change status of session " + _currentTokenId + " from " + _getStringStatus(_status) + " to " + _getStringStatus(newStatus));
            _status = newStatus;
        }

        // Turns Oauth2DeviceFlowState enum value into readable string
        function _getStringStatus(status) {
            switch (status) {
                case Oauth2DeviceFlowState.IDLE:
                    return "idle";
                case Oauth2DeviceFlowState.REQUEST_CODE:
                    return "requesting code";
                case Oauth2DeviceFlowState.WAIT_USER:
                    return "waiting for user";                
                case Oauth2DeviceFlowState.REFRESH_TOKEN:
                    return "token refreshed";
            }
        }

        // Clears client variables.
        // Parameters:
        //              full  - the directive to reset client to initial state.
        //                      Set to False if token information should be preserved.
        //  Returns:    Nothing
        function _cleanUp(full = true) {
            _verificationUrl = null;
            _userCode        = null;
            _deviceCode      = null;
            _pollTime        = OAUTH2_DEFAULT_POLL_TIME_SEC;
            _pollTimer       = null;

            if (full) {
                _expiresAt       = null;
                _refreshToken    = null;
                _accessToken     = null;
            }
        }

        // Records non-error event
        function _log(txt) {
            if (_debug) {
                server.log("[OAuth2DeviceFlow] " + txt);
            }
        }
    } // end of Client
}

// End Updated OAuth2 Library v2.1.0
// -----------------------------------------------------------------------