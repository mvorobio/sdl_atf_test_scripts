
local actions = require("user_modules/sequences/actions")
local utils = require("user_modules/utils")
local test = require("user_modules/dummy_connecttest")

local commonAppServices = actions

local serviceIDs = {}

function commonAppServices.appServiceCapability(update_reason, manifest) 
  local appService = {
    updateReason = update_reason,
    updatedAppServiceRecord = {
      serviceManifest = manifest
    }
  }
  if update_reason == "PUBLISHED" then
    appService.updatedAppServiceRecord.servicePublished = true
    appService.updatedAppServiceRecord.serviceActive = false
  elseif update_reason == "REMOVED" then
    appService.updatedAppServiceRecord.servicePublished = false
    appService.updatedAppServiceRecord.serviceActive = false
  elseif update_reason == "ACTIVATED" then
    appService.updatedAppServiceRecord.servicePublished = true
    appService.updatedAppServiceRecord.serviceActive = true
  elseif update_reason == "DEACTIVATED" then
    appService.updatedAppServiceRecord.servicePublished = true
    appService.updatedAppServiceRecord.serviceActive = false
  end
  return appService
end

function commonAppServices.appServiceCapabilityUpdateParams(update_reason, manifest)
  return {
    systemCapability = {
      systemCapabilityType = "APP_SERVICES",
      appServicesCapabilities = {
        appServices = {
          commonAppServices.appServiceCapability(update_reason, manifest)
        }
      }
    }
  }
end

function commonAppServices.getAppServiceConsumerConfig(app_id)
  return {
    keep_context = false,
    steal_focus = false,
    priority = "NONE",
    default_hmi = "NONE",
    groups = { "Base-4" , "AppServiceConsumer" },
    nicknames = { config["application" .. app_id].registerAppInterfaceParams.appName }
  }
end

function commonAppServices.getAppServiceProducerConfig(app_id)
  return {
    keep_context = false,
    steal_focus = false,
    priority = "NONE",
    default_hmi = "NONE",
    groups = { "Base-4" , "AppServiceProvider" },
    nicknames = { config["application" .. app_id].registerAppInterfaceParams.appName },
    app_services = {
      MEDIA = {
        handled_rpcs = {{function_id = 2000}},
        service_names = {
          config["application" .. app_id].registerAppInterfaceParams.appName
        }
      }
    }
  }
end

function commonAppServices.findCapabilityUpdate(capability, params)
  if not params.systemCapability then
    return false, "params.systemCapability is nil"
  end
  local systemCapability = params.systemCapability
  if not systemCapability.systemCapabilityType == "APP_SERVICES" or not systemCapability.appServicesCapabilities then
    return false, "appServicesCapabilities is nil"
  end
  local appServices = systemCapability.appServicesCapabilities.appServices
  for key, value in pairs(appServices) do
    local res, err = compareValues(capability, value, "params")
    if res then
      return true
    end
  end
  return false, "unable to find matching app service update"
end

function commonAppServices.publishEmbeddedAppService(manifest)
  local cid = commonAppServices.getHMIConnection():SendRequest("AppService.PublishAppService", {
    appServiceManifest = manifest
  })
  local first_run = true
  EXPECT_HMINOTIFICATION("BasicCommunication.OnSystemCapabilityUpdated"):Times(AtLeast(1)):ValidIf(function(self, data)
      if first_run then
        first_run = false
        local publishedParams = commonAppServices.appServiceCapability("PUBLISHED", manifest)
        return commonAppServices.findCapabilityUpdate(publishedParams, data.params)
      else
        local activatedParams = commonAppServices.appServiceCapability("ACTIVATED", manifest)
        return commonAppServices.findCapabilityUpdate(activatedParams, data.params)
      end
    end)
  EXPECT_HMIRESPONSE(cid, {
    result = {
      appServiceRecord = {
        serviceManifest = manifest,
        servicePublished = true
      },
      code = 0, 
      method = "AppService.PublishAppService"
    }
  }):Do(function(_, data)
      if data.result.appServiceRecord then
        serviceIDs[0] = data.result.appServiceRecord.serviceID
      end
    end)
end

