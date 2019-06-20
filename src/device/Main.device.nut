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

// Device Main Application File

// Libraries
#require "SPIFlashFileSystem.device.lib.nut:2.0.0"
#require "ConnectionManager.lib.nut:3.1.1"
#require "MessageManager.lib.nut:2.4.0"
#require "Promise.lib.nut:4.0.0"
// Location/GPS Libraries
#require "UBloxM8N.device.lib.nut:1.0.1"
#require "UbxMsgParser.lib.nut:2.0.0"
#require "UBloxAssistNow.device.lib.nut:0.1.0"
// Battery Charger/Fuel Gauge Libraries
#require "MAX17055.device.lib.nut:1.0.1"
#require "BQ25895.device.lib.nut:2.0.0"
// Env Sensor Libraries
#require "HTS221.device.lib.nut:2.0.1"
// #require "LIS3DH.device.lib.nut:2.0.2"

// Supporting files
// NOTE: Order of files matters do NOT change unless you know how it will effect 
// the application
@include __PATH__ + "/Hardware.device.nut"
@include __PATH__ + "/../shared/Logger.shared.nut"
@include __PATH__ + "/../shared/Constants.shared.nut"
@include __PATH__ + "/Persist.device.nut"
@include __PATH__ + "/Location.device.nut"
@include __PATH__ + "/Env.device.nut"
@include __PATH__ + "/Battery.device.nut"

// Main Application
// -----------------------------------------------------------------------

// NOTE: These timings have an impact on battery life. Current setting are not 
// battery efficient. 
// Wake every x seconds to check if report should be sent (location changed, etc)
const CHECK_IN_TIME_SEC      = 30; // 20
// Wake every x seconds to send a report, regaurdless of check results
const REPORT_TIME_SEC        = 300; // 300; 

// Accuracy of GPS fix in meters
const LOCATION_ACCURACY      = 10;
const LOCATION_TIMEOUT_SEC   = 70; 
const OFFLINE_ASSIST_REQ_MAX = 43200; // Limit requests to every 12h (12 * 60 * 60) 
// Constant used to validate imp's timestamp (must be a year greater than 2000)
const VALID_TS_YEAR          = 2019;
// Low battery alert threshold in percentage
const BATTERY_LOW_THRESH     = 10;
// Distance threshold in meters
const DISTANCE_THRESHOLD_M   = 20;

class MainController {

    // Class instances
    cm         = null;
    mm         = null;
    loc        = null;
    persist    = null;

    // Variables
    report     = null;
    storeToSpi = null; 

    constructor() {
        // Initialize ConnectionManager Library - this sets the connection policy, so divice can
        // run offline code. The connection policy should be one of the first things set when the
        // code starts running.
        // TODO: In production update CM_BLINK to NEVER to conserve battery power
        // TODO: Look into setting connection timeout (currently using default of 60s)
        cm = ConnectionManager({ 
            "blinkupBehavior" : CM_BLINK_ALWAYS, 
            "retryOnTimeout"  : false
        });
        imp.setsendbuffersize(8096);

        // Initialize Logger
        Logger.init(LOG_LEVEL.DEBUG, cm);

        ::debug("--------------------------------------------------------------------------");
        ::debug("Device started...");
        ::debug(imp.getsoftwareversion());
        ::debug("--------------------------------------------------------------------------");
        PWR_GATE_EN.configure(DIGITAL_OUT, 0);

        // Initialize storage class
        persist = Persist();
        // NOTE: If we do not plan to sleep this can be set to true or the variable can be dropped
        storeToSpi = false;

        // Initialize Message Manager for agent/device communication
        mm = MessageManager({"connectionManager" : cm});
        mm.onTimeout(mmOnTimeout.bindenv(this));

        // Start application
        onBoot();
    }

    // MM handlers
    // -------------------------------------------------------------

    // Global MM Timeout handler
    function mmOnTimeout(msg, wait, fail) {
        ::debug("MM message timed out");
        fail();
    }

