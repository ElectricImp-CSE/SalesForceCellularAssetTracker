// -----------------------------------------------------------------------
// Location Assistance File 
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

// Token is stored in /settings/imp.config file
const UBLOX_ASSISTNOW_TOKEN = "@{UBLOX_ASSISTNOW_TOKEN}";

// Manages u-blox Assist Now Logic
// Dependencies: UBloxAssistNow(agent) Library
// Initializes: UBloxAssistNow(agent) Library
class Location {
    
    assist = null;

    constructor() {
        assist = UBloxAssistNow(UBLOX_ASSISTNOW_TOKEN);
    }

    function getOnlineAssist(onResp) {
        local assistOnlineParams = {
            "gnss"     : ["gps", "glo"],
            "datatype" : ["eph", "alm", "aux"]
        };

        assist.requestOnline(assistOnlineParams, function(err, resp) {
            local assistData = null;
            if (err != null) {
                ::error("[Location] Online req error: " + err);
            } else {
                ::debug("[Location] Received AssistNow Online. Data length: " + resp.body.len());
                assistData = resp.body;
            }
            onResp(assistData);
        }.bindenv(this));
    }

    function getOfflineAssist(onResp) {
        local assistOfflineParams = {
            "gnss"   : ["gps", "glo"],
            "period" : 1,               // Num of weeks 1-5
            "days"   : 3
        };

        // Data is updated 1-2X a day
        assist.requestOffline(assistOfflineParams, function(err, resp) {
            local assistData = null;
            if (err != null) {
                ::error("[Location] Offline req error: " + err);
            } else {
                ::debug("[Location] Received AssistNow Offline. Raw data length: " + resp.body.len());
                ::debug("[Location] Parsing AssistNow Offline messages by date.");
                assistData = assist.getOfflineMsgByDate(resp);
                // Log Data Lengths
                foreach(day, data in assistData) {
                    ::debug(format("[Location] Offline assist for %s len %d", day, data.len()));
                }
            }
            onResp(assistData);
        }.bindenv(this))
    }

}

// End Location Assistance File
// -----------------------------------------------------------------------