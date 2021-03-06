---------------------------------------------------------------------------------------------------
-- Proposal:
-- https://github.com/smartdevicelink/sdl_evolution/blob/master/proposals/0221-multiple-modules.md
-- Description:
--  Check of GetInteriorVehicleDataConsent RPC processing with one moduleId and module allocation is performed
--  without asking driver if access mode is AUTO_ALLOW
--
-- Precondition:
-- 1) SDL and HMI are started
-- 2) HMI sent RC capabilities with modules of each type (allowMultipleAccess: true) to SDL
-- 3) RC access mode set from HMI: AUTO_ALLOW
-- 4) Mobile is connected to SDL
-- 5) App1 and App2 (appHMIType: ["REMOTE_CONTROL"]) are registered from Mobile
-- 6) App1 and App2 are within serviceArea of modules
-- 7) HMI level of App1 is BACKGROUND;
--    HMI level of App2 is FULL
-- 8) RC modules are free
--
-- Steps:
-- 1) Allocate free modules (moduleType: <moduleType>, moduleId: <moduleId>) to App2 via SetInteriorVehicleData RPC
--   Check:
--    SDL responds on SetInteriorVehicleData RPC with resultCode: SUCCESS
--    SDL does not send GetInteriorVehicleDataConsent RPC to HMI
--    SDL allocates module (moduleType: <moduleType>, moduleId: <moduleId>) to App2
--     and sends appropriate OnRCStatus notifications
-- 2) Activate App1 and send GetInteriorVehicleDataConsent RPC for one module of each RC module type sequentially
--     (moduleType: <moduleType>, moduleIds: [<moduleId>]) from App1
--   Check:
--    SDL does not send RC.GetInteriorVehicleDataConsent request to HMI
--    SDL responds on GetInteriorVehicleDataConsent RPC with resultCode:"SUCCESS", success:true, allowed: [true]
--    SDL does not send OnRCStatus notifications to HMI and Apps
-- 3) Try to reallocate module (moduleType: <moduleType>, moduleId: <moduleId>)
--     to App1 via SetInteriorVehicleData RPC sequentially
--   Check:
--    SDL does not send GetInteriorVehicleDataConsent RPC to HMI
--    SDL allocates module (moduleType: <moduleType>, moduleId: <moduleId>) to App1
--     and sends appropriate OnRCStatus notifications to HMI and Apps
--    SDL responds on SetInteriorVehicleData RPC with resultCode: SUCCESS
---------------------------------------------------------------------------------------------------
local runner = require('user_modules/script_runner')
local common = require("test_scripts/RC/MultipleModules/commonRCMulModules")

--[[ Test Configuration ]]
runner.testSettings.isSelfIncluded = false

--[[ Local Variables ]]
local appLocation = {
  [1] = common.grid.BACK_RIGHT_PASSENGER,
  [2] = common.grid.BACK_CENTER_PASSENGER
}

local accessMode = "AUTO_ALLOW"

local testServiceArea = common.grid.BACK_SEATS

local rcAppIds = { 1, 2 }

local rcCapabilities = common.initHmiRcCapabilitiesConsent(testServiceArea)
local testModulesArray = common.buildTestModulesArrayFirst(rcCapabilities)

--[[ Scenario ]]
runner.Title("Preconditions")
runner.Step("Clean environment", common.preconditions)
runner.Step("Prepare preloaded policy table", common.preparePreloadedPT, { rcAppIds })
runner.Step("Prepare RC modules capabilities and initial modules data", common.initHmiDataState, { rcCapabilities })
runner.Step("Start SDL, HMI, connect Mobile, start Session", common.start, { rcCapabilities })
runner.Step("Set RA mode: ".. accessMode, common.defineRAMode, { true, accessMode })
runner.Step("Register App1", common.registerAppWOPTU, { 1 })
runner.Step("Register App2", common.registerAppWOPTU, { 2 })
runner.Step("Activate App1", common.activateApp, { 1 })
runner.Step("Send user location of App1 (Back Seat)", common.setUserLocation, { 1, appLocation[1] })
runner.Step("Activate App2", common.activateApp, { 2 })
runner.Step("Send user location of App2 (Back seat)", common.setUserLocation, { 2, appLocation[2] })

for _, testModule in ipairs(testModulesArray) do
  runner.Step("Allocate module [" .. testModule.moduleType .. ":" .. testModule.moduleId .. "] to App2",
      common.rpcSuccess, { testModule.moduleType, testModule.moduleId, 2, "SetInteriorVehicleData" })
end

runner.Title("Test")
runner.Step("Activate App1", common.activateApp, { 1 })
for _, testModule in ipairs(testModulesArray) do
  runner.Step("Allow module [" .. testModule.moduleType .. ":" .. testModule.moduleId
      .. "] reallocation to App1",
    common.driverConsentForReallocationToApp,
    { 1, testModule.moduleType, { [testModule.moduleId] = true }, rcAppIds, accessMode })
  runner.Step("Reallocate module [" .. testModule.moduleType .. ":" .. testModule.moduleId .. "] to App1",
    common.allocateModuleWithoutConsent, { 1, testModule.moduleType, testModule.moduleId, nil, rcAppIds })
end

runner.Title("Postconditions")
runner.Step("Stop SDL", common.postconditions)