function commonAppServices.publishMobileAppService(manifest, app_id)
  if not app_id then app_id = 1 end
  local mobileSession = commonAppServices.getMobileSession(app_id)
  local cid = mobileSession:SendRPC("PublishAppService", {
    appServiceManifest = manifest
  })

  local first_run = true
  mobileSession:ExpectNotification("OnSystemCapabilityUpdated"):Times(AtLeast(1)):ValidIf(function(self, data)
      if first_run then
        first_run = false
        local publishedParams = commonAppServices.appServiceCapability("PUBLISHED", manifest)
        return commonAppServices.findCapabilityUpdate(publishedParams, data.payload)
      else
        local activatedParams = commonAppServices.appServiceCapability("ACTIVATED", manifest)
        return commonAppServices.findCapabilityUpdate(activatedParams, data.payload)
      end
    end)
  mobileSession:ExpectResponse(cid, {
    appServiceRecord = {
      serviceManifest = manifest,
      servicePublished = true
    },
    success = true,
    resultCode = "SUCCESS"
  }):Do(function(_, data)
      if data.payload.success then
        serviceIDs[app_id] = data.payload.appServiceRecord.serviceID
      end
    end)
end

function commonAppServices.publishSecondMobileAppService(manifest1, manifest2, app_id)
  if not app_id then app_id = 2 end

  local mobileSession = commonAppServices.getMobileSession(app_id)
  local cid = mobileSession:SendRPC("PublishAppService", {
    appServiceManifest = manifest2
  })

  local second_app_record = commonAppServices.appServiceCapability("PUBLISHED", manifest2)

  local publishedParams = commonAppServices.appServiceCapabilityUpdateParams("ACTIVATED", manifest1)
  publishedParams.systemCapability.appServicesCapabilities.appServices[2] = second_app_record
  publishedParams.systemCapability.appServicesCapabilities.appServices[1].updateReason = nil

  mobileSession:ExpectNotification("OnSystemCapabilityUpdated", publishedParams):Times(1)
  mobileSession:ExpectResponse(cid, {
    appServiceRecord = {
      serviceManifest = manifest,
      servicePublished = true
    },
    success = true,
    resultCode = "SUCCESS"
  }):Do(function(_, data)
      if data.payload.success then
        serviceIDs[app_id] = data.payload.appServiceRecord.serviceID
      end
    end)
end

function commonAppServices.mobileSubscribeAppServiceData(provider_app_id, app_id)
  if not app_id then app_id = 1 end
  local requestParams = {
    serviceType = "MEDIA",
    subscribe = true
  }
  local mobileSession = commonAppServices.getMobileSession(app_id)
  local cid = mobileSession:SendRPC("GetAppServiceData", requestParams)
  local service_id = commonAppServices.getAppServiceID(provider_app_id)
  local responseParams = {
    serviceData = {
      serviceID = service_id,
      serviceType = "MEDIA",
      mediaServiceData = {}
    }
  }
  if provider_app_id == 0 then
    EXPECT_HMICALL("AppService.GetAppServiceData", requestParams):Do(function(_, data) 
        commonAppServices.getHMIConnection():SendResponse(data.id, data.method, "SUCCESS", responseParams)
      end)
  else
    local providerMobileSession = commonAppServices.getMobileSession(provider_app_id)

    -- Fill out mobile response params
    responseParams.resultCode = "SUCCESS"
    responseParams.success = true
    providerMobileSession:ExpectRequest("GetAppServiceData", requestParams):Do(function(_, data) 
        providerMobileSession:SendResponse("GetAppServiceData", data.rpcCorrelationId, responseParams)
      end)
  end

  mobileSession:ExpectResponse(cid, responseParams)
end

function commonAppServices.getAppServiceID(app_id)
  if not app_id then app_id = 1 end
  return serviceIDs[app_id]
end

function commonAppServices.GetAppServiceSystemCapability(manifest, subscribe, app_id)
  if not app_id then app_id = 1 end
  local requestParams = {
    systemCapabilityType = "APP_SERVICES",
    subscribe = subscribe
  }

  local mobileSession = commonAppServices.getMobileSession(app_id)
  local cid = mobileSession:SendRPC("GetSystemCapability", requestParams)

  local responseParams = {
    success = true,
    resultCode = "SUCCESS",
    systemCapability = {
      systemCapabilityType = "APP_SERVICES",
      appServicesCapabilities = {
        appServices = {{
          updatedAppServiceRecord = {
            serviceManifest = manifest
          }
        }}
      }
    }
  }

  mobileSession:ExpectResponse(cid, responseParams)
end

function commonAppServices.cleanSession(app_id)
  test.mobileSession[app_id]:StopRPC()
  :Do(function(_, d)
    utils.cprint(35, "Mobile session " .. d.sessionId .. " deleted")
    test.mobileSession[app_id] = nil
  end)
  utils.wait()
end

return commonAppServices