    // MM onFail handler for report
    function mmOnReportFail(msg, err, retry) {
        ::error("Report send failed");
        // Don't reset reporting vars or reporting time
        // Try again at next check-in time
        scheduleNextCheckIn();
    }

    // MM onFail handler for assist messages
    function mmOnAssistFail(msg, err, retry) {
        ::error("Request for assist messages failed, retrying");
        retry();
    }

    // MM onAck handler for report
    function mmOnReportAck(msg) {
        // Report successfully sent
        ::debug("Report ACK received from agent");

        // Reset report & GPS table
        report = {};
        loc.clearGPSFix();

        updateReportingTime();
        scheduleNextCheckIn();
    }

    // MM onReply handler for assist messages
    function mmOnAssist(msg, response) {
        if (response == null) {
            ::debug("Didn't receive any Assist messages from agent.");
            return;
        }

        // Make sure location class is initialized
        if (loc == null) loc = Location(); 
        // Response contains assist messages from cloud
        local assistMsgs = response;

        if (msg.payload.data == ASSIST_TYPE.OFFLINE) {
            ::debug("Offline assist messages received from agent");
            // Get today's date string/file name
            local todayFileName = loc.getAssistDateFileName();

            // Store all offline assist messages by date
            persist.storeAssist(response);
            // Update time we last checked
            persist.setOfflineAssistChecked(time());

            // Select today's offline assist messages only
            if (todayFileName in response) {
                assistMsgs = response.todayFileName;
                ::debug("Writing offline assist messages to u-blox");
            } else {
                ::debug("No offline assist messges for today. No messages written to UBLOX.");
                return;
            }
        } else {
            ::debug("Online assist messages received from agent. Writing to u-blox");
        }

        // Write assist messages to UBLOX module
        loc.writeAssistMsgs(assistMsgs, onAssistMsgDone.bindenv(this));
    }

    // Connection & Connection Flow Handlers
    // -------------------------------------------------------------

    // Start application
    function onBoot() {
        // Set default report value
        report = {};
        // Set i2c clock rate
        SENSOR_I2C.configure(CLOCK_SPEED_400_KHZ);

        // Trigger async tasks
        // NOTE: getLocation() will initialize/re-initialize location class
        local tasks = [getLocation(), getBattStatus(), getTempHumid()];
        Promise.serial(tasks)
            .then(function(msg) {
                // Persist raw location data so we can determine location changes on next check-in
                if ("fix" in report && "lat" in report.fix && "lng" in report.fix) {
                    persist.setLocation(report.fix.lat, report.fix.lng, storeToSpi);
                }

                // NOTE: Report ack/timeout/fail handler(s) will schedule next check-in
                sendReport();
            }.bindenv(this));

        // Get assist messages
        // NOTE: Order matters, best to let getLocation() initialize location class first 
        reqOfflineAssist();
        reqOnlineAssist();
    }

    function onCheckIn() {
        ::debug("Starting check-in flow...");

        // Trigger async tasks
        // NOTE: getLocation() will initialize/re-initialize location class
        local tasks = [getLocation(), getBattStatus(), getTempHumid()];
        Promise.serial(tasks)
            .then(function(msg) {
                if (shouldReport()) {
                    // NOTE: Report ack/timeout/fail handler(s) will schedule next check-in
                    sendReport();
                } else {
                    scheduleNextCheckIn();
                }
            }.bindenv(this));

        // Get offline assist messages if needed
        // TODO: Move to connection flow if sleep/wake flow implemented.
        reqOfflineAssist();
        reqOnlineAssist();
    }

    function scheduleNextCheckIn() {
        ::debug("Scheduling next check-in: " + (time() + CHECK_IN_TIME_SEC));
        // TODO: update with power down/sleep logic to conserve battery
        imp.wakeup(CHECK_IN_TIME_SEC, onCheckIn.bindenv(this));
    }

    // Actions
    // -------------------------------------------------------------

