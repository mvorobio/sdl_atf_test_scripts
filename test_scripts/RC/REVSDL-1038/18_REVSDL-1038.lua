local commonSteps = require("user_modules/shared_testcases/commonSteps")
commonSteps:DeleteLogsFileAndPolicyTable()

revsdl = require("user_modules/revsdl")

revsdl.AddUnknownFunctionIDs()
revsdl.SubscribeToRcInterface()
config.ValidateSchema = false
config.application1.registerAppInterfaceParams.appHMIType = { "REMOTE_CONTROL" }

Test = require('connecttest')
require('cardinalities')
local events = require('events')
local mobile_session = require('mobile_session')

---------------------------------------------------------------------------------------------
-----------------------REVSDL-1038: HMI's RPCs validation rules------------------------------
---------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------

--=================================================BEGIN TEST CASES 18==========================================================--

  --Begin Test case ResponseFakeParamsNotification.18
  --Description:  --Fake params

    --Requirement/Diagrams id in jira:
        --REVSDL-1038

    --Verification criteria:
        --<19.>In case RSDL sends a request following the internal processes to HMI (example: permission request), and HMI responds with one or more fake params (that is, non-existent per HMI_API) to RSDL, RSDL must cut these fake params off and process the response
            --Information: applicable RPCs:
            --GetInteriorVehicleDataConsent


      --Begin Test case ResponseFakeParamsNotification.18.1
      --Description: send notification with fake params
        function Test:GetInteriorVehicleDataConsent_FakeParams()
          local cid = self.mobileSession:SendRPC("ButtonPress",
          {
            zone =
            {
              colspan = 2,
              row = 0,
              rowspan = 2,
              col = 1,
              levelspan = 1,
              level = 0
            },
            moduleType = "RADIO",
            buttonPressMode = "LONG",
            buttonName = "VOLUME_UP"
          })

        --hmi side: expect RC.GetInteriorVehicleDataConsent request
        EXPECT_HMICALL("RC.GetInteriorVehicleDataConsent",
                {
                  appID = self.applications["Test Application"],
                  moduleType = "RADIO",
                  zone =
                  {
                    colspan = 2,
                    row = 0,
                    rowspan = 2,
                    col = 1,
                    levelspan = 1,
                    level = 0
                  }
                })
          :Do(function(_,data)
            --hmi side: sending RC.GetInteriorVehicleDataConsent response
            self.hmiConnection:SendResponse(data.id, "RC.GetInteriorVehicleDataConsent", "SUCCESS", {allowed = true, isAllowed = false})

              --hmi side: expect Buttons.ButtonPress request
              EXPECT_HMICALL("Buttons.ButtonPress",
                      {
                        zone =
                        {
                          colspan = 2,
                          row = 0,
                          rowspan = 2,
                          col = 1,
                          levelspan = 1,
                          level = 0
                        },
                        moduleType = "RADIO",
                        buttonPressMode = "LONG",
                        buttonName = "VOLUME_UP"
                      })
                :Do(function(_,data)
                  --hmi side: sending Buttons.ButtonPress response
                  self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
                end)

          end)


          EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS" })
          :Timeout(3000)
        end
      --End Test case ResponseFakeParamsNotification.18.1

  --End Test case ResponseFakeParamsNotification.18
--=================================================END TEST CASES 18==========================================================--
