// -----------------------------------------------------------------------
// Losant Cloud Service File
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

// Use this to show a dashboard/verify device application is working as intended
class LosantTracker {
    lsntApp        = null;
    lsntDeviceId   = null;
    impDeviceId    = null;
    agentId        = null;

    function __statics__() {
        // API Token for Losant application
        const LOSANT_API_TOKEN        = "@{LOSANT_API_TOKEN}";
        const LOSANT_APPLICATION_ID   = "@{LOSANT_APPLICATION_ID}";
        const DEVICE_NAME_TEMPLATE    = "Tracker_%s";
        const DEVICE_DESCRIPTION      = "Electric Imp Device";
        const LOSANT_DEVICE_CLASS     = "standalone";
    }

    constructor() {
        agentId = split(http.agenturl(), "/").top();
        impDeviceId = imp.configparams.deviceid;

        lsntApp = Losant(LOSANT_APPLICATION_ID, LOSANT_API_TOKEN);
        // Check if device with this agent and device id combo exists, create if need
        ::debug("[Losant] Check Losant app for devices with matching tags.");
        _getLosantDeviceId();
    }

    function sendData(data) {
        // Check that we have a Losant device configured
        if (lsntDeviceId == null) {
            ::debug("[Losant] Losant device not configured. Not sending data: ");
            ::debug(http.jsonencode(data));
            return;
        }

        local payload = {
            "time" : lsntApp.createIsoTimeStamp(),
            "data" : {}
        };

        // Make sure data sent matches the attribute name
        if ("temp" in data) payload.data.temperature <- data.temp;
        if ("humid" in data) payload.data.humidity <- data.humid;
        if ("lat" in data && "lng" in data) payload.data.location <- format("%s,%s", data.lat, data.lng);
        if ("dist" in data) payload.data.distance <- data.dist; 
        if ("fix" in data && "accuracy" in data.fix) payload.data.fixaccuracy <- data.fix.accuracy; 

        ::debug("[Losant] Sending device state to Losant:");
        ::debug(http.jsonencode(payload));
        lsntApp.sendDeviceState(lsntDeviceId, payload, _sendDeviceStateHandler.bindenv(this));
    }

    function updateDevice(newAttributes, newTags = null) {
        if (lsntDeviceId != null) {
            if (newTags == null) newTags = _createTags();
            local deviceInfo = {
                "name"        : format(DEVICE_NAME_TEMPLATE, agentId),
                "description" : DEVICE_DESCRIPTION,
                "deviceClass" : LOSANT_DEVICE_CLASS,
                "tags"        : newTags,
                "attributes"  : newAttributes
            }
            ::debug("[Losant] Losant: Updating device.");
            lsntApp.updateDeviceInfo(lsntDeviceId, deviceInfo, function(res) {
                ::debug("[Losant] Losant: Update device status code: " + res.statuscode);
                ::debug(res.body);
            }.bindenv(this))
        } else {
            ::debug("[Losant] Losant device id not retrieved yet. Try again.");
        }
    }

    function _getLosantDeviceId() {
        // Create filter for tags matching this device info,
        // Tags for this app are unique combo of agent and imp device id
        local qparams = lsntApp.createTagFilterQueryParams(_createTags());

        // Check if a device with matching unique tags exists, create one
        // and store losant device id.
        lsntApp.getDevices(_getDevicesHandler.bindenv(this), qparams);
    }

    function _createDevice() {
        // This should be done with caution, it is possible to create multiple devices
        // Each device will be given a unique Losant device id, but will have same agent
        // and imp device ids

        // Only create if we do not have a Losant device id
        if (lsntDeviceId == null) {
            local deviceInfo = {
                "name"        : format(DEVICE_NAME_TEMPLATE, agentId),
                "description" : DEVICE_DESCRIPTION,
                "deviceClass" : LOSANT_DEVICE_CLASS,
                "tags"        : _createTags(),
                "attributes"  : _createAttrs()
            }
            ::debug("[Losant] Losant: Creating new device.");
            lsntApp.createDevice(deviceInfo, _createDeviceHandler.bindenv(this))
        }
    }

    function _sendDeviceStateHandler(res) {
        // Log only if not successfull
        if (res.statuscode != 200) {
            ::debug(res.statuscode);
            ::debug(res.body);
        }
    }

    function _createDeviceHandler(res) {
        // server.log(res.statuscode);
        // server.log(res.body);
        local body = http.jsondecode(res.body);
        ::debug("[Losant] Losant:  Device created.");
        if ("deviceId" in body) {
            lsntDeviceId = body.deviceId;
        } else {
            ::error("[Losant] Losant device id not found.");
            ::debug(res.body);
        }
    }

    function _getDevicesHandler(res) {
        // server.log(res.statuscode);
        // server.log(res.body);
        local body = http.jsondecode(res.body);

        if (res.statuscode == 200 && "count" in body) {
            // Successful request
            switch (body.count) {
                case 0:
                    // No devices found, create device
                    ::debug("[Losant] Losant: Device not found.");
                    _createDevice();
                    break;
                case 1:
                    // We found the device, store the losDevId
                    ::debug("[Losant] Losant: Device with matching tags found.");
                    if ("items" in body && "deviceId" in body.items[0]) {
                        lsntDeviceId = body.items[0].deviceId;
                        // Make sure the attributes and tags in Losant
                        // match the current code.
                        updateDevice(_createAttrs, _createTags);
                    } else {
                        ::error("[Losant] Losant device id not in payload.");
                        ::debug(res.body);
                    }
                    break;
                default:
                    // Log results of filtered query
                    ::error("[Losant] Losant: Found " + body.count + "devices matching the device tags.");

                    // TODO: Delete duplicate devices - look into how to determine which device
                    // is active, so data isn't lost
            }
        } else {
            ::error("[Losant] Losant: List device request failed with status code: " + res.statuscode);
        }
    }

    function _createTags() {
        return [
            {
                "key"   : "agentId",
                "value" : agentId
            },
            {
                "key"   : "impDevId",
                "value" : impDeviceId
            },
        ]
    }

    function _createAttrs() {
        return [
            {
                "name"     : "temperature",
                "dataType" : "number"
            },
            {
                "name"     : "humidity",
                "dataType" : "number"
            }, 
            {
                "name"     : "location",
                "dataType" : "gps"
            },
            {
                "name"     : "distance",
                "dataType" : "number"
            },
            {
                "name"     : "fixaccuracy",
                "dataType" : "number"
            }
        ];
    }
}

// End Losant Cloud Service File
// -----------------------------------------------------------------------