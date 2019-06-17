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
const CHECK_IN_TIME_SEC    = 10;
// Wake every x seconds to send a report, regaurdless of check results
const REPORT_TIME_SEC      = 300 // 60 * 5; 

// Accuracy of GPS fix in meters
const LOCATION_ACCURACY    = 10;
const LOCATION_TIMEOUT_SEC = 70; 
// Constant used to validate imp's timestamp (must be a year greater than 2000)
const VALID_TS_YEAR        = 2019;

class MainController {

    // Class instances
    cm         = null;
    mm         = null;
    loc        = null;
    env        = null;
    battery    = null;
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
        cm = ConnectionManager({ "blinkupBehavior": CM_BLINK_ALWAYS });
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

        // Reset report table
        report = {};
        
        updateReportingTime();
        scheduleNextCheckIn();
    }

    // MM onReply handler for assist messages
    function mmOnAssist(msg, response) {
        if (response == null) {
            ::debug("Didn't receive any Assist messages from agent.");
            return;
        }

        ::debug("Assist messages received from agent. Writing to u-blox");
        // Make sure location class is initialized
        if (loc == null) loc = Location(); 
        // Response contains assist messages from cloud
        local assistMsgs = response;

        if (msg.payload.data == ASSIST_TYPE.OFFLINE) {
            // Get today's date string/file name
            local todayFileName = loc.getAssistDateFileName();

            // Store all offline assist messages by date
            persist.storeAssist(response);

            // Select today's offline assist messages only
            if (todayFileName in response) {
                assistMsgs = response.todayFileName;
            } else {
                ::debug("No offline assist messges for today. No messages written to UBLOX.");
                return;
            }
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

        // Get offline assist messages
        reqOfflineAssist();

        // Trigger async tasks
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
    }

    function onCheckIn() {
        ::debug("Made it to first check-in!!!");
        // TODO: Update this once onBoot is working!!!

        // Take readings (location, temp, batt)
        // If (when) online 
            // Refresh offline assist messages (if needed - limit to every 12h)
        // Check if should report (location change, low battery)
            // Send report
            // or schedule next check-in
    }

    function scheduleNextCheckIn() {
        ::debug("Scheduling next check-in: " + (time() + CHECK_IN_TIME_SEC));
        // TODO: update with power down/sleep logic to conserve battery
        imp.wakeup(CHECK_IN_TIME_SEC, onCheckIn.bindenv(this));
    }

    // Actions
    // -------------------------------------------------------------

    // Send a request to agent for offline assist messages
    function reqOfflineAssist() {
        if (cm.isConnected()) {
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
            ::debug("Requesting online assist messages from agnet/Assist Now.");
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
            if (loc == null) loc = Location();
            loc.getLocation(LOCATION_ACCURACY, function(gpxFix) {
                ::debug("Got fix. Disabling GPS power");
                PWR_GATE_EN.write(0);
        
                // Store fix data for report
                // NOTE: Keep both raw (so we can store easily to SPI) and formatted 
                // lat and lng (for reporting) 
                if ("lat" in gpxFix) report.lat = UbxMsgParser.toDecimalDegreeString(gpxFix.lat);
                if ("lng" in gpxFix) report.lng = UbxMsgParser.toDecimalDegreeString(gpxFix.lng);
                report.fix <- gpxFix;
                return resolve("GPS location done");
            }.bindenv(this));

            //Configure Location Timeout
            imp.wakeup(LOCATION_TIMEOUT_SEC, function() {
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
            if (battery == null) battery = Battery(false);
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
            if (env == null)  env = Env(false);
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

    // Returns boolean, checks for event(s) or if report time has passed
    function shouldReport() {
        // TODO: updat this logic for current application!!!

        // Check for events
        // Note: TODO check if location has changed
        // local haveMoved = persist.getMoveDetected();
        // ::debug("Movement detected: " + haveMoved);
        // if (haveMoved) return true;

        // NOTE: We need a valid timestamp to determine sleep times.
        // If the imp looses all power, a connection to the server is
        // needed to get a valid timestamp.
        local validTS = validTimestamp();
        ::debug("Valid timestamp: " + validTS);
        if (!validTS) return true;

        // Check if report time has passed
        // local now = time();
        // local shouldReport = (now >= persist.getReportTime());
        // ::debug("Time to send report: " + shouldReport);
        // return shouldReport;
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