    // Send a request to agent for offline assist messages if we haven't refreshed recently
    function reqOfflineAssist() {
        // Limit requests (Offline Assist data refreshes 1X-2X a day)
        if (shouldGetOfflineAssist() && cm.isConnected()) {
            // We don't have a fix, request assist online data
            ::debug("Requesting offline assist messages from agent/Assist Now.");
            local mmHandlers = {
                "onReply" : mmOnAssist.bindenv(this),
                "onFail"  : mmOnAssistFail.bindenv(this)
            };
            mm.send(MM_ASSIST, ASSIST_TYPE.OFFLINE, mmHandlers);
        }
        // TODO: Add async task to track when reply and write to Ublox are completed
    }

    // Send a request to agent for onlne assist messages
    function reqOnlineAssist() {
        if (cm.isConnected()) {
            // We don't have a fix, request assist online data
            ::debug("Requesting online assist messages from agent/Assist Now.");
            local mmHandlers = {
                "onReply" : mmOnAssist.bindenv(this),
                "onFail"  : mmOnAssistFail.bindenv(this)
            };
            mm.send(MM_ASSIST, ASSIST_TYPE.ONLINE, mmHandlers);
        }
    }

    // Create and send device status report to agent
    function sendReport() {
        // Add timestamp to report
        report.ts <- time();

        // Send to agent
        ::debug("Sending device status report to agent");
        local mmHandlers = {
            "onAck"  : mmOnReportAck.bindenv(this), 
            "onFail" : mmOnReportFail.bindenv(this)
        };
        mm.send(MM_REPORT, report, mmHandlers);
    }

    // Powers up GPS and starts location message filtering for accurate fix
    // Returns Promise when completed
    function getLocation() {
        return Promise(function(resolve, reject) {
            // Power up GPS
            PWR_GATE_EN.write(1);
            // Enable UBlox 
            // Note: If device wakes from sleep just initialize 
            // Location class, however if device continues to run
            // after PWR_GATE_EN disables GPS UBX uart needs to be 
            // reconfigured, so call init method to re-initialize UBLOX 
            // libs. 
            (loc == null) ? loc = Location() : loc.init();

            local locationTimer = null;

            loc.getLocation(LOCATION_ACCURACY, function(gpxFix) {
                ::debug("Got fix. Disabling GPS power");
                PWR_GATE_EN.write(0);

                // Cancel timeout timer
                if (locationTimer != null) imp.cancelwakeup(locationTimer);

                // Store fix data for report
                // NOTE: Keep both raw (so we can store easily to SPI) and formatted 
                // lat and lng (for reporting) 
                if ("lat" in gpxFix) report.lat <- UbxMsgParser.toDecimalDegreeString(gpxFix.lat);
                if ("lng" in gpxFix) report.lng <- UbxMsgParser.toDecimalDegreeString(gpxFix.lng);
                report.fix <- gpxFix;

                if ("lat" in report && "lng" in report) {
                    ::debug(format("GPS reading: Latitude %s, Longitude %s", report.lat, report.lng));
                }

                return resolve("GPS location done");
            }.bindenv(this));

            // Configure Location Timeout
            locationTimer = imp.wakeup(LOCATION_TIMEOUT_SEC, function() {
                ::debug("Location request timed out. Disabling GPS power");
                PWR_GATE_EN.write(0);

                // NOTE: Report will not include GPS location
                return resolve("GPS location request timed out");
            }.bindenv(this));
        }.bindenv(this))
    }

    // Initializes Battery monitor and gets battery status
    // Returns Promise when completed
    function getBattStatus() {
        return Promise(function(resolve, reject) {
            // Initialize Battery Monitor, don't configure i2c
            local battery = Battery(false);
            battery.getStatus(function(status) {
                ::debug("Get battery status complete:")
                ::debug("Remaining cell capacity: " + status.capacity + "mAh");
                ::debug("Percent of battery remaining: " + status.percent + "%");
                // Stores battery status for use in report
                report.battStatus <- status;
                return resolve("Battery status complete");
            }.bindenv(this));
        }.bindenv(this))
    }

