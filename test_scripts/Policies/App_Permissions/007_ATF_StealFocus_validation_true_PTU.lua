-- Requirement summary:
-- [[Policies]] <app_id> policies and "steal_focus" validation.

-- Description:
-- In case the <app id> policies are assigned to the application, PoliciesManager must validate "steal_focus" section and in case "steal_focus:true",
-- PoliciesManager must allow SDL to pass the RPC that contains the soft button with STEAL_FOCUS SystemAction.
-- Note: in sdl_preloaded_pt. json, should be "steal_focus:true" for Policies.
-- Note: in ptu.json, should be "steal_focus:true".

-- 1. RunSDL. InitHMI. InitHMI_onReady. ConnectMobile. StartSession.
-- 2. Activiate Application for allow sendRPC Alert
-- 3. Run With_Steal Focus TrueValue for Current_App
-- 4. MOB-SDL: SendRPC with soft button, STEAL_FOCUS in SystemAction
-- Expected result
-- SDL must response: success = true, resultCode = "SUCCESS"
--------------------------------------------------------------------------------------------------------------------------------------------------------
--[[ General configuration parameters ]]
--ToDo: shall be removed when issue: "ATF does not stop HB timers by closing session and connection" is fixed
config.defaultProtocolVersion = 2

--[[ Required Shared libraries ]]
local commonFunctions = require ('user_modules/shared_testcases/commonFunctions')
local commonSteps = require ('user_modules/shared_testcases/commonSteps')
local commonTestCases = require ('user_modules/shared_testcases/commonTestCases')
local commonPreconditions = require ('user_modules/shared_testcases/commonPreconditions')
local testCasesForPolicyTableSnapshot = require ('user_modules/shared_testcases/testCasesForPolicyTableSnapshot')
local testCasesForPolicyTable = require ('user_modules/shared_testcases/testCasesForPolicyTable')
local utils = require ('user_modules/utils')

--[[ Local Functions ]]
local function SendOnSystemContext(self, ctx)
  self.hmiConnection:SendNotification("UI.OnSystemContext",{ appID = self.applications[config.application1.registerAppInterfaceParams.appName], systemContext = ctx })
end

--[[ General Precondition before ATF start ]]
commonSteps:DeleteLogsFileAndPolicyTable()
commonPreconditions:Connecttest_without_ExitBySDLDisconnect_WithoutOpenConnectionRegisterApp("connecttest_connect_device.lua")

--[[ General Settings for configuration ]]
Test = require('user_modules/connecttest_connect_device')
require('cardinalities')
require('user_modules/AppTypes')
local mobile_session = require("mobile_session")

--[[ Preconditions ]]
function Test:Precondition_Connect_device()
  commonTestCases:DelayedExp(2000)
  self:connectMobile()
  EXPECT_HMICALL("BasicCommunication.UpdateDeviceList", {
      deviceList = { { id = utils.getDeviceMAC(), name = utils.getDeviceName(), transportType = "WIFI", isSDLAllowed = false} } })
  :Do(function(_,data)
      self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
    end)
end

function Test:Precondition_StartNewSession()
  self.mobileSession = mobile_session.MobileSession(self, self.mobileConnection)
  self.mobileSession:StartService(7)
end

function Test:Precondition_ActivateApplication()
  config.application1.registerAppInterfaceParams.fullAppID = "123456"
  local CorIdRAI = self.mobileSession:SendRPC("RegisterAppInterface", config.application1.registerAppInterfaceParams)
  EXPECT_HMINOTIFICATION("BasicCommunication.OnAppRegistered", { application = { policyAppID = "123456"} })
  :Do(function(_,data)
      self.applications[config.application1.registerAppInterfaceParams.appName] = data.params.application.appID
      local RequestId = self.hmiConnection:SendRequest("SDL.ActivateApp", {appID = self.applications[config.application1.registerAppInterfaceParams.appName]})
      EXPECT_HMIRESPONSE(RequestId, { result = {
            code = 0,
            isSDLAllowed = false},
          method = "SDL.ActivateApp"})
      :Do(function(_,_)
          local RequestId1 = self.hmiConnection:SendRequest("SDL.GetUserFriendlyMessage", {language = "EN-US", messageCodes = {"DataConsent"}})
          EXPECT_HMIRESPONSE(RequestId1,{result = {code = 0, method = "SDL.GetUserFriendlyMessage"}})
          :Do(function(_,_)
              self.hmiConnection:SendNotification("SDL.OnAllowSDLFunctionality", {allowed = true, source = "GUI", device = {id = utils.getDeviceMAC(), name = utils.getDeviceName()}})
              EXPECT_HMICALL("BasicCommunication.ActivateApp")
              :Do(function(_,data1)
                  self.hmiConnection:SendResponse(data1.id,"BasicCommunication.ActivateApp", "SUCCESS", {})
                  EXPECT_NOTIFICATION("OnHMIStatus", {hmiLevel = "FULL", systemContext = "MAIN"})
                end)
            end)
        end)
    end)
  EXPECT_RESPONSE(CorIdRAI, { success = true, resultCode = "SUCCESS"})
end

function Test:Precondition_DeactivateApp()
  self.hmiConnection:SendNotification("BasicCommunication.OnAppDeactivated", {appID = self.applications[config.application1.registerAppInterfaceParams.appName], reason = "GENERAL"})
  EXPECT_NOTIFICATION("OnHMIStatus", {hmiLevel = "LIMITED"})
