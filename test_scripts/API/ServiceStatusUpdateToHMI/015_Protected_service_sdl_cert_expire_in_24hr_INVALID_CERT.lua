-----------------------------------------------------------------------------------------------------------------------
-- Proposal:
-- https://github.com/smartdevicelink/sdl_evolution/blob/master/proposals/0211-ServiceStatusUpdateToHMI.md
-----------------------------------------------------------------------------------------------------------------------
-- Description: Attempt to open protected Audio/Video service with OnServiceUpdate notification
-- in case of defined force protection and SDL certificate is about to expire in 24 hrs
--
-- Preconditions:
-- 1) SDL certificate is about to expire in next 24 hours
-- 2) Force protection for the service is switched ON
-- 3) App is registered with NAVIGATION appHMIType and activated
-- Steps:
-- 1) App sends StartService request (<service_type>, encryption = true)
-- SDL does:
--   - send OnServiceUpdate (<service_type>, REQUEST_RECEIVED) to HMI
--   - send GetSystemTime() request to HMI and wait for the response
-- 2) HMI sends valid GetSystemTime response
-- SDL does:
--   - start PTU sequence and send OnStatusUpdate(UPDATE_NEEDED) to HMI
-- 3) Policy Table Update is finished successfully and brought the same SDL certificate
-- that is about to expire in next 24 hours
-- SDL does:
--   - send OnStatusUpdate(UP_TO_DATE) to HMI
--   - send OnServiceUpdate (<service_type>, REQUEST_REJECTED, INVALID_CERT) to HMI
--   - send StartServiceNACK(<service_type>, encryption = false) to App
--   - send BC.CloseApplication to HMI
--   - send OnHMIStatus(NONE) to mobile app
-----------------------------------------------------------------------------------------------------------------------
--[[ Required Shared libraries ]]
local runner = require('user_modules/script_runner')
local common = require('test_scripts/API/ServiceStatusUpdateToHMI/common')

--[[ Test Configuration ]]
runner.testSettings.isSelfIncluded = false

--[[ Local Constants ]]
local videoServiceId = 11
local audioServiceId = 10

--[[ Local Functions ]]
function common.sendGetSystemTimeResponse(pId, pMethod)
  local st = {
    millisecond = 100,
    second = 30,
    minute = 29,
    hour = 15,
    day = 18,
    month = 4,
    year = 2045,
    tz_hour = -3,
    tz_minute = 10
  }
  common.getHMIConnection():SendResponse(pId, pMethod, "SUCCESS", { systemTime = st })
end

function common.onServiceUpdateFunc(pServiceTypeValue)
  common.getHMIConnection():ExpectNotification("BasicCommunication.OnServiceUpdate",
    { serviceEvent = "REQUEST_RECEIVED", serviceType = pServiceTypeValue, appID = common.getHMIAppId() },
    { serviceEvent = "REQUEST_REJECTED", serviceType = pServiceTypeValue, appID = common.getHMIAppId(),
      reason = "INVALID_CERT" })
  :Times(2)

  common.getHMIConnection():ExpectRequest("BasicCommunication.CloseApplication", { appID = common.getHMIAppId() })
  :Do(function(_, data)
      common.getHMIConnection():SendResponse(data.id, data.method, "SUCCESS", { })
    end)

  common.getMobileSession():ExpectNotification("OnHMIStatus",
    { hmiLevel = "NONE", audioStreamingState = "NOT_AUDIBLE", systemContext = "MAIN" })
end

function common.serviceResponseFunc(pServiceId)
  common.getMobileSession():ExpectControlMessage(pServiceId, {
    frameInfo = common.frameInfo.START_SERVICE_NACK,
    encryption = false
  })
end

--[[ Scenario ]]
runner.Title("Preconditions")
runner.Step("Clean environment", common.preconditions, {
  common.serviceData[audioServiceId].forceCode .. ', ' .. common.serviceData[videoServiceId].forceCode })
runner.Step("Init SDL certificates", common.initSDLCertificates,
  { "./files/Security/client_credential.pem", true })
runner.Step("Start SDL, HMI, connect Mobile, start Session", common.start)
runner.Step("App registration", common.registerApp)
runner.Step("PolicyTableUpdate", common.policyTableUpdate)
runner.Step("App activation", common.activateApp)

runner.Title("Test")
runner.Step("Start Video Service protected, REJECTED", common.startServiceWithOnServiceUpdate, { videoServiceId, 0, 1 })
runner.Step("App activation", common.activateApp)
runner.Step("Start Audio Service protected, REJECTED", common.startServiceWithOnServiceUpdate, { audioServiceId, 0, 1 })

runner.Title("Postconditions")
runner.Step("Stop SDL", common.postconditions)
