// -// The class that represents OAuth 2.0 authorization flow
//  // for browserless and input constrained devices.
//  // https://tools.ietf.org/html/draft-ietf-oauth-device-flow-05
//  class OAuth2.DeviceFlow {
// @@ -483,6 +278,7 @@
//              local data = {
//                  "scope": _scope,
//                  "client_id": _clientId,
// +                "response_type": _grantType
//              };
 
//              _doPostWithHttpCallback(_loginHost, data, _requestCodeCallback,
// @@ -587,7 +383,7 @@
//              local data = {
//                  "client_id"     : _clientId,
//                  "code"          : _deviceCode,
// -                "grant_type"    : _grantType,
// +                "grant_type"    : "device",
//              };
 
//              if (null != _clientSecret)  data.client_secret <- _clientSecret;
// @@ -662,6 +458,7 @@
//          //          callbackArgs    - additional arguments to the handler
//          function _doPostWithHttpCallback(url, data, callback, callbackArgs) {
//              local body = http.urlencode(data);
// +            print(body);
//              local context = {
//                  "client" : this,
//                  "func"   : callback,
// @@ -710,12 +507,12 @@
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
 
// @@ -799,4 +596,44 @@
//              }
//          }
//      } // end of Client
// -}
// \ No newline at end of file
// +}
// +
// +// Fill CLIENT_ID and CLIENT_SECRET with correct values
// +local userConfig = { "clientId"     : ",
// +                     "clientSecret" : "",
// +                     "scope"        : "api refresh_token"
// +};
// +                     
// +local providerConfig = { "loginHost" : "https://test.salesforce.com/services/oauth2/token",
// +                         "tokenHost" : "https://test.salesforce.com/services/oauth2/token",
// +                         "grantType" : "device_code"
// +};
// +
// +// Initialize client with provided Google Firebase config
// +client <- OAuth2.DeviceFlow.Client(providerConfig, userConfig);
// +
// +local token = client.getValidAccessTokenOrNull();
// +
// +if (token != null) {
// +    server.log("Valid access token is: " + token);
// +} else {
// +    // Acquire a new access token
// +    local error = client.acquireAccessToken(
// +    // Token received callback function
// +    function(response, error) {
// +        if (error) {
// +            server.error("Token acquisition error: " + error);
// +        } else {
// +            server.log("Received token: " + response);
// +        }
// +    },
// +    // User notification callback function
// +    function(url, code) {
// +        server.log("Authorization is pending. Please grant access");
// +        server.log("URL: " + url);
// +        server.log("Code: " + code);
// +    }
// +    );
// +
// +    if (error != null) server.error("Client is already performing request (" + error + ")");
// +}