end

function Test:Preconditions_Update_Policy_With_Steal_Focus_FalseValue_for_Current_App()
  local pts_file_name = commonFunctions:read_parameter_from_smart_device_link_ini("SystemFilesPath") .. "/"
    .. commonFunctions:read_parameter_from_smart_device_link_ini("PathToSnapshot")
  EXPECT_HMINOTIFICATION("SDL.OnStatusUpdate", { status = "UPDATING" }, { status = "UP_TO_DATE" }):Times(2)
  local requestId = self.hmiConnection:SendRequest("SDL.GetPolicyConfigurationData",
      { policyType = "module_config", property = "endpoints" })
  EXPECT_HMIRESPONSE(requestId)
  :Do(function()
      self.hmiConnection:SendNotification("BasicCommunication.OnSystemRequest", {
          requestType = "PROPRIETARY",
          fileName = pts_file_name
        }
      )
      EXPECT_NOTIFICATION("OnSystemRequest", { requestType = "PROPRIETARY" })
      :Do(function()
          local CorIdSystemRequest = self.mobileSession:SendRPC("SystemRequest", {
            requestType = "PROPRIETARY" }, "files/ptu_general_steal_focus_true.json")
          EXPECT_HMICALL("BasicCommunication.SystemRequest")
          :Do(function(_, data)
              self.hmiConnection:SendNotification("SDL.OnReceivedPolicyUpdate", { policyfile = data.params.fileName })
              self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
            end)
          self.mobileSession:ExpectResponse(CorIdSystemRequest, { success = true, resultCode = "SUCCESS" })
        end)
    end)
end

--[[Test]]
commonFunctions:newTestCasesGroup("Test")

function Test:TestStep_UpdatePTS()
  testCasesForPolicyTable:trigger_user_request_update_from_HMI(self)
end

function Test:TestStep_Verify_appid_section()
  local test_fail = false
  local steal_focus = testCasesForPolicyTableSnapshot:get_data_from_PTS("app_policies.123456.steal_focus")

  if(steal_focus ~= true) then
    commonFunctions:printError("Error: steal_focus is not true")
    test_fail = true
  end
  if(test_fail == true) then
    self:FailTestCase("Test failed. See prints")
  end
end

function Test:TestCase_SendRPC_with_STEAL_FOCUS_Value()
  local CorIdAlert = self.mobileSession:SendRPC("Alert",
    {
      alertText1 = "alertText1",
      alertText2 = "alertText2",
      alertText3 = "alertText3",
      ttsChunks =
      {
        {
          text = "TTSChunk",
          type = "TEXT",
        }
      },
      duration = 5000,
      playTone = true,
      progressIndicator = true,
      softButtons =
      {
        {
          type = "TEXT",
          text = "Keep",
          isHighlighted = true,
          softButtonID = 4,
          systemAction = "STEAL_FOCUS",
        },

        {
          type = "IMAGE",
          image =
          {
            value = "icon.png",
            imageType = "STATIC",
          },
          softButtonID = 5,
          systemAction = "STEAL_FOCUS",
        },
      }
    })
  local AlertId
  EXPECT_HMICALL("UI.Alert",
    {
      appID = self.applications["Test Application"],
      alertStrings =
      {
        {fieldName = "alertText1", fieldText = "alertText1"},
        {fieldName = "alertText2", fieldText = "alertText2"},
        {fieldName = "alertText3", fieldText = "alertText3"}
      },
      alertType = "BOTH",
      duration = 0,
      progressIndicator = true,
      softButtons =
      {
        {
          type = "TEXT",
          text = "Keep",
          isHighlighted = true,
          softButtonID = 4,
          systemAction = "STEAL_FOCUS",
        },
        {
          type = "IMAGE",
          softButtonID = 5,
          systemAction = "STEAL_FOCUS",
        },
      }
    })
  :Do(function(_,data)
      SendOnSystemContext(self,"ALERT")
      AlertId = data.id
      local function alertResponse()
        self.hmiConnection:SendResponse(AlertId, "UI.Alert", "SUCCESS", { })
        SendOnSystemContext(self,"MAIN")
      end

      RUN_AFTER(alertResponse, 3000)
    end)
  local SpeakId
  EXPECT_HMICALL("TTS.Speak",
    {
      ttsChunks =
      {
        {
          text = "TTSChunk",
          type = "TEXT"
        }
      },
      speakType = "ALERT",
      playTone = true
    })
  :Do(function(_,data)
      self.hmiConnection:SendNotification("TTS.Started")
      SpeakId = data.id
      local function speakResponse()
        self.hmiConnection:SendResponse(SpeakId, "TTS.Speak", "SUCCESS", { })

        self.hmiConnection:SendNotification("TTS.Stopped")
      end
      RUN_AFTER(speakResponse, 2000)
    end)
  :ValidIf(function(_,data)
      if #data.params.ttsChunks == 1 then
        return true
      else
        print("ttsChunks array in TTS.Speak request has wrong element number. Expected 1")
        return false
      end
    end)
  EXPECT_RESPONSE(CorIdAlert, { success = true, resultCode = "SUCCESS"})
end

--[[ Postconditions ]]
commonFunctions:newTestCasesGroup("Postconditions")
function Test.Postcondition_StopSDL()
  StopSDL()
end

return Test
