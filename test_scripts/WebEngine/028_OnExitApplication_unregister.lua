--[[ General test configuration ]]
config.defaultMobileAdapterType = "WS"

--[[ Required Shared libraries ]]
local common = require('test_scripts/WebEngine/commonWebEngine')
local runner = require('user_modules/script_runner')

--[[ Local Variables ]]
  local appProp = {
    nicknames = { "Test Application" },
    policyAppID = "0000001",
    enabled = true,
    authToken = "ABCD12345",
    transportType = "WS",
    hybridAppPreference = "CLOUD"
  }

--[[ Local Functions ]]
local function setAppProperties()
  common.checkUpdateAppList(appProp.policyAppID, 1, 1)
  common.setAppProperties(appProp)
end

local function onExitApp()
  local appID = common.getHMIAppId()
  common.getHMIConnection():SendNotification("BasicCommunication.OnExitApplication", {reason = "RESOURCE_CONSTRAINT", appID = appID})
  common.getHMIConnection():ExpectNotification("BasicCommunication.OnAppUnregistered", {unexpectedDisconnect = false, appID = appID})
  common.getMobileSession():ExpectNotification("OnAppInterfaceUnregistered", {reason = "RESOURCE_CONSTRAINT"})
  common.checkUpdateAppList(appProp.policyAppID, 1, 1)
end

local function registerApp()
  common.checkUpdateAppList(appProp.policyAppID, 1, 1)
  common.registerAppWOPTU()
end

-- [[ Scenario ]]
common.Title("Preconditions")
common.Step("Clean environment", common.preconditions)
common.Step("Start SDL, HMI", common.startWOdeviceConnect)

common.Title("Test")
runner.Step("Connect WebEngine device", common.connectWebEngine, { 1, config.defaultMobileAdapterType })
common.Step("SetAppProperties enabled=true", setAppProperties)
common.Step("Register App", registerApp)
common.Step("OnExitApplication", onExitApp)

common.Title("Postconditions")
common.Step("Stop SDL", common.postconditions)