    // Initializes Environmental Monitor and gets temperature and humidity
    // Returns Promise when completed
    function getTempHumid() {
        return Promise(function(resolve, reject) {
            // Initialize Environmental Monitor, don't configure i2c
            local env = Env(false);
            env.getTempHumid(function(reading) {
                if (reading == null) return resolve("Temperature/Humidity reading failed.");
                // Stores temp and humid readings for use in report
                if ("temperature" in reading) report.temp <- reading.temperature;
                if ("humidity" in reading) report.humid <- reading.humidity;
                ::debug(format("Temperature/Humidity reading complete, temp: %f, humidity: %f", reading.temperature, reading.humidity));
                return resolve("Temperature/Humidity reading complete");
            }.bindenv(this))
        }.bindenv(this))
    }

    function updateReportingTime() {
        local now = time();

	    // If report timer expired set based on current time 
        // TODO: When sleep/power conserve code updates - offset based on boot time
        local reportTime = now + REPORT_TIME_SEC;

        // Update report time if it has changed
        persist.setReportTime(reportTime, false);

        ::debug("Next report time " + reportTime + ", in " + (reportTime - now) + "s");
    }

    // Async Action Handlers
    // -------------------------------------------------------------

    // Assist messages written to u-blox completed
    // Logs write errors if any
    function onAssistMsgDone(errs) {
        ::debug("Assist messages written to u-blox");
        if (errs != null) {
            foreach(err in errs) {
                // Log errors encountered
                ::error(err.error);
            }
        }
    }

    // Helpers
    // -------------------------------------------------------------

    function shouldGetOfflineAssist() {
        local lastChecked = persist.getOfflineAssestChecked();
        return (lastChecked == null || time() >= (lastChecked + OFFLINE_ASSIST_REQ_MAX));
    }

    // Returns boolean, checks for event(s) or if report time has passed
    function shouldReport() {
        // Check if we have moved using current and previous location
        // NOTE: This updates stored location, so needs to be the first thing checked
        if ("fix" in report) {
            // We have a new location, check distance

            // Get stored location
            local lastLoc = persist.getLocation();

            if (lastLoc == null) {
                // We have not reported a location yet, so send a report
                // Update stored lat and lng
                persist.setLocation(lat, lng, storeToSpi);
                return true;
            } else {
                ::debug("Got location in report. Calculating distance.");
                ::debug("Last location: lat " + lastLoc.lat + ", lng " + lastLoc.lng);

                local lat = report.fix.lat;
                local lng = report.fix.lng;

                ::debug("New location: lat " + lat + ", lng " + lng);

                // Param order: new lat, new lng, old lat old lng
                local dist = loc.calculateDistance(lat, lng, lastLoc.lat, lastLoc.lng);
                report.dist <- dist;

                // Update stored lat and lng
                persist.setLocation(lat, lng, storeToSpi);

                // Report if we have moved more than the minimum distance
                if (dist >= DISTANCE_THRESHOLD_M) {
                    report.locationChanged <- true;
                    return true;
                }
            }
        }

        // NOTE: We need a valid timestamp to determine sleep times.
        // If the imp looses all power, a connection to the server is
        // needed to get a valid timestamp.
        local validTS = validTimestamp();
        ::debug("Valid timestamp: " + validTS);
        if (!validTS) return true;

        // Check if battery is low
        if ("battStatus" in report && report.battStatus.percent <= BATTERY_LOW_THRESH) {
            return true;
        } 

        // TODO: Feature - Add temp/humid in range checks

        // Check if report time has passed
        local now = time();
        local shouldReport = (now >= persist.getReportTime());
        ::debug("Time to send report: " + shouldReport);
        return shouldReport;
    }

    // Returns boolean, if the imp module currently has a valid timestamp
    function validTimestamp() {
        local d = date();
        // If imp doesn't have a valid timestamp the date method returns
        // a year of 2000. Check that the year returned by the date method
        // is greater or equal to VALID_TS_YEAR constant.
        return (d.year >= VALID_TS_YEAR);
    }
    
}

// Runtime
// -----------------------------------------------------------------------

// Start controller
MainController();