module("L_RFXtrx", package.seeall)

local bitw = require("bit")

local PLUGIN_VERSION = "1.50"

local THIS_DEVICE = 0
local buffer = ""
local buffering = false
local sequenceNum = 0

local taskHandle = -1
local TASK_ERROR = 2
local TASK_ERROR_PERM = -2
local TASK_SUCCESS = 4
local TASK_BUSY = 1

local typeRFX = 0x53
local firmware = 0
local firmtype = 0
local hardware = 0

local mm2inch = 0.03937008
local inch2mm = 25.4
local LacrosseInchesPerCount = 0.0105
local LacrosseMMPerCount = 0.2667

-- class.lua
-- Compatible with Lua 5.1 (not 5.0).
-- This class definition is copied from http://lua-users.org/wiki/SimpleLuaClasses
local function class(base, init)
	local c = {}	-- a new class instance
	if not init and type(base) == 'function' then
		init = base
		base = nil
	elseif type(base) == 'table' then
		-- our new class is a shallow copy of the base class!
		for i,v in pairs(base) do
			c[i] = v
		end
		c._base = base
	end
	-- the class will be the metatable for all its objects,
	-- and they will look up their methods in it.
	c.__index = c

	-- expose a constructor which can be called by <classname>(<args>)
	local mt = {}
	mt.__call = function(class_tbl, ...)
		local obj = {}
		setmetatable(obj,c)
		if init then
			init(obj,...)
		else
			-- make sure that any stuff from the base class is initialized!
			if base and base.init then
				base.init(obj, ...)
			end
		end
		return obj
	end
	c.init = init
	c.is_a = function(self, klass)
		local m = getmetatable(self)
		while m do
			if m == klass then return true end
			m = m._base
		end
		return false
	end
	setmetatable(c, mt)
	return c
end

-- Define a class for our message types
local Message = class(function(a, type, subType, length)
	a.type = type			-- the packet type
	a.subType = subType		-- the subtype
	a.length = length		-- the length in bytes
	a.key = string.format('%06X',(bitw.lshift((bitw.lshift(length,8) + type), 8)) + subType)
	a.decodeFunction = nil	-- the function used to decode the command
end)

-- A class method to print a message class object
--function Message:__tostring()
--	local part1 = "Message - length: " .. string.format("0x%02X", self.length) .. " type: " .. string.format("0x%02X", self.type)
--	local part2 = ' subType: ' .. self.subtype .. ' key: ' .. self.key or 'nil' .. ' decode function: ' .. self.decodeFunction or 'nil'
--	return (part1 .. part2)
--end

-- Create the message types in a table so we can work with them as a group
-- Each message is created with a type, subType and length
local tableMsgTypes = {
	MODE_COMMAND =				Message( 0x00, 0x00, 13 ),
	RESPONSE_MODE_COMMAND =		Message( 0x01, 0x00, 20 ),
	UNKNOWN_RTS_REMOTE =		Message( 0x01, 0x01, 13 ),
	WRONG_COMMAND =				Message( 0x01, 0xFF, 13 ),
	RECEIVER_LOCK_ERROR =		Message( 0x02, 0x00, 4 ),
	TRANSMITTER_RESPONSE =		Message( 0x02, 0x01, 4 ),
	LIGHTING_X10 =				Message( 0x10, 0x0, 7 ),
	LIGHTING_ARC =				Message( 0x10, 0x1, 7 ),
	LIGHTING_AB400D =			Message( 0x10, 0x2, 7 ),
	LIGHTING_WAVEMAN =			Message( 0x10, 0x3, 7 ),
	LIGHTING_EMW200 =			Message( 0x10, 0x4, 7 ),
	LIGHTING_IMPULS =			Message( 0x10, 0x5, 7 ),
	LIGHTING_RISINGSUN =		Message( 0x10, 0x6, 7 ),
	LIGHTING_PHILIPS =			Message( 0x10, 0x7, 7 ),
	LIGHTING_ENERGENIE_ENER010 =Message( 0x10, 0x8, 7 ),
	LIGHTING_ENERGENIE_5GANG =	Message( 0x10, 0x9, 7 ),
	LIGHTING_COCO =				Message( 0x10, 0xa, 7 ),
	LIGHTING_AC =				Message( 0x11, 0x0, 11 ),
	LIGHTING_HEU =				Message( 0x11, 0x1, 11 ),
	LIGHTING_ANSLUT =			Message( 0x11, 0x2, 11 ),
	LIGHTING_KOPPLA =			Message( 0x12, 0x0, 8 ),
	SECURITY_DOOR =				Message( 0x13, 0x0, 9 ),
	LIGHTING_LIGHTWARERF =		Message( 0x14, 0x0, 10 ),
	LIGHTING_EMW100 =			Message( 0x14, 0x1, 10 ),
	LIGHTING_BBSB =				Message( 0x14, 0x2, 10 ),
	LIGHTING_RSL2 =				Message( 0x14, 0x4, 10 ),
	LIGHTING_LIVOLO =			Message( 0x14, 0x5, 10 ),
	LIGHTING_KANGTAI =			Message( 0x14, 0x11, 10 ),
	LIGHTING_BLYSS =			Message( 0x15, 0x0, 11 ),
	CURTAIN_HARRISON =			Message( 0x18, 0x0, 7 ),
	BLIND_T0 =					Message( 0x19, 0x0, 9 ),
	BLIND_T1 =					Message( 0x19, 0x1, 9 ),
	BLIND_T2 =					Message( 0x19, 0x2, 9 ),
	BLIND_T3 =					Message( 0x19, 0x3, 9 ),
	BLIND_T4 =					Message( 0x19, 0x4, 9 ),
	BLIND_T5 =					Message( 0x19, 0x5, 9 ),
	BLIND_T6 =					Message( 0x19, 0x6, 9 ),
	BLIND_T7 =					Message( 0x19, 0x7, 9 ),
	RFY0 =						Message( 0x1A, 0x0, 12 ),
	SECURITY_X10DS =			Message( 0x20, 0x0, 8 ),
	SECURITY_X10MS =			Message( 0x20, 0x1, 8 ),
	SECURITY_X10SR =			Message( 0x20, 0x2, 8 ),
	KD101 =						Message( 0x20, 0x3, 8 ),
	POWERCODE_PRIMDS =			Message( 0x20, 0x4, 8 ),
	POWERCODE_MS =				Message( 0x20, 0x5, 8 ),
	POWERCODE_AUXDS =			Message( 0x20, 0x7, 8 ),
	SECURITY_MEISR =			Message( 0x20, 0x8, 8 ),
	SA30 =						Message( 0x20, 0x9, 8 ),
	ATI_REMOTE_WONDER =			Message( 0x30, 0x0, 6 ),
	ATI_REMOTE_WONDER_PLUS =	Message( 0x30, 0x1, 6 ),
	MEDION_REMOTE =				Message( 0x30, 0x2, 6 ),
	X10_PC_REMOTE =				Message( 0x30, 0x3, 6 ),
	ATI_REMOTE_WONDER_II =		Message( 0x30, 0x4, 6 ),
	HEATER3_MERTIK1 =			Message( 0x42, 0x0, 8 ),
	HEATER3_MERTIK2 =			Message( 0x42, 0x1, 8 ),
	TR1 =						Message( 0x4F, 0x1, 10 ),
	TEMP1 =						Message( 0x50, 0x1, 8 ),
	TEMP2 =						Message( 0x50, 0x2, 8 ),
	TEMP3 =						Message( 0x50, 0x3, 8 ),
	TEMP4 =						Message( 0x50, 0x4, 8 ),
	TEMP5 =						Message( 0x50, 0x5, 8 ),
	TEMP6 =						Message( 0x50, 0x6, 8 ),
	TEMP7 =						Message( 0x50, 0x7, 8 ),
	TEMP8 =						Message( 0x50, 0x8, 8 ),
	TEMP9 =						Message( 0x50, 0x9, 8 ),
	TEMP10 =					Message( 0x50, 0xA, 8 ),
	TEMP11 =					Message( 0x50, 0xB, 8 ),
	HUM1 =						Message( 0x51, 0x1, 8 ),
	HUM2 =						Message( 0x51, 0x2, 8 ),
	TEMP_HUM1 =					Message( 0x52, 0x1, 10 ),
	TEMP_HUM2 =					Message( 0x52, 0x2, 10 ),
	TEMP_HUM3 =					Message( 0x52, 0x3, 10 ),
	TEMP_HUM4 =					Message( 0x52, 0x4, 10 ),
	TEMP_HUM5 =					Message( 0x52, 0x5, 10 ),
	TEMP_HUM6 =					Message( 0x52, 0x6, 10 ),
	TEMP_HUM7 =					Message( 0x52, 0x7, 10 ),
	TEMP_HUM8 =					Message( 0x52, 0x8, 10 ),
	TEMP_HUM9 =					Message( 0x52, 0x9, 10 ),
	TEMP_HUM10 =				Message( 0x52, 0xa, 10 ),
	TEMP_HUM11 =				Message( 0x52, 0xb, 10 ),
	TEMP_HUM12 =				Message( 0x52, 0xc, 10 ),
	TEMP_HUM13 =				Message( 0x52, 0xd, 10 ),
	TEMP_HUM14 =				Message( 0x52, 0xe, 10 ),
	BARO1 =						Message( 0x53, 0x1, 9 ),
	TEMP_HUM_BARO1 =			Message( 0x54, 0x1, 13 ),
	TEMP_HUM_BARO2 =			Message( 0x54, 0x2, 13 ),
	RAIN1 =						Message( 0x55, 0x1, 11 ),
	RAIN2 =						Message( 0x55, 0x2, 11 ),
	RAIN3 =						Message( 0x55, 0x3, 11 ),
	RAIN4 =						Message( 0x55, 0x4, 11 ),
	RAIN5 =						Message( 0x55, 0x5, 11 ),
	RAIN6 =						Message( 0x55, 0x6, 11 ),
	RAIN7 =						Message( 0x55, 0x7, 11 ),
	WIND1 =						Message( 0x56, 0x1, 16 ),
	WIND2 =						Message( 0x56, 0x2, 16 ),
	WIND3 =						Message( 0x56, 0x3, 16 ),
	WIND4 =						Message( 0x56, 0x4, 16 ),
	WIND5 =						Message( 0x56, 0x5, 16 ),
	WIND6 =						Message( 0x56, 0x6, 16 ),
	WIND7 =						Message( 0x56, 0x7, 16 ),
	UV1 =						Message( 0x57, 0x1, 9 ),
	UV2 =						Message( 0x57, 0x2, 9 ),
	UV3 =						Message( 0x57, 0x3, 9 ),
	ELEC1 =						Message( 0x59, 0x1, 13 ),
	ELEC2 =						Message( 0x5A, 0x1, 17 ),
	ELEC3 =						Message( 0x5A, 0x2, 17 ),
	ELEC4 =						Message( 0x5B, 0x1, 19 ),
	WEIGHT1 =					Message( 0x5D, 0x1, 8 ),
	WEIGHT2 =					Message( 0x5D, 0x2, 8 ),
	RFXSENSOR_T =				Message( 0x70, 0x0, 7 ),
	RFXMETER =					Message( 0x71, 0x0, 10 )
}

-- Define a class for commands to be processed
local DeviceCmd = class(function(a, altid, cmd, value, delay)
	a.altid = altid		-- the altid of the device to act on
	a.cmd = cmd			-- the Command object defining what to do. Most often this is a variable name
	a.value = value		-- the value data used by the command
	a.delay = delay		-- the delay amount for delayed message actions
end)

-- This table is initialized in deferredStartup
-- It is used to select a message type based on the length, type, and subtype
--  found in the received message.
local tableMsgSelect = {}

local DATA_MSG_RESET = string.char(0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
local DATA_MSG_GET_STATUS = string.char(2, 0, 0, 0, 0, 0, 0, 0, 0, 0)
local DATA_MSG_SAVE = string.char(6, 0, 0, 0, 0, 0, 0, 0, 0, 0)

-- This table keeps trace of messages sent by the plugin to the RFXtrx
-- Each entry is a table of 2 elements:
-- 1) sequence number of the message
-- 2) table of commands
local tableMsgSent = {}

-- A table to speed up searching for a command
-- Used by searchCommandsTable(cmd)
--local tableCommandByCmd = {}

-- A class for commands
local Command = class(function(a, name, deviceType, variable)
	a.name = name				-- Name of the command
	a.deviceType = deviceType	-- the device type it operates on
	a.variable = variable		-- the variable used or modified (may be nil)
end)

-- A class method to print a command class object
--local function Command:__tostring()
--	return("Command - name: " .. self.name .. " deviceType: " .. self.deviceType .. ' variable: ' .. self.variable or 'nil')
--end

-- The table defines all commands used by the plugin
-- Each command object (defined above)
-- 1) command (a string)
-- 2) type of the device to act on or create
-- 3) variable (can be nil for commands that don't require a value)
local tableCommandTypes = {
	CMD_ON = Command("On", "LIGHT", "VAR_LIGHT"),
	CMD_OFF = Command("Off", "LIGHT", "VAR_LIGHT"),
	CMD_OPEN = Command("Open", "COVER", nil),
	CMD_CLOSE = Command("Close", "COVER", nil),
	CMD_STOP = Command("Stop", "COVER", nil),
	CMD_DIM = Command("Dim", "DIMMER", "VAR_DIMMER"),
	CMD_PROGRAM = Command("Program", nil, nil),
	CMD_TEMP = Command("Temperature", "TEMP", "VAR_TEMP"),
	CMD_TEMPTABLE = Command("Temptable", "TEMP", "VAR_TEMPMAXMIN"),
	CMD_TEMPMAX24HR = Command("Tempmax24hr", "TEMP", "VAR_TEMPMAX24HR"),
	CMD_TEMPMIN24HR = Command("Tempmin24hr", "TEMP", "VAR_TEMPMIN24HR"),
	CMD_TEMPMAX = Command("Tempmax", "TEMP", "VAR_TEMPMAX"),
	CMD_TEMPMIN = Command("Tempmin", "TEMP", "VAR_TEMPMIN"),
	CMD_HUM = Command("Humidity", "HUM", "VAR_HUM"),
	CMD_HUMTABLE = Command("Humtable", "HUM", "VAR_HUMMAXMIN"),
	CMD_HUMMAX24HR = Command("Hummax24hr", "HUM", "VAR_HUMMAX24HR"),
	CMD_HUMMIN24HR = Command("Hummin24hr", "HUM", "VAR_HUMMIN24HR"),
	CMD_HUMMAX = Command("Hummax", "HUM", "VAR_HUMMAX"),
	CMD_HUMMIN = Command("Hummin", "HUM", "VAR_HUMMIN"),
	CMD_PRESSURE = Command("Pressure", "BARO", "VAR_PRESSURE"),
	CMD_FORECAST = Command("Forecast", "BARO", "VAR_FORECAST"),
	CMD_RAIN = Command("Rain", "RAIN", "VAR_RAIN"),
	CMD_RAIN24HRS = Command("Rain60Min", "RAIN", "VAR_RAIN24HRS"),
	CMD_RAINRATE = Command("RainRate", "RAIN", "VAR_RAINRATE"),
	CMD_RAINBYMINUTE = Command("Rainbyminute", "RAIN", "VAR_RAINBYMINUTE"),
	CMD_RAINBYHOUR = Command("Rainbyhour", "RAIN", "VAR_RAINBYHOUR"),
	CMD_RAINBYDAY = Command("Rainbyday", "RAIN", "VAR_RAINBYDAY"),
	CMD_RAINBYWEEK = Command("Rainbyweek", "RAIN", "VAR_RAINBYWEEK"),
	CMD_RAINBYMONTH = Command("Rainbymonth", "RAIN", "VAR_RAINBYMONTH"),
	CMD_CURRENTWEEK = Command("WeekNumber", "RAIN", "VAR_WEEKNUM"),
	CMD_DIRECTION = Command("Direction", "WIND", "VAR_DIRECTION"),
	CMD_WIND = Command("Speed", "WIND", "VAR_WIND"),
	CMD_GUST = Command("Gust", "WIND", "VAR_GUST"),
	CMD_UV = Command("UV", "UV", "VAR_UV"),
	CMD_WEIGHT = Command("Weight", "WEIGHT", "VAR_WEIGHT"),
	CMD_IMPEDANCE = Command("Impedance", "WEIGHT", "VAR_IMPEDANCE"),
	CMD_DOOR = Command("Door", "DOOR", "VAR_TRIPPED"),
	CMD_AUTOUNTRIP = Command("AutoUntrip", "DOOR", "VAR_AUTOUNTRIP"),
	CMD_MOTION = Command("Motion", "MOTION", "VAR_TRIPPED"),
	--	CMD_TAMPERED = Command("Door", "DOOR", "VAR_TAMPERED"),
	CMD_SMOKE = Command("Smoke", "SMOKE", "VAR_TRIPPED"),
	CMD_SMOKE_OFF = Command("SmokeOff", "SMOKE", nil),
	CMD_ARM_MODE = Command("ArmMode", "ALARM", "VAR_ARM_MODE"),
	CMD_ARM_MODE_NUM = Command("ArmModeNum", "ALARM", "VAR_ARM_MODE_NUM"),
	CMD_DETAILED_ARM_MODE = Command("DetailedArmMode", "ALARM", "VAR_DETAILED_ARM_MODE"),
	CMD_ALARM_SCENE_ON = Command("AlarmSceneOn", "ALARM", "VAR_SCENE_ON"),
	CMD_ALARM_SCENE_OFF = Command("AlarmSceneOff", "ALARM", "VAR_SCENE_OFF"),
	CMD_WATT = Command("Watt", "POWER", "VAR_WATT"),
	CMD_KWH = Command("kWh", "POWER", "VAR_KWH"),
	CMD_PULSEN = Command("Pulsen", "RFXMETER", "VAR_PULSEN"),
	CMD_OFFSET = Command("Offset", "RFXMETER", "VAR_OFFSET"),
	CMD_MULT = Command("MULT", "RFXMETER", "VAR_MULT"),
	CMD_BATTERY = Command("BatteryLevel", nil, "VAR_BATTERY_LEVEL"),
	CMD_STRENGTH = Command("CommStrength", nil, "VAR_COMM_STRENGTH"),
	CMD_SCENE_ON = Command("SceneOn", "REMOTE", "VAR_SCENE_ON"),
	CMD_SCENE_OFF = Command("SceneOff", "REMOTE", "VAR_SCENE_OFF"),
	CMD_LWRF_SCENE_ON = Command("LWRFSceneOn", "LWRF_REMOTE", "VAR_SCENE_ON"),
	CMD_LWRF_SCENE_OFF = Command("LWRFSceneOff", "LWRF_REMOTE", "VAR_SCENE_OFF"),
	CMD_ATI_SCENE_ON = Command("ATISceneOn", "ATI_REMOTE", "VAR_SCENE_ON"),
	CMD_ATI_SCENE_OFF = Command("ATISceneOff", "ATI_REMOTE", "VAR_SCENE_OFF"),
	CMD_HEATER = Command("Heater", "HEATER", "VAR_HEATER"),
	CMD_HEATER_SW = Command("HeaterSwitch", "HEATER", "VAR_HEATER_SW"),
	CMD_HEATER_UP = Command("HeaterUp", "HEATER", nil),
	CMD_HEATER_DOWN = Command("HeaterDown", "HEATER", nil)
}

-- Define a class for variables
local Variable = class(function(a, serviceId, name, isBoolean, isAdjustable, onlySaveChanged)
	a.serviceId = serviceId					-- the service ID in the device service file
	a.name = name							-- the variable name in the device service file
	a.isBoolean = isBoolean					-- treat as a boolean variable
	a.isAdjustable = isAdjustable			-- is adjustable using multipliers and/or offsets
	a.onlySaveChanged = onlySaveChanged		-- is only saved if different from current value
end)

-- This table defines all device variables that are used by the plugin
-- Each entry is a table of 4 elements:
-- 1) the service ID
-- 2) the variable name
-- 3) true if the variable is of type boolean
-- 4) true if the variable can be adjusted (through value in AdjustConstant variable)
-- 5) true if the variable is not updated when the value is unchanged
local tabVars = {
	VAR_TEMP = Variable( "urn:upnp-org:serviceId:TemperatureSensor1", "CurrentTemperature", false, true, true ),
	VAR_TEMPMAX24HR = Variable( "urn:upnp-org:serviceId:TemperatureSensor1", "MaxTemp24hr", false, true, true ),
	VAR_TEMPMIN24HR = Variable( "urn:upnp-org:serviceId:TemperatureSensor1", "MinTemp24hr", false, true, true ),
	VAR_TEMPMAXMIN = Variable( "urn:upnp-org:serviceId:TemperatureSensor1", "MaxMinTemps", false, false, true ),
	VAR_TEMPMAX = Variable( "urn:upnp-org:serviceId:TemperatureSensor1", "MaxTemp", false, true, true ),
	VAR_TEMPMIN = Variable( "urn:upnp-org:serviceId:TemperatureSensor1", "MinTemp", false, true, true ),
	VAR_HUM = Variable( "urn:micasaverde-com:serviceId:HumiditySensor1", "CurrentLevel", false, true, true ),
	VAR_HUMMAX24HR = Variable( "urn:micasaverde-com:serviceId:HumiditySensor1", "MaxHum24hr", false, true, true ),
	VAR_HUMMIN24HR = Variable( "urn:micasaverde-com:serviceId:HumiditySensor1", "MinHum24hr", false, true, true ),
	VAR_HUMMAXMIN = Variable( "urn:micasaverde-com:serviceId:HumiditySensor1", "MaxMinHum", false, false, true ),
	VAR_HUMMAX = Variable( "urn:micasaverde-com:serviceId:HumiditySensor1", "MaxHum", false, true, true ),
	VAR_HUMMIN = Variable( "urn:micasaverde-com:serviceId:HumiditySensor1", "MinHum", false, true, true ),
	VAR_LIGHT = Variable( "urn:upnp-org:serviceId:SwitchPower1", "Status", false, false, true ),
	VAR_DIMMER = Variable( "urn:upnp-org:serviceId:Dimming1", "LoadLevelStatus", false, false, true ),
	VAR_PRESSURE = Variable( "urn:upnp-org:serviceId:BarometerSensor1", "CurrentPressure", false, true, true ),
	VAR_FORECAST = Variable( "urn:upnp-org:serviceId:BarometerSensor1", "Forecast", false, false, true ),
	VAR_RAIN = Variable( "urn:upnp-org:serviceId:RainSensor1", "CurrentTRain", false, false, true ),
	VAR_RAIN24HRS = Variable( "urn:upnp-org:serviceId:RainSensor1", "Rain24Hrs", false, false, false ),
	VAR_RAINRATE = Variable( "urn:upnp-org:serviceId:RainSensor1", "CurrentRain", false, false, true ),
	VAR_WEEKNUM = Variable( "urn:upnp-org:serviceId:RainSensor1", "WeekNumber", false, false, false ),
	VAR_RAINBYMINUTE = Variable( "urn:upnp-org:serviceId:RainSensor1", "MinuteRain", false, false, true ),
	VAR_RAINBYHOUR = Variable( "urn:upnp-org:serviceId:RainSensor1", "HourlyRain", false, false, true ),
	VAR_RAINBYDAY = Variable( "urn:upnp-org:serviceId:RainSensor1", "DailyRain", false, false, true ),
	VAR_RAINBYWEEK = Variable( "urn:upnp-org:serviceId:RainSensor1", "WeeklyRain", false, false, true ),
	VAR_RAINBYMONTH = Variable( "urn:upnp-org:serviceId:RainSensor1", "MonthlyRain", false, false, true ),
	VAR_WIND = Variable( "urn:upnp-org:serviceId:WindSensor1", "AvgSpeed", false, false, true ),
	VAR_GUST = Variable( "urn:upnp-org:serviceId:WindSensor1", "GustSpeed", false, false, true ),
	VAR_DIRECTION = Variable( "urn:upnp-org:serviceId:WindSensor1", "Direction", false, false, true ),
	VAR_UV = Variable( "urn:upnp-org:serviceId:UvSensor1", "CurrentLevel", false, true, true ),
	VAR_WEIGHT = Variable( "urn:micasaverde-com:serviceId:ScaleSensor1", "Weight", false, false, true ),
	VAR_IMPEDANCE = Variable( "urn:micasaverde-com:serviceId:ScaleSensor1", "Impedance", false, false, true ),
	VAR_BATTERY_LEVEL = Variable( "urn:micasaverde-com:serviceId:HaDevice1", "BatteryLevel", false, false, true ),
	VAR_BATTERY_DATE = Variable( "urn:micasaverde-com:serviceId:HaDevice1", "BatteryDate", false, false, true ),
	VAR_IO_DEVICE = Variable( "urn:micasaverde-com:serviceId:HaDevice1", "IODevice", false, false, true ),
	VAR_BAUD = Variable( "urn:micasaverde-org:serviceId:SerialPort1", "baud", false, false, true ),
	VAR_ARMED = Variable( "urn:micasaverde-com:serviceId:SecuritySensor1", "Armed", true, false, true ),
	VAR_TRIPPED = Variable( "urn:micasaverde-com:serviceId:SecuritySensor1", "Tripped", true, false, false ),
	VAR_ARMEDTRIPPED = Variable( "urn:micasaverde-com:serviceId:SecuritySensor1", "ArmedTripped", true, false, false ),
	VAR_LAST_TRIP = Variable( "urn:micasaverde-com:serviceId:SecuritySensor1", "LastTrip", false, false, true ),
	VAR_AUTOUNTRIP = Variable( "urn:micasaverde-com:serviceId:SecuritySensor1", "AutoUntrip", false, false, false ),
	VAR_ARM_MODE = Variable( "urn:micasaverde-com:serviceId:AlarmPartition2", "ArmMode", false, false, true ),
	VAR_ARM_MODE_NUM = Variable( "urn:rfxcom-com:serviceId:SecurityRemote1", "ArmModeNum", false, false, true ),
	VAR_DETAILED_ARM_MODE = Variable( "urn:micasaverde-com:serviceId:AlarmPartition2", "DetailedArmMode", false, false, true ),
	--	VAR_TAMPERED = Variable( "urn:micasaverde-com:serviceId:HaDevice1", "sl_TamperAlarm", true, false, true ),
	VAR_WATT = Variable( "urn:micasaverde-com:serviceId:EnergyMetering1", "Watts", false, false, true ),
	VAR_KWH = Variable( "urn:micasaverde-com:serviceId:EnergyMetering1", "KWH", false, false, true ),
	VAR_SCENE_ON = Variable( "urn:micasaverde-com:serviceId:SceneController1", "sl_SceneActivated", false, false, false ),
	VAR_SCENE_OFF = Variable( "urn:micasaverde-com:serviceId:SceneController1", "sl_SceneDeactivated", false, false, false ),
	VAR_EXIT_DELAY = Variable( "urn:rfxcom-com:serviceId:SecurityRemote1", "ExitDelay", false, false, true ),
	VAR_HEATER = Variable( "urn:upnp-org:serviceId:HVAC_UserOperatingMode1", "ModeStatus", false, false, true ),
	VAR_HEATER_SW = Variable( "urn:upnp-org:serviceId:SwitchPower1", "Status", false, false, true ),
	--VAR_HEATER_HA = Variable( "urn:micasaverde-com:serviceId:HaDevice1", "Status", false, false, true ),
	VAR_PULSEN = Variable( "urn:delanghe-com:serviceId:RFXMetering1", "Pulsen", false, false, true ),
	VAR_OFFSET = Variable( "urn:delanghe-com:serviceId:RFXMetering1", "Offset", false, false, true ),
	VAR_MULT = Variable( "urn:delanghe-com:serviceId:RFXMetering1", "Mult", false, false, true ),
	VAR_LIGHT_LEVEL = Variable( "urn:micasaverde-com:serviceId:LightSensor1", "CurrentLevel", false, false, true ),
	VAR_STATE = Variable( "urn:upnp-org:serviceId:SwitchPower1", "Status", false, false, true ),
	VAR_COMM_FAILURE = Variable( "urn:micasaverde-com:serviceId:HaDevice1", "CommFailure", false, false, true ),
	VAR_COMM_STRENGTH = Variable( "urn:micasaverde-com:serviceId:HaDevice1", "CommStrength", false, false, true ),

	VAR_PLUGIN_VERSION = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "PluginVersion", false, false, true ),
	VAR_AUTO_CREATE = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "AutoCreate", true, false, true ),
	VAR_DISABLED_DEVICES = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "DisabledDevices", false, false, true ),
	VAR_FIRMWARE_VERSION = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "FirmwareVersion", false, false, true ),
	VAR_FIRMWARE_TYPE = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "FirmwareType", false, false, true ),
	VAR_HARDWARE_VERSION = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "HardwareVersion", false, false, true ),
	VAR_TEMP_UNIT = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "CelciusTemp", true, false, true ),
	VAR_LENGTH_UNIT = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "MMLength", true, false, true ),
	VAR_SPEED_UNIT = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "KmhSpeed", true, false, true ),
	VAR_VOLTAGE = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "Voltage", false, false, true ),
	VAR_VERATIME = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "VeraTime", false, false, false ),
	VAR_VERAPORT = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "IPPort", false, false, true ),
	VAR_BYRONSX_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "ByronSXReceiving", true, false, true ),
	VAR_RSL_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "RSLReceiving", true, false, true ),
	VAR_UNDECODED_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "UndecodedReceiving", true, false, true ),
	VAR_IMAGINTRONIX_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "ImagintronixReceiving", true, false, true ),
	VAR_KEELOQ_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "KeeloqReceiving", true, false, true ),
	VAR_HOMECONFORT_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "HomeconfortReceiving", true, false, true ),
	VAR_LIGHTING4_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "Lighting4Receiving", true, false, true ),
	VAR_FINEOFFSET_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "FineOffsetReceiving", true, false, true ),
	VAR_RUBICSON_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "RubicsonReceiving", true, false, true ),
	VAR_AE_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "AEReceiving", true, false, true ),
	VAR_BLINDST1_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "BlindsT1Receiving", true, false, true ),
	VAR_BLINDST0_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "BlindsT0Receiving", true, false, true ),
	VAR_PROGUARD_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "ProGuardReceiving", true, false, true ),
	VAR_FS20_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "FS20Receiving", true, false, true ),
	VAR_LACROSSE_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "LaCrosseReceiving", true, false, true ),
	VAR_HIDEKI_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "HidekiReceiving", true, false, true ),
	VAR_AD_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "ADReceiving", true, false, true ),
	VAR_MERTIK_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "MertikReceiving", true, false, true ),
	VAR_VISONIC_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "VisonicReceiving", true, false, true ),
	VAR_ATI_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "ATIReceiving", true, false, true ),
	VAR_OREGON_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "OregonReceiving", true, false, true ),
	VAR_MEIANTECH_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "MeiantechReceiving", true, false, true ),
	VAR_HEU_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "HEUReceiving", true, false, true ),
	VAR_AC_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "ACReceiving", true, false, true ),
	VAR_ARC_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "ARCReceiving", true, false, true ),
	VAR_X10_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "X10Receiving", true, false, true ),
	VAR_ASSOCIATION = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "Association", false, false, true ),
	VAR_LAST_RECEIVED_MSG = Variable( "urn:rfxcom-com:serviceId:rfxtrx1", "LastReceivedMsg", false, false, true ),
	VAR_ADJUST_MULTIPLIER = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "AdjustMultiplier", false, false, true ),
	VAR_ADJUST_CONSTANT = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "AdjustConstant", false, false, true ),
	VAR_ADJUST_CONSTANT2 = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "AdjustConstant2", false, false, true ),
	VAR_REPEAT_EVENT = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "RepeatEvent", false, false, true ),
	VAR_NBR_DEVICES = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "NbrDevices", false, false, true ),
	VAR_DEBUG_LOGS = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "DebugLogs", true, false, true ),
	VAR_RFY_MODE = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "RFYMode", false, false, true )
}

-- Define a class for devices
local Device = class(function(a, deviceType, deviceFile, name, prefix, hasAssociation, hasMode, hasAdjustments, jsDeviceType)
	a.deviceType = deviceType			-- the upnp device type
	a.deviceFile = deviceFile			-- the upnp device definition file D_<device>.xml
	a.name = name						-- the device name
	a.prefix = prefix					-- a prefix for the altid
	a.hasAssociation = hasAssociation	-- used to enable device conversions
	a.hasMode = hasMode					-- used to allow setting device modes
	a.hasAdjustments = hasAdjustments	-- on device creation, creates offset and multiplier variables
	a.jsDeviceType = jsDeviceType		-- the device type sent from the js file
end)

-- This table defines all kinds of child that can be managed by the plugin
-- Each entry is a table of 7 elements:
-- 1) device type (URN)
-- 2) XML description file
-- 3) Prefix for the device name
-- 4) Prefix for the device id
-- 5) a boolean indicating if variable "Association" must be created for this device type
-- 6) a boolean indicating if variable "RFYMode" must be created for this device type
-- 7) a boolean indicating if variables "AdjustMultiplier" and "AdjustConstant" must be created for this device type
local tableDeviceTypes = {
	DOOR = Device("urn:schemas-micasaverde-com:device:DoorSensor:1", "D_DoorSensor1.xml", "RFX Door ", "DS/", false, false, false, "DOOR_SENSOR" ),
	MOTION = Device("urn:schemas-micasaverde-com:device:MotionSensor:1", "D_MotionSensor1.xml", "RFX Motion ", "MS/", false, false, false, "MOTION_SENSOR" ),
	SMOKE = Device("urn:schemas-micasaverde-com:device:SmokeSensor:1", "D_SmokeSensor1.xml", "RFX Smoke ", "SS/", false, false, false, nil ),
	LIGHT = Device("urn:schemas-upnp-org:device:BinaryLight:1", "D_BinaryLight1.xml", "RFX Light ", "LS/", true, false, false, "SWITCH_LIGHT" ),
	DIMMER = Device("urn:schemas-upnp-org:device:DimmableLight:1", "D_DimmableLight1.xml", "RFX dim Light ", "DL/", true, false, false, "DIMMABLE_LIGHT" ),
	COVER = Device("urn:schemas-micasaverde-com:device:WindowCovering:1", "D_WindowCovering1.xml", "RFX Window ", "WC/", true, true, false, "WINDOW_COVERING" ),
	TEMP = Device("urn:schemas-micasaverde-com:device:TemperatureSensor:1", "D_TemperatureSensor1.xml", "RFX Temp ", "TS/", false, false, true, nil ),
	HUM = Device("urn:schemas-micasaverde-com:device:HumiditySensor:1", "D_HumiditySensor1.xml", "RFX Hum ", "HS/", false, false, true, nil ),
	BARO = Device("urn:schemas-micasaverde-com:device:BarometerSensor:1", "D_BarometerSensor1.xml", "RFX Baro ", "BS/", false, false, true, nil ),
	WIND = Device("urn:schemas-micasaverde-com:device:WindSensor:1", "D_WindSensor1.xml", "RFX Wind ", "WS/", false, false, false, nil ),
	RAIN = Device("urn:schemas-micasaverde-com:device:RainSensor:1", "D_RainSensor1.xml", "RFX Rain ", "RS/", false, false, false, nil ),
	UV = Device("urn:schemas-micasaverde-com:device:UvSensor:1", "D_UvSensor1.xml", "RFX UV ", "UV/", false, false, true, nil ),
	WEIGHT = Device("urn:schemas-micasaverde-com:device:ScaleSensor:1", "D_ScaleSensor1.xml", "RFX Weight ", "WT/", false, false, false, nil ),
	POWER = Device("urn:schemas-micasaverde-com:device:PowerMeter:1", "D_PowerMeter1.xml", "RFX Power ", "PM/", false, false, false, nil ),
	RFXMETER = Device("urn:casa-delanghe-com:device:RFXMeter:1", "D_RFXMeter1.xml", "RFX Meter ", "RM/", false, false, false, nil ),
	ALARM = Device("urn:rfxcom-com:device:SecurityRemote:1", "D_SecurityRemote1.xml", "RFX Remote ", "SR/", false, false, false, nil ),
	REMOTE = Device("urn:rfxcom-com:device:X10ChaconRemote:1", "D_X10ChaconRemote1.xml", "RFX Remote ", "RC/", false, false, false, nil ),
	LWRF_REMOTE = Device("urn:rfxcom-com:device:LWRFRemote:1", "D_LWRFRemote1.xml", "RFX Remote ", "RC/", false, false, false, nil ),
	ATI_REMOTE = Device("urn:rfxcom-com:device:ATIRemote:1", "D_ATIRemote1.xml", "RFX Remote ", "RC/", false, false, false, nil ),
	HEATER = Device("urn:schemas-upnp-org:device:Heater:1", "D_Heater1.xml", "RFX Heater ", "HT/", false, false, false, nil ),
	LIGHT_LEVEL = Device("urn:schemas-micasaverde-com:device:LightSensor:1", "D_LightSensor1.xml", "RFX Light level ", "LL/", false, false, false, "LIGHT_SENSOR" ),
	SWITCH_TOGGLE = Device("urn:rfxcom-com:device:SwitchToggle:1", "D_SwitchToggle1.xml", "RFX Toggle Switch ", "L4/", false, false, false, "SWITCH_TOGGLE" )
}

-- Scene controller - scene number
-- ON/OFF (activated/deactivated): 1-16
-- SET LEVEL (activated only): 17-32
-- LOCK/UNLOCK (activated/deactivated): 33-48
-- OPEN (activated only): 49-64
-- CLOSE (activated only): 65-80
-- STOP (activated only): 81-96
-- GROUP ON/OFF (activated/deactivated): 100
-- GROUP LEVEL (activated only): 101
-- DIM (activated only): 102
-- BRIGHT (activated only): 103
-- ALL LOCK (activated only): 105
-- MOOD1 (activated only): 111
-- MOOD2 (activated only): 112
-- MOOD3 (activated only): 113
-- MOOD4 (activated only): 114
-- MOOD5 (activated only): 115
-- PANIC/END PANIC (activated/deactivated): 120
-- ARM AWAY (activated only): 121
-- ARM HOME (activated only): 122
-- DISARM (activated only): 123
-- PAIR (KD101/SA30) (activated only): 124
-- CHIME (activated only): 131-146


local tableCategories = {
	X10 = {	"X10 lighting", true, false, true, false, true, false,
		false, nil, nil,
		true, 0x41, 0x50,
		false, nil, nil,
		true, 1, 16,
		false, nil, nil,
		false, nil, nil,
	"L1.0/", "%s%s%02d", "REMOTE", "%s%s", nil, nil	},
	ARC = {	"ARC", true, false, true, true, false, false,
		false, nil, nil,
		true, 0x41, 0x50,
		false, nil, nil,
		true, 1, 16,
		false, nil, nil,
		false, nil, nil,
	"L1.1/", "%s%s%02d", "REMOTE", "%s%s", nil, nil	},
	ELRO_AB400D = {	"ELRO AB400D, Flamingo, Sartano", true, false, false, false, false, false,
		false, nil, nil,
		true, 0x41, 0x50,
		false, nil, nil,
		true, 1, 64,
		false, nil, nil,
		false, nil, nil,
	"L1.2/", "%s%s%02d", nil, nil, nil, nil	},
	PHENIX = {	"Phenix", true, false, false, false, false, false,
		false, nil, nil,
		true, 0x41, 0x50,
		false, nil, nil,
		true, 1, 32,
		false, nil, nil,
		false, nil, nil,
	"L1.2/", "%s%s%02d", nil, nil, nil, nil	},
	WAVEMAN = {	"Waveman", true, false, false, false, false, false,
		false, nil, nil,
		true, 0x41, 0x50,
		false, nil, nil,
		true, 1, 16,
		false, nil, nil,
		false, nil, nil,
	"L1.3/", "%s%s%02d", nil, nil, nil, nil	},
	EMW200 = {	"Chacon EMW200", true, false, false, false, false, false,
		false, nil, nil,
		true, 0x41, 0x43,
		false, nil, nil,
		true, 1, 4,
		false, nil, nil,
		false, nil, nil,
	"L1.4/", "%s%s%02d", nil, nil, nil, nil	},
	IMPULS = {	"Impuls", true, false, false, false, false, false,
		false, nil, nil,
		true, 0x41, 0x50,
		false, nil, nil,
		true, 1, 64,
		false, nil, nil,
		false, nil, nil,
	"L1.5/", "%s%s%02d", nil, nil, nil, nil	},
	RISINGSUN = {	"RisingSun", true, false, false, false, false, false,
		false, nil, nil,
		true, 0x41, 0x44,
		false, nil, nil,
		true, 1, 4,
		false, nil, nil,
		false, nil, nil,
	"L1.6/", "%s%s%02d", nil, nil, nil, nil	},
	PHILIPS_SBC = {	"Philips SBC", true, false, false, false, false, false,
		false, nil, nil,
		true, 0x41, 0x50,
		false, nil, nil,
		true, 1, 8,
		false, nil, nil,
		false, nil, nil,
	"L1.7/", "%s%s%02d", "REMOTE", "%s%s", nil, nil	},
	ENERGENIE_ENER010 = {	"Energenie ENER010", true, false, false, false, false, false,
		false, nil, nil,
		true, 0x41, 0x50,
		false, nil, nil,
		true, 1, 4,
		false, nil, nil,
		false, nil, nil,
	"L1.8/", "%s%s%02d", "REMOTE", "%s%s", nil, nil	},
	ENERGENIE_5GANG = {	"Energenie 5 gang", true, false, false, false, false, false,
		false, nil, nil,
		true, 0x41, 0x50,
		false, nil, nil,
		true, 1, 10,
		false, nil, nil,
		false, nil, nil,
	"L1.9/", "%s%s%02d", nil, nil, nil, nil	},
	COCO = {	"COCO GDR2-2000R", true, false, false, false, false, false,
		false, nil, nil,
		true, 0x41, 0x44,
		false, nil, nil,
		true, 1, 4,
		false, nil, nil,
		false, nil, nil,
	"L1.A/", "%s%s%02d", nil, nil, nil, nil	},
	AC = {	"AC", true, true, true, true, true, true,
		true, 1, 0x3FFFFFF,
		false, nil, nil,
		false, nil, nil,
		true, 1, 16,
		false, nil, nil,
		false, nil, nil,
	"L2.0/", "%s%07X/%02d", "REMOTE", "%s%07X", nil, nil	},
	HOMEEASY_EU = {	"HomeEasy EU", true, true, false, false, false, false,
		true, 1, 0x3FFFFFF,
		false, nil, nil,
		false, nil, nil,
		true, 1, 16,
		false, nil, nil,
		false, nil, nil,
	"L2.1/", "%s%07X/%02d", "REMOTE", "%s%07X", nil, nil	},
	ANSLUT = {	"ANSLUT", true, true, false, false, false, false,
		true, 1, 0x3FFFFFF,
		false, nil, nil,
		false, nil, nil,
		true, 1, 16,
		false, nil, nil,
		false, nil, nil,
	"L2.2/", "%s%07X/%02d", "REMOTE", "%s%07X", nil, nil	},
	IKEA_KOPPLA = {	"Ikea Koppla", true, false, false, false, false, false,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
		true, 1, 16,
		true, 1, 10,
	"L3.0/", "%s%X%02d", nil, nil, nil, nil	},
	LIGHTWAVERF_SIEMENS = {	"LightwaveRF, Siemens", true, true, true, true, false, true,
		true, 1, 0xFFFFFF,
		false, nil, nil,
		false, nil, nil,
		true, 1, 16,
		false, nil, nil,
		false, nil, nil,
	"L5.0/", "%s%06X/%02d", "LWRF_REMOTE", "%s%06X", nil, nil	},
	EMW100 = {	"GAO/Everflourish EMW100", true, false, false, false, false, false,
		true, 1, 0x3FFF,
		false, nil, nil,
		false, nil, nil,
		true, 1, 4,
		false, nil, nil,
		false, nil, nil,
	"L5.1/", "%s%06X/%02d", nil, nil, nil, nil	},
	BBSB = {	"Bye Bye Standby (new)", true, false, false, false, false, false,
		true, 1, 0x7FFFF,
		false, nil, nil,
		false, nil, nil,
		true, 1, 6,
		false, nil, nil,
		false, nil, nil,
	"L5.2/", "%s%06X/%02d", "REMOTE", "%s%06X", nil, nil	},
	RSL2 = {	"Conrad RSL2", true, false, false, false, false, false,
		true, 1, 0xFFFFFF,
		false, nil, nil,
		false, nil, nil,
		true, 1, 16,
		false, nil, nil,
		false, nil, nil,
	"L5.4/", "%s%06X/%02d", "REMOTE", "%s%06X", nil, nil	},
	LIVOLO_1GANG = {	"Livolo (1 gang)", true, true, false, false, false, false,
		true, 1, 0xFFFF,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
	"L5.5/", "%s%06X/1", nil, nil, nil, nil	},
	LIVOLO_2GANG = {	"Livolo (2 gang)", true, false, false, false, false, false,
		true, 1, 0xFFFF,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
	"L5.5/", "%s%06X/1", "LIGHT", "%s%06X/2", nil, nil	},
	LIVOLO_3GANG = {	"Livolo (3 gang)", true, false, false, false, false, false,
		true, 1, 0xFFFF,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
	"L5.5/", "%s%06X/1", "LIGHT", "%s%06X/2", "LIGHT", "%s%06X/3"	},
	BLYSS = {	"Blyss", true, false, true, true, false, false,
		true, 0, 0xFFFF,
		false, nil, nil,
		true, 0x41, 0x50,
		true, 1, 5,
		false, nil, nil,
		false, nil, nil,
	"L6.0/", "%s%04X/%s%d", "REMOTE", "%s%04X/%s", nil, nil	},
	HARRISON_CURTAIN = {	"Harrison Curtain", false, false, false, false, false, true,
		false, nil, nil,
		true, 0x41, 0x50,
		false, nil, nil,
		true, 1, 16,
		false, nil, nil,
		false, nil, nil,
	"C0/", "%s%s%02d", nil, nil, nil, nil	},
	ROLLERTROL = {	"RollerTrol", false, false, false, false, false, true,
		true, 1, 0xFFFF,
		false, nil, nil,
		false, nil, nil,
		true, 0, 15,
		false, nil, nil,
		false, nil, nil,
	"B0/", "%s%06X/%02d", nil, nil, nil, nil	},
	HASTA_NEW = {	"Hasta (new)", false, false, false, false, false, true,
		true, 1, 0xFFFF,
		false, nil, nil,
		false, nil, nil,
		true, 0, 15,
		false, nil, nil,
		false, nil, nil,
	"B0/", "%s%06X/%02d", nil, nil, nil, nil	},
	HASTA_OLD = {	"Hasta (old)", false, false, false, false, false, true,
		true, 1, 0xFFFF,
		false, nil, nil,
		false, nil, nil,
		true, 0, 15,
		false, nil, nil,
		false, nil, nil,
	"B1/", "%s%06X/%02d", nil, nil, nil, nil	},
	A_OK_RF01 = {	"A-OK RF01", false, false, false, false, false, true,
		true, 1, 0xFFFFFF,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
	"B2/", "%s%06X/00", nil, nil, nil, nil	},
	A_OK_AC114 = {	"A-OK AC114", false, false, false, false, false, true,
		true, 1, 0xFFFFFF,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
	"B3/", "%s%06X/00", nil, nil, nil, nil	},
	RAEX = {	"Raex YR1326 T16 motor", false, false, false, false, false, true,
		true, 1, 0xFFFFFF,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
	"B4/", "%s%06X/00", nil, nil, nil, nil	},
	MEDIA_MOUNT = {	"Media Mount projector screen", false, false, false, false, false, true,
		true, 1, 0xFFFFFF,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
	"B5/", "%s%06X/00", nil, nil, nil, nil	},
	DC_RMF_YOODA = {	"DC106, YOODA, Rohrmotor24 RMF", false, false, false, false, false, true,
		true, 1, 0x0FFFFFFF,
		false, nil, nil,
		false, nil, nil,
		true, 0, 15,
		false, nil, nil,
		false, nil, nil,
	"B6/", "%s%07X/%02d", nil, nil, nil, nil	},
	FOREST = {	"Forest", false, false, false, false, false, true,
		true, 1, 0x0FFFFFFF,
		false, nil, nil,
		false, nil, nil,
		true, 0, 15,
		false, nil, nil,
		false, nil, nil,
	"B7/", "%s%07X/%02d", nil, nil, nil, nil	},
	RFY = {	"RFY", false, false, false, false, false, true,
		true, 1, 0x0FFFFF,
		false, nil, nil,
		false, nil, nil,
		true, 0, 4,
		false, nil, nil,
		false, nil, nil,
	"RFY0/", "%s%05X/%02d", nil, nil, nil, nil	},
	SONOFF = {	"Sonoff Smart Switch", true, false, false, false, false, false,
		true, 1, 0xFFFFFF,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
		false, nil, nil,
	"L4/", "%s%06X/00", nil, nil, nil, nil	}
}

-- A table used to find the device ID number using the AltId
-- This table is initialized in deferredStartup and after devices
-- are added or deleted.
local devicedIdNumByAltId = {}

-- A table used to speed up searching for a child device
-- Used by findChild(parentDevice, altid, deviceType)
local tableDeviceNumByAltidAndType  = {}


-- This table stores all children
-- Each entry is a table of 4 elements:
-- 1) device ID (altid)
-- 2) a key in the table tableDeviceTypes
-- 3) the associations (value of variable "Association")
-- 4) device name
local tableDevices = {}

local DEBUG_MODE = false


local function log(text, level)
	luup.log("RFXtrx: " .. text, (level or 50))
end

local function warning(stuff)
	log("warning: " .. stuff, 2)
end

local function error(stuff)
	log("error: " .. stuff, 1)
end

local function debug(stuff)
	if (DEBUG_MODE) then
		log("dbg: " .. stuff)
	end
end

local function tableSize(theTable)
	local count = 0
	for i, v in ipairs(theTable) do
		count = count + 1
	end
	return count
end


local function task(text, mode)
	if (mode == TASK_ERROR_PERM)
		then
		log(text, 1)
	elseif (mode ~= TASK_SUCCESS)
		then
		log(text, 2)
	else
		log(text)
	end
	if (mode == TASK_ERROR_PERM)
		then
		taskHandle = luup.task(text, TASK_ERROR, "RFXtrx", taskHandle)
	else
		taskHandle = luup.task(text, mode, "RFXtrx", taskHandle)

		-- Clear the previous error, since they're all transient
		if (mode ~= TASK_SUCCESS)
			then
			luup.call_delay("clearTask", 15, "", false)
		end
	end
end

function clearTask()
	task("Clearing...", TASK_SUCCESS)
end

-- Helper function to get a substring that can handle null chars
-- Code from RFXCOM plugin
local function getStringPart( psString, piStart, piLen )
	local lsResult = ""

	if ( psString ~= nil )
		then
		local liStringLength = 1 + #psString
		for teller = piStart, (piStart + piLen - 1)
			do
			-- if not beyond string length
			if ( liStringLength > teller )
				then
				lsResult = lsResult .. string.sub(psString, teller, teller)
			end
		end
	end

	return lsResult
end

local function formattohex(dataBuf)

	local resultstr = ""
	if (dataBuf ~= nil)
		then
		for idx = 1, string.len(dataBuf)
			do
			resultstr = resultstr .. string.format("%02X ", string.byte(dataBuf, idx) )
		end
	end
	return resultstr

end

local function searchInStringTable(table, value)

	local idx = 0
	for i, v in ipairs(table)
		do
		if (v == value)
			then
			idx = i
			break
		end
	end
	return idx

end

local function searchInTable(table, searchIndex, value)

	local idx = 0
	for i, v in ipairs(table)
		do
		if (v[searchIndex] == value)
			then
			idx = i
			break
		end
	end
	return idx

end

local function searchInTable2(table, searchIndex1, value1, searchIndex2, value2)

	local idx = 0
	for i, v in ipairs(table)
		do
		if (v[searchIndex1] == value1 and v[searchIndex2] == value2)
			then
			idx = i
			break
		end
	end
	return idx

end

local function searchInKeyTable(table, value1, value2)

	local key = nil
	for k, v in pairs(table)
		do
		if (v.deviceType == value1 and v.prefix == value2)
			then
			key = k
			break
		end
	end
	return key

end

local function getVariable(deviceNum, variable)
	local value = nil
	if (variable ~= nil)
		then
		value = luup.variable_get(variable.serviceId, variable.name, deviceNum)
		if(variable.isBoolean)
			then
			if(value == "0")
				then value = false
			elseif(value == "1")
				then value = true
			end
		end
	end
	return value
end

local function setDefaultValue(deviceNum, variable, value)
	if (variable ~= nil and value ~= nil)
		then
		local currentValue = luup.variable_get(variable.serviceId, variable.name, deviceNum)
		if(currentValue == nil) then
			debug("SET " .. variable.name .. " with default value " .. value)
			luup.variable_set(variable.serviceId, variable.name, value, deviceNum)
		end
	end
end

local function setVariable(deviceNum, variable, value)
	if (variable ~= nil and value ~= nil)
		then
		if (type(value) == "number")
			then
			value = tostring(value)
		end
		local doChange = true
		local currentValue = getVariable(deviceNum, variable)
		if ((luup.devices[deviceNum].device_type == tableDeviceTypes.MOTION.deviceType
			or luup.devices[deviceNum].device_type == tableDeviceTypes.DOOR.deviceType
			or luup.devices[deviceNum].device_type == tableDeviceTypes.SMOKE.deviceType)
			and variable == tabVars.VAR_TRIPPED
			and currentValue == value
			and getVariable(deviceNum, tabVars.VAR_REPEAT_EVENT) == "0")
			then
			doChange = false
		elseif (luup.devices[deviceNum].device_type == tableDeviceTypes.LIGHT.deviceType
			and variable == tabVars.VAR_LIGHT
			and currentValue == value
			and getVariable(deviceNum, tabVars.VAR_REPEAT_EVENT) == "1")
			then
			luup.variable_set(variable.serviceId, variable.name, -1, deviceNum)
		elseif (currentValue ~= nil and currentValue == value
			and variable.onlySaveChanged)
			then
			doChange = false
		end
		if (doChange) then
			if(variable.isBoolean)
				then
				if(value)
					then value = "1"
					else value = "0"
				end
			end
			luup.variable_set(variable.serviceId, variable.name, value, deviceNum)
		end

		if (variable == tabVars.VAR_TRIPPED and value == "1")
			then
			setVariable(deviceNum, tabVars.VAR_LAST_TRIP, os.time())
		elseif (variable == tabVars.VAR_BATTERY_LEVEL)
			then
			setVariable(deviceNum, tabVars.VAR_BATTERY_DATE, os.time())
		end
	end
end

local function initIDLookup()

	devicedIdNumByAltId = {}
	-- Build a table for selecting the device ID based on the altid
	for deviceNum, veraDevice in pairs(luup.devices) do
		debug("device: "..deviceNum)
		if (deviceNum == THIS_DEVICE) then
			devicedIdNumByAltId["RFXTRX"] = THIS_DEVICE
		elseif (veraDevice.device_num_parent == THIS_DEVICE) then
			devicedIdNumByAltId[string.sub(veraDevice.id, 4, #veraDevice.id)] = deviceNum
		end
	end

end

local function initStateVariables()
	-- Must use 0 or 1 for booleans here
	setDefaultValue(THIS_DEVICE, tabVars.VAR_AUTO_CREATE, "0")
	setDefaultValue(THIS_DEVICE, tabVars.VAR_TEMP_UNIT, "1")
	setDefaultValue(THIS_DEVICE, tabVars.VAR_LENGTH_UNIT, "1")
	setDefaultValue(THIS_DEVICE, tabVars.VAR_SPEED_UNIT, "1")
	setDefaultValue(THIS_DEVICE, tabVars.VAR_VOLTAGE, "230")
	setDefaultValue(THIS_DEVICE, tabVars.VAR_DISABLED_DEVICES, "")

	-- Previous versions used one of four different static JSON files
	-- to handle the different firmware versions. That is no longer needed
	-- but we need to be sure the original JSON file is used.
	local currentJsonFilename = luup.attr_get("device_json", THIS_DEVICE)
	debug("Current JSON file: " .. currentJsonFilename)
	local properJsonFilename = "D_RFXtrx.json"
	debug("Proper JSON file: " .. properJsonFilename)
	if (currentJsonFilename ~= properJsonFilename)
		then
		debug("Setting device_json to " .. properJsonFilename)
		luup.attr_set("device_json", properJsonFilename, THIS_DEVICE)
		currentJsonFilename = luup.attr_get("device_json", THIS_DEVICE)
		debug("Current JSON file: " .. currentJsonFilename)
		if (currentJsonFilename ~= properJsonFilename)
		then
			error("Cannot set proper RFXtrx JSON file")
		else
			luup.reload()
		end
	end

end

local function encodeCommandsInString(tableCmds)

	local str = ""
	if ((tableCmds ~= nil) and (#tableCmds > 0))
		then
		for _, command in ipairs(tableCmds)
			do
			str = str .. command.altid .. "#" .. command.cmd .. "#" .. (command.value or "nil") .. "\n"
		end
	end
	return str

end

local function decodeCommandsFromString(data)

	local tableCmds = {}
	local i = 0
	while true
		do
		local j = string.find(data, "\n", i+1)
		if (j == nil)
			then
			break
		end
		local cmdstr = string.sub(data, i+1, j-1)
		--debug("cmd=" .. cmd)
		for id, cmd, value in string.gmatch(cmdstr, "([%u%d/.]+)#([%a%d]+)#([%a%d/. ]+)")
			do
			if (value == "nil")
				then
				value = nil
			end
			--debug("id=" .. (id or "nil") .. " cmd=" .. (cmd or "nil") .. " value=" .. (value or "nil"))
			table.insert(tableCmds, DeviceCmd( id, cmd, value, 0 ))
		end
		i = j
	end
	return tableCmds

end

local function logDevices()

	local countDS = 0
	local countMS = 0
	local countLS = 0
	local countDL = 0
	local countWC = 0
	local countTS = 0
	local countHS = 0
	local countBS = 0
	local countWS = 0
	local countRS = 0
	local countPM = 0
	local countUV = 0
	local countWT = 0
	local countSR = 0
	local countRC = 0
	local countHT = 0
	local countRM = 0
	local countLL = 0
	local countST = 0

	for _, device in ipairs(tableDevices)
		do
		local key = device[2]
		if (key == "DOOR")
			then
			countDS = countDS + 1
		elseif (key == "MOTION")
			then
			countMS = countMS + 1
		elseif (key == "LIGHT")
			then
			countLS = countLS + 1
		elseif (key == "DIMMER")
			then
			countDL = countDL + 1
		elseif (key == "COVER")
			then
			countWC = countWC + 1
		elseif (key == "TEMP")
			then
			countTS = countTS + 1
		elseif (key == "HUM")
			then
			countHS = countHS + 1
		elseif (key == "BARO")
			then
			countBS = countBS + 1
		elseif (key == "WIND")
			then
			countWS = countWS + 1
		elseif (key == "RAIN")
			then
			countRS = countRS + 1
		elseif (key == "POWER")
			then
			countPM = countPM + 1
		elseif (key == "UV")
			then
			countUV = countUV + 1
		elseif (key == "WEIGHT")
			then
			countWT = countWT + 1
		elseif (key == "ALARM")
			then
			countSR = countSR + 1
		elseif (key == "REMOTE")
			then
			countRC = countRC + 1
		elseif (key == "HEATER")
			then
			countHT = countHT + 1
		elseif (key == "RFXMETER")
			then
			countRM = countRM + 1
		elseif (key == "LIGHT_LEVEL")
			then
			countLL = countLL + 1
		elseif (key == "SWITCH_TOGGLE")
			then
			countST = countST + 1
		end
	end
	log("Tree with number child devices: " .. #tableDevices)
	log("       door sensors: " .. countDS)
	log("     motion sensors: " .. countMS)
	log("      light sensors: " .. countLL)
	log("     light switches: " .. countLS)
	log(" dim light switches: " .. countDL)
	log("    window covering: " .. countWC)
	log("temperature sensors: " .. countTS)
	log("   humidity sensors: " .. countHS)
	log(" barometric sensors: " .. countBS)
	log("       wind sensors: " .. countWS)
	log("       rain sensors: " .. countRS)
	log("         UV sensors: " .. countUV)
	log("     weight sensors: " .. countWT)
	log("      power sensors: " .. countPM)
	log("   security remotes: " .. countSR)
	log("    remote controls: " .. countRC)
	log("    heating devices: " .. countHT)
	log("          RFXMeters: " .. countRM)
	log("     smart switches: " .. countST)

end

local function logCmds(title, tableCmds)

	local str = title .. ": "
	if (tableCmds ~= nil and #tableCmds > 0)
		then
		for _, command in ipairs(tableCmds)
			do
			str = str .. (command.altid or "nil altid") .. " "
			if(command.cmd) then
				str = str .. (command.cmd.name or "nil cmd.name")
			else
				str = str .. "nil cmd"
			end
			str = str .. " " .. (command.value or "nil value") .. " "
			if (command.delay and tonumber(command.delay) > 0)
				then
				str = str .. " delayed " .. command.delay .. "s"
			end
		end
	end
	debug(str)

end

local function findStrInStringList(list, str)

	if (list ~= nil)
		then
		for value in string.gmatch(list, "[%u%d/.]+")
			do
			--debug("value = " .. value)
			if (value == str)
				then
				return true
			end
		end
	end

	return false

end

local function findAssociation(deviceNum, altid)

	local associations = getVariable(deviceNum, tabVars.VAR_ASSOCIATION)
	return findStrInStringList(associations, altid)

end

local function findChild(parentDevice, altid, deviceType)

	local key = altid .. (deviceType or "")
	local deviceNum = tableDeviceNumByAltidAndType[key]
	if(deviceNum ~= nil) then
		--debug("devicenum found in table - key: " .. key .. " devicenum: " .. deviceNum)
		return deviceNum
	end
	--debug("searching for devicenum " .. key)
	local foundAssoc = nil
	for k, veraDevice in pairs(luup.devices)
		do
		if ((deviceType == nil) or (veraDevice.device_type == deviceType))
			then
			if (veraDevice.device_num_parent == parentDevice and string.find(veraDevice.id, altid .. "$", 4) == 4)
				then
				tableDeviceNumByAltidAndType[key]= k
				return k
			elseif (findAssociation(k, altid) == true)
				then
				foundAssoc = k
				tableDeviceNumByAltidAndType[key]= k
			end
		end
	end
	if(foundAssoc == nil)
		then debug("findChild failed for altid: " .. altid)
	end
	return foundAssoc

end

local function findChildren(parentDevice, deviceType)

	local children = {}

	for k, v in pairs(luup.devices)
		do
		if (v.device_type == deviceType)
			then
			children[#children+1] = v.id
		end
	end
	return children

end

-- Function to send a message to RFXtrx
local function sendCommand(packetType, packetSubType, packetData, tableCmds)

	if (tableCmds ~= nil and #tableCmds > 0)
		then
		table.insert(tableMsgSent, { sequenceNum, tableCmds })
	end

	local cmd = string.char(string.len(packetData) + 3, packetType, packetSubType, sequenceNum) .. packetData

	debug("Sending command: " .. formattohex(cmd))

	if (luup.io.write(cmd) == false)
		then
		task("Cannot send command - communications error", TASK_ERROR)
		luup.set_failure(true)
		return false
	end

	sequenceNum = (sequenceNum + 1) % 256

	return true

end

local function sendRepeatCommand(packetType, packetSubType, packetData, nbRTimes, tableCmds)

	for i=1, nbRTimes
		do
		if (i == 1)
			then
			sendCommand(packetType, packetSubType, packetData, tableCmds)
		else
			sendCommand(packetType, packetSubType, packetData, { { "", "", nil, 0 } })
		end
	end

end

local function isDisabledDevice(id)

	local disabledDevices = getVariable(THIS_DEVICE, tabVars.VAR_DISABLED_DEVICES)
	return findStrInStringList(disabledDevices, id)

end

local function disableDevice(id)

	local disabledDevices = getVariable(THIS_DEVICE, tabVars.VAR_DISABLED_DEVICES)
	if (findStrInStringList(disabledDevices, id) == false)
		then
		if (disabledDevices == nil or disabledDevices == "")
			then
			disabledDevices = id
		else
			disabledDevices = disabledDevices .. "," .. id
		end
		setVariable(THIS_DEVICE, tabVars.VAR_DISABLED_DEVICES, disabledDevices)
	end
require('mobdebug').done()

end

-- Convert a value from millimeters to inches
local function inches( millimeters )
	return (millimeters * mm2inch)
end

-- Convert a value from inches to millimeters
local function millimeters( inches )
	return (inches * inch2mm)
end

local function isLeapYear( year )
	if(((year % 4 == 0) and (year % 100 ~= 0)) or (year % 400 == 0)) then
		return true
	else
		return false
	end
end

local function indexDiff(first, last, size)
	local diff = last - first
	if(last < first) then
		diff = diff + size
	end
	return diff
end

-- Given the year and the julian day
-- determine the week number
local function weekOfYear( year, day )
	local yearStart = { year = year, month = 1, day = 1, hour = 0 }
	-- The numeric value of that date
	local yearNum = os.time(yearStart)
	-- This will fill in all of the details for 1 January of that year including the day of the week
	yearStart = os.date("*t", yearNum)
	local weekOffset = math.floor((yearStart["wday"] + 6) / 12 )
	local daysOffset = yearStart["wday"] - 2
	local week = (math.floor((day + daysOffset)/7) - weekOffset + 1)
	-- If the week is 53 then it's the start of week 1 of the next year
	if (week==53) then
		week = 1
	end
	return week
end

-- Extract the battery level from the data string sent by the device
-- byte1 is the location of the byte containing the battery level in the data string
-- Battery level should never be greater than 9?
local function decodeBatteryLevel( dataString, byte1 )
	-- it's always the lower 4 bits
	local battery = bitw.band(string.byte(dataString, byte1), 0x0F)
	if (battery <= 9)
		then
		battery = (battery + 1) * 10
	else
		battery = 99
	end
	return battery
end


-- Decode bytes received from a device that contain the measured temperature
-- dataString is the string received from the sensor
-- byte1 is the first byte of temperature data. The second byte of data always
-- follows the first
local function decodeTemperature( altid, dataString, byte1 )
	local temp = (bitw.band(string.byte(dataString, byte1), 0x7F) * 256 + string.byte(dataString, byte1 + 1)) / 10
	if (bitw.band(string.byte(dataString, byte1), 0x80) == 0x80)
		then
		temp = -temp
		if (temp < -28.89)
			then
			debug("Dubious temperature reading: " .. temp .. "C" .. " altid=" .. altid)
		end
		else if (temp > 65.56)
			then
			debug("Dubious temperature reading: " .. temp .. "C" .. " altid=" .. altid)
		end
	end
	if (not getVariable(THIS_DEVICE, tabVars.VAR_TEMP_UNIT))
		then
		-- Convert degree celcius to degree fahrenheit
		temp = math.floor((temp * 1.8 + 32) * 10 + 0.5) / 10
	end
	return temp
end

local function resetRainData(first, last, rainTable)
	if(type(rainTable) ~= "table")
		then
		warning("Invalid type passed to resetRainData")
		return
	end
	debug("Resetting rain data from " .. first .. " to " .. last .. " in " .. #rainTable)
	local i = first
	if (first <= last) then
		while i <= last do
			rainTable[i] = 0
			i = i + 1
		end
	else
		while i <= #rainTable do
			rainTable[i] = 0
			i = i + 1
		end
		i = 1
		while i <= last do
			rainTable[i] = 0
			i = i + 1
		end
	end
end

-- Reset all of the data in one of the rain data tables
-- size is used in case dataTable needs to be created
local function resetRainTable(rainTable, size)
	if(type(rainTable) ~= "table")
		then
		warning("Invalid type passed to resetRainTable")
		return
	end
	debug("Resetting rain table " .. #rainTable)
	resetRainData(1, size, rainTable)
end

-- Retrieve the a rain data table from the rain device data
local function getRainTableData(deviceNum, variable, size)
	local tableDataString = getVariable(deviceNum, variable)
	local rainTable = {}
	if(tableDataString == nil)
		then
		local i = 1
		while(i <= size) do
			rainTable[i] = 0.0
			i = i+1
		end
	else
		for v in string.gmatch(tableDataString, "(-?%d+%.?%d*)") do
			rainTable[#rainTable + 1] = tonumber(v)
		end
	end

	return rainTable
end

-- A function to concatenate table values with a comma seperator
-- Works even if a table contains tables
local function recursiveConcat(item)
	if type(item) ~= "table" then return item end
	local res = {}
	for i = 1, #item do
		res[i] = recursiveConcat(item[i])
	end
	return table.concat(res, ',')
end

-- Create an new max min table of 24 given max and min values
local function createMaxMinTable( maxVal, minVal )
	local maxval = tonumber(maxVal)
	local minval = tonumber(minVal)
	if((maxval == nil) or (minval == nil))
	then return nil end
	local newMaxMinTable = {}
	for i=1, 24
		do
		newMaxMinTable[i] = { maxval, minval }
	end
	return newMaxMinTable
end

-- Put all of the max and min values from a table into a single string
local function stringifyMaxMinTable(tableMaxMin)
	local tempData = ''
	if((tableMaxMin == nil) or (#tableMaxMin == 0))
		then
		debug("Empty or NIL MaxMin Table")
	else
		local tempTable = {}
		for i=1, #tableMaxMin
			do
			tempTable[i]= table.concat(tableMaxMin[i],',')
		end
		tempData = table.concat(tempTable, ',')
	end
	return tempData
end

-- Recreate a table of max min values from a string containing the data
local function recreateMaxMinTable(tableDataString)
	local newHourlyMaxMin = {}
	for k, v in string.gmatch(tableDataString, "(-?%d+%.?%d*)%,(-?%d+%.?%d*)") do
		newHourlyMaxMin[#newHourlyMaxMin + 1] = {tonumber(k),tonumber(v)}
	end
	return newHourlyMaxMin
end

-- Update if necessary the max or min values detected for a temperature sensor device
local function checkMaxMinTemp( altid, tableCmds, temp )
	local maxMinString = ''
	local maxMinTable = {}
	local tableModified = false
	-- Get the current hour. Add 1 so that our table index starts at 1
	local thisHour = tonumber(os.date("%H", os.time())) + 1
	local prevHour
	local maxval
	local minval
	-- Determine the device number of the temperature sensor
	local deviceNum = findChild(THIS_DEVICE, altid, tableDeviceTypes.TEMP.deviceType)
	if (deviceNum ~= nil)
		then
		-- Update the maximum temperature if necessary
		maxval = tonumber(getVariable(deviceNum, tabVars.VAR_TEMPMAX))
		if (maxval == nil or temp > maxval)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_TEMPMAX, temp, 0 ) )
		end
		-- Update the minimum temperature if necessary
		minval = tonumber(getVariable(deviceNum, tabVars.VAR_TEMPMIN))
		if (minval == nil or temp < minval)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_TEMPMIN, temp, 0 ) )
		end
		-- Get the string of max and min temperature values for the last 24 hours
		maxMinString = getVariable(deviceNum, tabVars.VAR_TEMPMAXMIN)
		-- If the string is empty create a new table of values
		if((maxMinString == nil) or (#maxMinString == 0))
			then
			maxMinTable = createMaxMinTable( -20, 150 )
			tableModified = true
		else
			-- Get the table values from the string
			maxMinTable = recreateMaxMinTable(maxMinString)
		end
		-- Update the table values if necessary
		-- Get the hour of the previous sensor input
		prevHour = tonumber(os.date("%H", getVariable(deviceNum, tabVars.VAR_BATTERY_DATE))) + 1
		-- If they're different save the new temp as the max and min for the current hour
		if( prevHour ~= thisHour)
			then
			maxMinTable[thisHour] = { temp, temp }
			tableModified = true
		else
			-- Otherwise see if the new temp is greater than the current max or less than the current min for this hour
			if(maxMinTable[thisHour][1] < temp)
				then
				maxMinTable[thisHour][1] = temp
				tableModified = true
			end
			if(maxMinTable[thisHour][2] > temp)
				then
				maxMinTable[thisHour][2] = temp
				tableModified = true
			end
		end

		if(tableModified)
			then
			-- Find the max and min temps in the last 24 hours
			maxval = -20.0
			minval = 150.0
			for i = 1, #maxMinTable
				do
				maxval = math.max(maxMinTable[i][1], maxval)
				minval = math.min(maxMinTable[i][2], minval)
			end
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_TEMPMAX24HR, maxval, 0 ) )
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_TEMPMIN24HR, minval, 0 ) )
			maxMinString = stringifyMaxMinTable(maxMinTable)
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_TEMPTABLE, maxMinString, 0 ) )
		end
	end
end

-- Update if necessary the max or min values detected for a humidity sensor device
local function checkMaxMinHum( altid, tableCmds, hum )
	local maxMinString = ''
	local maxMinTable = {}
	local tableModified = false
	-- Get the current hour. Add 1 so that our table index starts at 1
	local thisHour = tonumber(os.date("%H", os.time())) + 1
	local prevHour
	local maxval
	local minval
	-- Determine the device number of the temperature sensor
	local deviceNum = findChild(THIS_DEVICE, altid, tableDeviceTypes.HUM.deviceType)
	if (deviceNum ~= nil)
		then
		-- Update the maximum temperature if necessary
		maxval = tonumber(getVariable(deviceNum, tabVars.VAR_HUMMAX))
		if (maxval == nil or hum > maxval)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HUMMAX, hum, 0 ) )
		end
		-- Update the minimum temperature if necessary
		minval = tonumber(getVariable(deviceNum, tabVars.VAR_HUMMIN))
		if (minval == nil or hum < minval)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HUMMIN, hum, 0 ) )
		end
		-- Get the string of max and min temperature values for the last 24 hours
		maxMinString = getVariable(deviceNum, tabVars.VAR_HUMMAXMIN)
		-- If the string is empty create a new table of values
		if((maxMinString == nil) or (#maxMinString == 0))
			then
			maxMinTable = createMaxMinTable( 0, 100 )
			tableModified = true
		else
			-- Get the table values from the string
			maxMinTable = recreateMaxMinTable(maxMinString)
		end
		-- Update the table values if necessary
		-- Get the hour of the previous sensor input
		prevHour = tonumber(os.date("%H", getVariable(deviceNum, tabVars.VAR_BATTERY_DATE))) + 1
		-- If they're different save the new hum as the max and min for the current hour
		if( prevHour ~= thisHour)
			then
			maxMinTable[thisHour] = { hum, hum }
			tableModified = true
		else
			-- Otherwise see if the new hum is greater than the current max or less than the current min for this hour
			if(maxMinTable[thisHour][1] < hum)
				then
				maxMinTable[thisHour][1] = hum
				tableModified = true
			end
			if(maxMinTable[thisHour][2] > hum)
				then
				maxMinTable[thisHour][2] = hum
				tableModified = true
			end
		end

		if(tableModified)
			then
			-- Find the max and min temps in the last 24 hours
			maxval = 0
			minval = 100
			for i = 1, #maxMinTable
				do
				maxval = math.max(maxMinTable[i][1], maxval)
				minval = math.min(maxMinTable[i][2], minval)
			end
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HUMMAX24HR, maxval, 0 ) )
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HUMMIN24HR, minval, 0 ) )
			maxMinString = stringifyMaxMinTable(maxMinTable)
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HUMTABLE, maxMinString, 0 ) )
		end
	end
end


-- Check existing devices and init tables
local function checkExistingDevices(lul_device)

	local nbr = 0

	-- Check all devices if they are childeren. If so, register in
	-- the correct array based on the device type
	for k, v in pairs(luup.devices)
		do
		-- Look for devices with this device as parent
		if (v.device_num_parent == lul_device)
			then
			debug( "Found child device id " .. tostring(v.id) .. " of type " .. tostring(v.device_type))
			nbr = nbr + 1

			local key = searchInKeyTable(tableDeviceTypes, tostring(v.device_type), string.sub(v.id, 1, 3))
			if (key ~= nil)
				then
				local associations = getVariable(k, tabVars.VAR_ASSOCIATION)
				table.insert(tableDevices, { v.id, key, associations, v.description })
				if (tableDeviceTypes[key].hasMode)
					then
					setDefaultValue(k, tabVars.VAR_RFY_MODE, "STANDARD")
				end
				if (tableDeviceTypes[key].hasAdjustments)
					then
					setDefaultValue(k, tabVars.VAR_ADJUST_MULTIPLIER, "1.0")
					setDefaultValue(k, tabVars.VAR_ADJUST_CONSTANT, "0.0")
					setDefaultValue(k, tabVars.VAR_ADJUST_CONSTANT2, "0.0")
				end
				if (key == "LIGHT")
					then
					setDefaultValue(k, tabVars.VAR_REPEAT_EVENT, "0")
				elseif (key == "MOTION" or key == "DOOR" or key == "SMOKE")
					then
					setDefaultValue(k, tabVars.VAR_REPEAT_EVENT, "1")
				end
			end
		end
	end

	setVariable(lul_device, tabVars.VAR_NBR_DEVICES, nbr)

	logDevices()

end

local function updateManagedDevices(tableNewDevices, tableConversions, tableDeletedDevices)

	if (( (tableNewDevices ~= nil) and (#tableNewDevices > 0) )
		or ( (tableConversions ~= nil) and (#tableConversions > 0) )
		or ( (tableDeletedDevices ~= nil) and (#tableDeletedDevices > 0) ))
		then
		local child_devices = luup.chdev.start(THIS_DEVICE);

		-----------------------------------------------------------------------------------
		-- First add or convert all 'old' children to the three
		-----------------------------------------------------------------------------------
		for i, device in ipairs(tableDevices)
			do
			local id = device[1]
			local subId = string.sub(id, 4, #id)
			local existingDevice = tableDeviceTypes[device[2]]
			local associations = device[3]
			local name = device[4]

			local toBeDeleted = false

			if ((tableDeletedDevices ~= nil) and (#tableDeletedDevices > 0))
				then
				for _, v2 in ipairs(tableDeletedDevices)
					do
					if (v2 == id)
						then
						toBeDeleted = true
						break
					end
				end
			end

			local room
			local deviceId = nil
			local devType = nil

			if ((tableConversions ~= nil) and (#tableConversions > 0))
				then
				for _, v2 in ipairs(tableConversions)
					do
					if ((subId == v2[3]) or (findStrInStringList(associations, v2[3]) == true))
						then
						name = v2[1]
						room = v2[2]
						deviceId = v2[3]
						devType = v2[4]
						break
					end
				end
			end

			if (deviceId ~= nil and devType ~= nil)
				then
				debug("Converting " .. name .. "...")

				local newDeviceType = tableDeviceTypes[devType]

				if (newDeviceType ~= existingDevice)
					then
					local parameters = ""
					if (newDeviceType.hasAssociation)
						then
						if (parameters ~= "")
							then
							parameters = parameters .. "\n"
						end
						parameters = parameters .. tabVars.VAR_ASSOCIATION.serviceId .. "," .. tabVars.VAR_ASSOCIATION.name .. "="
						if (associations ~= nil)
							then
							parameters = parameters .. associations
							else
							parameters = parameters .. ""
						end
					end
					if (newDeviceType == tableDeviceTypes.LIGHT)
						then
						if (parameters ~= "")
							then
							parameters = parameters .. "\n"
						end
						parameters = parameters .. tabVars.VAR_LIGHT.serviceId .. "," .. tabVars.VAR_LIGHT.name .. "=0"
						parameters = parameters .. "\n"
						parameters = parameters .. tabVars.VAR_REPEAT_EVENT.serviceId .. "," .. tabVars.VAR_REPEAT_EVENT.name .. "=0"
					elseif (newDeviceType == tableDeviceTypes.DIMMER
						or newDeviceType == tableDeviceTypes.COVER)
						then
						if (parameters ~= "")
							then
							parameters = parameters .. "\n"
						end
						parameters = parameters .. tabVars.VAR_DIMMER.serviceId .. "," .. tabVars.VAR_DIMMER.name .. "=0"
						parameters = parameters .. "\n"
						parameters = parameters .. tabVars.VAR_LIGHT.serviceId .. "," .. tabVars.VAR_LIGHT.name .. "=0"
					elseif (newDeviceType == tableDeviceTypes.MOTION
						or newDeviceType == tableDeviceTypes.DOOR)
						then
						if (parameters ~= "")
							then
							parameters = parameters .. "\n"
						end
						parameters = parameters .. tabVars.VAR_ARMEDTRIPPED.serviceId .. "," .. tabVars.VAR_ARMEDTRIPPED.name .. "=0"
						--						parameters = parameters .. "\n"
						--						parameters = parameters .. tabVars.VAR_TRIPPED.serviceId .. "," .. tabVars.VAR_TRIPPED.name .. "=0"
						parameters = parameters .. "\n"
						parameters = parameters .. tabVars.VAR_REPEAT_EVENT.serviceId .. "," .. tabVars.VAR_REPEAT_EVENT.name .. "=1"
						--						parameters = parameters .. "\n"
						--						parameters = parameters .. tabVars.VAR_TAMPERED.serviceId .. "," .. tabVars.VAR_TAMPERED.name .. "=0"
					elseif (newDeviceType == tableDeviceTypes.LIGHT_LEVEL)
						then
						if (parameters ~= "")
							then
							parameters = parameters .. "\n"
						end
						parameters = parameters .. tabVars.VAR_LIGHT_LEVEL.serviceId .. "," .. tabVars.VAR_LIGHT_LEVEL.name .. "=0"
					end
					luup.chdev.append(THIS_DEVICE, child_devices, newDeviceType.prefix .. subId, name,
					newDeviceType.deviceType, newDeviceType.deviceFile, "", parameters, false)
					tableDevices[i] = { newDeviceType.prefix .. subId, devType, associations, name }
				else
					luup.chdev.append(THIS_DEVICE, child_devices, id, name,
					existingDevice.deviceType, existingDevice.deviceFile, "", "", false)
				end
			elseif (not toBeDeleted)
				then
				luup.chdev.append(THIS_DEVICE, child_devices, id, name,
				existingDevice.deviceType, existingDevice.deviceFile, "", "", false)
			end
		end

		------------------------------------------------------------------------------------
		-- Now add the new device(s) to the tree
		------------------------------------------------------------------------------------

		if ((tableNewDevices ~= nil) and (#tableNewDevices > 0))
			then
			for _, device in ipairs(tableNewDevices)
				do
				local name = device[1]
				local room = device[2]
				local deviceId = device[3]
				local devType = device[4]
				local newDevice = tableDeviceTypes[devType]
				name = name or (newDevice.name .. deviceId)
				debug("Creating child device id " .. newDevice.prefix .. deviceId .. " of type " .. newDevice.deviceType)
				local parameters = ""
				if (newDevice.hasAssociation)
					then
					if (parameters ~= "")
						then
						parameters = parameters .. "\n"
					end
					parameters = parameters .. tabVars.VAR_ASSOCIATION.serviceId .. "," .. tabVars.VAR_ASSOCIATION.name .. "="
				end
				if (newDevice.hasMode)
					then
					if (parameters ~= "")
						then
						parameters = parameters .. "\n"
					end
					parameters = parameters .. tabVars.VAR_RFY_MODE.serviceId .. "," .. tabVars.VAR_RFY_MODE.name .. "=STANDARD"
				end
				if (newDevice.hasAdjustments)
					then
					if (parameters ~= "")
						then
						parameters = parameters .. "\n"
					end
					parameters = parameters .. tabVars.VAR_ADJUST_MULTIPLIER.serviceId .. "," .. tabVars.VAR_ADJUST_MULTIPLIER.name .. "=1.0"
					parameters = parameters .. "\n"
					parameters = parameters .. tabVars.VAR_ADJUST_CONSTANT.serviceId .. "," .. tabVars.VAR_ADJUST_CONSTANT.name .. "=0.0"
					parameters = parameters .. "\n"
					parameters = parameters .. tabVars.VAR_ADJUST_CONSTANT2.serviceId .. "," .. tabVars.VAR_ADJUST_CONSTANT2.name .. "=0.0"
				end
				if (newDevice == tableDeviceTypes.LIGHT)
					then
					if (parameters ~= "")
						then
						parameters = parameters .. "\n"
					end
					parameters = parameters .. tabVars.VAR_LIGHT.serviceId .. "," .. tabVars.VAR_LIGHT.name .. "=0"
					parameters = parameters .. "\n"
					parameters = parameters .. tabVars.VAR_REPEAT_EVENT.serviceId .. "," .. tabVars.VAR_REPEAT_EVENT.name .. "=0"
				elseif (newDevice == tableDeviceTypes.SWITCH_TOGGLE)
					then
					if (parameters ~= "")
						then
						parameters = parameters .. "\n"
					end
					parameters = parameters .. tabVars.VAR_STATE.serviceId .. "," .. tabVars.VAR_STATE.name .. "=0"
					parameters = parameters .. "\n"
					parameters = parameters .. tabVars.VAR_REPEAT_EVENT.serviceId .. "," .. tabVars.VAR_REPEAT_EVENT.name .. "=1"
				elseif (newDevice == tableDeviceTypes.DIMMER
					or newDevice == tableDeviceTypes.COVER)
					then
					if (parameters ~= "")
						then
						parameters = parameters .. "\n"
					end
					parameters = parameters .. tabVars.VAR_DIMMER.serviceId .. "," .. tabVars.VAR_DIMMER.name .. "=0"
					parameters = parameters .. "\n"
					parameters = parameters .. tabVars.VAR_LIGHT.serviceId .. "," .. tabVars.VAR_LIGHT.name .. "=0"
				elseif (newDevice == tableDeviceTypes.MOTION
					or newDevice == tableDeviceTypes.DOOR
					or newDevice == tableDeviceTypes.SMOKE)
					then
					if (parameters ~= "")
						then
						parameters = parameters .. "\n"
					end
					parameters = parameters .. tabVars.VAR_TRIPPED.serviceId .. "," .. tabVars.VAR_TRIPPED.name .. "=0"
					parameters = parameters .. "\n"
					parameters = parameters .. tabVars.VAR_REPEAT_EVENT.serviceId .. "," .. tabVars.VAR_REPEAT_EVENT.name .. "=1"
					parameters = parameters .. "\n"
					parameters = parameters .. tabVars.VAR_ARMED.serviceId .. "," .. tabVars.VAR_ARMED.name .. "=0"
					parameters = parameters .. "\n"
					parameters = parameters .. tabVars.VAR_AUTOUNTRIP.serviceId .. "," .. tabVars.VAR_AUTOUNTRIP.name .. "=0"
				elseif (newDevice == tableDeviceTypes.ALARM)
					then
					if (parameters ~= "")
						then
						parameters = parameters .. "\n"
					end
					parameters = parameters .. tabVars.VAR_EXIT_DELAY.serviceId .. "," .. tabVars.VAR_EXIT_DELAY.name .. "=0"
				elseif (newDevice == tableDeviceTypes.LIGHT_LEVEL)
					then
					if (parameters ~= "")
						then
						parameters = parameters .. "\n"
					end
					parameters = parameters .. tabVars.VAR_LIGHT_LEVEL.serviceId .. "," .. tabVars.VAR_LIGHT_LEVEL.name .. "=0"
				end
				luup.chdev.append(THIS_DEVICE, child_devices, newDevice.prefix .. deviceId, name,
				newDevice.deviceType, newDevice.deviceFile, "", parameters, false)
				table.insert(tableDevices, { newDevice.prefix .. deviceId, devType, nil, name })
			end
		end

		logDevices()
		-- Synch the new tree with the old three
		debug("Start sync")
		luup.chdev.sync(THIS_DEVICE, child_devices)
		debug("End sync")

		initIDLookup()
	end

end

local function actOnCommands(tableCmds)

	if ((tableCmds == nil) or (#tableCmds == 0))
		then
		debug("actOnCommands: tableCmds is empty")
		return
	end

	logCmds("actOnCommands:cmds", tableCmds)

	local altID
	local cmd
	local deviceIdNum
	local cmdDeviceType
	local value, value2
	local variable, variable2

	------------------------------------------------------------------------------
	-- Creation of new child devices
	------------------------------------------------------------------------------
	local autoCreate = (getVariable(lul_device, tabVars.VAR_AUTO_CREATE))
	local tableNewDevices = {}
	local tableConversions = {}
	for _, command in ipairs(tableCmds)
		do
		altID = command.altid
		cmd = command.cmd
		if(cmd) then
			cmdDeviceType = cmd.deviceType
		else
			cmdDeviceType = nil
		end
		if ((altID and #altID > 0)
			and (cmdDeviceType ~= nil)
			and (searchInTable2(tableNewDevices, 3, altID, 4, cmdDeviceType) == 0)
			and (searchInTable(tableConversions, 3, altID) == 0))
			then
			deviceIdNum = devicedIdNumByAltId[altID]
			-- Check if child exists but conversion is required
			local dev = nil
			if (cmd == tableCommandTypes.CMD_OPEN
				or cmd == tableCommandTypes.CMD_CLOSE
				or cmd == tableCommandTypes.CMD_STOP
				or cmd == tableCommandTypes.CMD_ON
				or cmd == tableCommandTypes.CMD_OFF
				or cmd == tableCommandTypes.CMD_DIM)
				then
				dev = findChild(THIS_DEVICE, altID, nil)
				if (dev ~= nil)
					then
					if ((cmd == tableCommandTypes.CMD_OPEN
						or cmd == tableCommandTypes.CMD_CLOSE
						or cmd == tableCommandTypes.CMD_STOP)
						and (luup.devices[dev].device_type == tableDeviceTypes.LIGHT.deviceType
						or luup.devices[dev].device_type == tableDeviceTypes.DIMMER.deviceType))
						then
						table.insert(tableConversions, { luup.devices[dev].description,
							luup.devices[dev].room_num,	altID, "COVER" })
					elseif (cmd == tableCommandTypes.CMD_DIM
						and luup.devices[dev].device_type == tableDeviceTypes.LIGHT.deviceType)
						then
						table.insert(tableConversions, { luup.devices[dev].description,
							luup.devices[dev].room_num,	altID, "DIMMER" })
					end
				end
			end
			if ((dev == nil)
				and (autoCreate)
				and (findChild(THIS_DEVICE, altID, tableDeviceTypes[cmdDeviceType].deviceType) == nil)
				and (isDisabledDevice(tableDeviceTypes[cmdDeviceType].prefix .. altID) == false))
				then
				table.insert(tableNewDevices, { nil, nil, altID, cmdDeviceType })
				debug("New device: altID: " .. altID .. " deviceType: " .. cmdDeviceType)
			end
		end
	end
	if ((#tableNewDevices > 0) or (#tableConversions > 0))
		then
		updateManagedDevices(tableNewDevices, tableConversions, nil)
		return
	end

	-- Separate immediate and delayed commands
	local tableImmediateCmds = {}
	local tableDelays = {}
	for _, command in ipairs(tableCmds)
		do
		if (command.delay == 0)
			then
			table.insert(tableImmediateCmds, command )
		elseif (searchInStringTable(tableDelays, command.delay) == 0)
			then
			table.insert(tableDelays, command.delay)
		end
	end
	--logCmds("immediate cmds", tableImmediateCmds)
	-- Plan delayed commands
	for _, delay in ipairs(tableDelays)
		do
		local tableDelayedCmds = {}
		for _, command in ipairs(tableCmds)
			do
			if (command.delay == delay)
				then
				table.insert(tableDelayedCmds, command )
			end
		end
		--logCmds("delayed cmds " .. delay .. "s", tableDelayedCmds)
		luup.call_delay("handleDelayedCmds", delay, encodeCommandsInString(tableDelayedCmds))
	end

	-- Exit if there are no immediate commands
	if (tableImmediateCmds == nil or #tableImmediateCmds == 0)
		then
		return
	end

	------------------------------------------------------------------------------
	-- Deliver commands to devices
	------------------------------------------------------------------------------
	for deviceNum, luupDevice in pairs(luup.devices) do
		-- Check if we have a device with the correct parent (THIS_DEVICE)
		if (luupDevice.device_num_parent == THIS_DEVICE)
			then
--			debug("Device Number: " .. deviceNum ..
--					 " luupDevice.device_type: " .. tostring(luupDevice.device_type) ..
--					 " luupDevice.device_num_parent: " .. tostring(luupDevice.device_num_parent) ..
--					 " luupDevice.id: " .. tostring(luupDevice.id)
--			)
			for _, v2 in ipairs(tableImmediateCmds)
				do
				altID = v2.altid
				cmd = v2.cmd
				value = v2.value
				if ((#altID > 0)
					and ((string.find(luupDevice.id, altID .. "$", 4) == 4)
					or (findAssociation(deviceNum, altID) == true)))
					then
					if (cmd == tableCommandTypes.CMD_OFF)
						then
						value = "0"
					elseif (cmd == tableCommandTypes.CMD_ON)
						then
						value = "1"
					end
					cmdDeviceType = nil
					variable = nil
					if (cmd.deviceType ~= nil)
						then
						cmdDeviceType = tableDeviceTypes[cmd.deviceType]
					end
					if (cmd.variable ~= nil)
						then
						variable = tabVars[cmd.variable]
					end
					if ((cmdDeviceType == nil or luupDevice.device_type == cmdDeviceType.deviceType) and variable ~= nil and value ~= nil)
						then
						if (cmdDeviceType ~= nil and cmdDeviceType.hasAdjustments and variable.isAdjustable)
							then
							value = tonumber(value)
							local adjust = getVariable(deviceNum, tabVars.VAR_ADJUST_CONSTANT2)
							if (adjust ~= nil and adjust ~= "")
								then
								value = value + tonumber(adjust)
							end
							adjust = getVariable(deviceNum, tabVars.VAR_ADJUST_MULTIPLIER)
							if (adjust ~= nil and adjust ~= "")
								then
								value = value * tonumber(adjust)
							end
							adjust = getVariable(deviceNum, tabVars.VAR_ADJUST_CONSTANT)
							if (adjust ~= nil and adjust ~= "")
								then
								value = value + tonumber(adjust)
							end
						end
						setVariable(deviceNum, variable, value)
					end
					if (luupDevice.device_type == tableDeviceTypes.DIMMER.deviceType
						or luupDevice.device_type == tableDeviceTypes.COVER.deviceType)
						then
						variable = nil
						variable2 = nil
						if (luupDevice.device_type == tableDeviceTypes.COVER.deviceType and cmd == tableCommandTypes.CMD_DIM)
							then
							variable = tabVars.VAR_DIMMER
						end
						if (cmd == tableCommandTypes.CMD_OFF or cmd == tableCommandTypes.CMD_CLOSE)
							then
							variable = tabVars.VAR_DIMMER
							value = 0
							variable2 = tabVars.VAR_LIGHT
							value2 = "0"
						elseif (cmd == tableCommandTypes.CMD_ON or cmd == tableCommandTypes.CMD_OPEN)
							then
							variable = tabVars.VAR_DIMMER
							value = 100
							variable2 = tabVars.VAR_LIGHT
							value2 = "1"
						elseif (cmd == tableCommandTypes.CMD_DIM and tonumber(value) == 0)
							then
							variable2 = tabVars.VAR_LIGHT
							value2 = "0"
						elseif (cmd == tableCommandTypes.CMD_DIM and tonumber(value) > 0)
							then
							variable2 = tabVars.VAR_LIGHT
							value2 = "1"
						end
						setVariable(deviceNum, variable, value)
						setVariable(deviceNum, variable2, value2)
					elseif (luupDevice.device_type == tableDeviceTypes.MOTION.deviceType
						or luupDevice.device_type == tableDeviceTypes.DOOR.deviceType)
						then
						value = nil
						if (cmd == tableCommandTypes.CMD_OFF)
							then
							value = false
						elseif (cmd == tableCommandTypes.CMD_ON)
							then
							value = true
						end
						setVariable(deviceNum, tabVars.VAR_TRIPPED, value)
					elseif (luupDevice.device_type == tableDeviceTypes.LIGHT_LEVEL.deviceType)
						then
						value = nil
						if (cmd == tableCommandTypes.CMD_OFF)
							then
							value = "100"
						elseif (cmd == tableCommandTypes.CMD_ON)
							then
							value = "0"
						end
						setVariable(deviceNum, tabVars.VAR_LIGHT_LEVEL, value)
					elseif (luupDevice.device_type == tableDeviceTypes.SMOKE.deviceType)
						then
						value = nil
						if (cmd == tableCommandTypes.CMD_SMOKE_OFF)
							then
							local last = getVariable(deviceNum, tabVars.VAR_LAST_TRIP)
							if (getVariable(deviceNum, tabVars.VAR_TRIPPED)
								and last ~= nil and (os.time() - last) >= 25)
								then
								value = false
							end
						end
						setVariable(deviceNum, tabVars.VAR_TRIPPED, value)
					end
				end
			end
		end
	end

end

function handleDelayedCmds(data)

	local tableCmds = decodeCommandsFromString(data)
	actOnCommands(tableCmds)
	return 0

end

-- Function to decode a message.
local function decodeMessage(message)

	local tableCmds = {}
	local key = string.format('%06X',(bitw.lshift((bitw.lshift(string.byte(message, 1),8) + string.byte(message, 2)), 8)) + string.byte(message, 3))
	--debug("Msg select key: " .. key)
	local seqNum = string.byte(message, 4)
	local data = getStringPart(message, 5, #message)
	local decodeFunction = tableMsgSelect[key].decodeFunction

	-- If there is a method to decode this message
	if(decodeFunction ~= nil) then
		tableCmds = decodeFunction(tableMsgSelect[key].subType, data, seqNum)
		actOnCommands(tableCmds)
	else
		warning("No decode method for message: " .. formattohex(message))
		return
	end
end

local function decodeResponse(subType, data, seqNum)

	local tableCmds = {}

	if (subType == tableMsgTypes.TRANSMITTER_RESPONSE.subType)
		then
		debug("Response to a command")
		local idx = searchInTable(tableMsgSent, 1, seqNum)
		if (idx > 0)
			then
			debug("Found sent command " .. seqNum .. " at index " .. idx)
			local msg = string.byte(data, 1)
			if (msg == 0x0 or msg == 0x1)
				then
				debug("Transmitter response " .. msg .. " ACK")
				tableCmds = tableMsgSent[idx][2]
			elseif (msg == 0x2 or msg == 0x3) then
				error("Transmitter response " .. msg .. " NAK for message number " .. seqNum)
			else
				error("Transmitter response " .. msg .. " ??? for message number " .. seqNum)
			end
			table.remove(tableMsgSent, idx)
		else
			error("Transmitter response for an unexpected message number " .. seqNum)
		end
	end

	return tableCmds

end

local function decodeResponseMode(subType, data)
	local tableCmds = {}

	if (subType == tableMsgTypes.RESPONSE_MODE_COMMAND.subType)
		then
		log("Plugin version: " .. PLUGIN_VERSION)
		setVariable(THIS_DEVICE, tabVars.VAR_PLUGIN_VERSION, PLUGIN_VERSION)
		local cmd = string.byte(data, 1)
		-- if result of Get Status or Set Mode commands
		if (cmd == 0x2 or cmd == 0x3)
			then
			debug("Response to a Get Status command or Set Mode command")
			typeRFX = string.byte(data, 2)
			if (typeRFX == 0x50)
				then
				log("RFXtrx315 at 310 MHz")
			elseif (typeRFX == 0x51)
				then
				log("RFXtrx315 at 315 MHz")
			elseif (typeRFX == 0x52)
				then
				log("RFXrec433 at 433.92 MHz")
			elseif (typeRFX == 0x53)
				then
				log("RFXtrx433e at 433.92 MHz")
			elseif (typeRFX == 0x55)
				then
				log("RFXtrx868 at 868.00 MHz")
			elseif (typeRFX == 0x56)
				then
				log("RFXtrx868 at 868.00 MHz FSK")
			elseif (typeRFX == 0x57)
				then
				log("RFXtrx868 at 868.30 MHz")
			elseif (typeRFX == 0x58)
				then
				log("RFXtrx868 at 868.30 MHz FSK")
			elseif (typeRFX == 0x59)
				then
				log("RFXtrx868 at 868.35 MHz")
			elseif (typeRFX == 0x5A)
				then
				log("RFXtrx868 at 868.35 MHz FSK")
			elseif (typeRFX == 0x5B)
				then
				log("RFXtrx868 at 868.95 MHz")
			end

			-- Add 1000 to the byte indicating the firmware version
			--  so that the displayed version matches that of the firmware version
			firmware = 1000 + string.byte(data, 3)
			log("Firmware version: " .. firmware)
			setVariable(THIS_DEVICE, tabVars.VAR_FIRMWARE_VERSION, firmware)

			-- Get the firmware type
			local typeFirmware = string.byte(data, 11)
			if (typeFirmware == 1)
				then
				log("Firmware type: Type1")
				firmtype = "Type1"
			elseif (typeFirmware == 2)
				then
				log("Firmware type: Type2")
				firmtype = "Type2"
			elseif (typeFirmware == 3)
				then
				log("Firmware type: Ext")
				firmtype = "Ext"
			elseif (typeFirmware == 4)
				then
				log("Firmware type: Ext2")
				firmtype = "Ext2"
			else
				log("Unknown firmware type")
				firmtype = "Unknown"
			end
			setVariable(THIS_DEVICE, tabVars.VAR_FIRMWARE_TYPE, firmtype)
			-- Get the hardware version ;
			--  the major and minor versions
			hardware = string.byte(data, 8) .. "." .. string.byte(data, 9)
			log("Hardware version: " .. hardware)
			setVariable(THIS_DEVICE, tabVars.VAR_HARDWARE_VERSION, hardware)

			log("RFXtrx setup to receive protocols:")
			local msg3 = string.byte(data, 4)
			local msg4 = string.byte(data, 5)
			local msg5 = string.byte(data, 6)
			local msg6 = string.byte(data, 7)

			local isEnabled = (bitw.band(msg3, 0x80) == 0x80)
			setVariable(THIS_DEVICE, tabVars.VAR_UNDECODED_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - Undecoded")
			end
			isEnabled = (bitw.band(msg3, 0x40) == 0x40)
			setVariable(THIS_DEVICE, tabVars.VAR_IMAGINTRONIX_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - Byron SX")
			end
			isEnabled = (bitw.band(msg3, 0x20) == 0x20)
			setVariable(THIS_DEVICE, tabVars.VAR_BYRONSX_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - Byron SX")
			end
			isEnabled = (bitw.band(msg3, 0x10) == 0x10)
			setVariable(THIS_DEVICE, tabVars.VAR_RSL_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - RSL")
			end
			isEnabled = (bitw.band(msg3, 0x08) == 0x08)
			setVariable(THIS_DEVICE, tabVars.VAR_LIGHTING4_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - Lighting4")
			end
			isEnabled = (bitw.band(msg3, 0x04) == 0x04)
			setVariable(THIS_DEVICE, tabVars.VAR_FINEOFFSET_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - FineOffset / Viking")
			end
			isEnabled = (bitw.band(msg3, 0x02) == 0x02)
			setVariable(THIS_DEVICE, tabVars.VAR_RUBICSON_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - Rubicson")
			end
			isEnabled = (bitw.band(msg3, 0x01) == 0x01)
			setVariable(THIS_DEVICE, tabVars.VAR_AE_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - AE (Blyss)")
			end

			isEnabled = (bitw.band(msg4, 0x80) == 0x80)
			setVariable(THIS_DEVICE, tabVars.VAR_BLINDST1_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - Hasta (old) / A-OK / Raex / Media Mount")
			end
			isEnabled = (bitw.band(msg4, 0x40) == 0x40)
			setVariable(THIS_DEVICE, tabVars.VAR_BLINDST0_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - RollerTrol / Hasta (new)")
			end
			isEnabled = (bitw.band(msg4, 0x20) == 0x20)
			setVariable(THIS_DEVICE, tabVars.VAR_PROGUARD_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - ProGuard")
			end
			isEnabled = (bitw.band(msg4, 0x10) == 0x10)
			setVariable(THIS_DEVICE, tabVars.VAR_FS20_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - FS20")
			end
			isEnabled = (bitw.band(msg4, 0x08) == 0x08)
			setVariable(THIS_DEVICE, tabVars.VAR_LACROSSE_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - La Crosse")
			end
			isEnabled = (bitw.band(msg4, 0x04) == 0x04)
			setVariable(THIS_DEVICE, tabVars.VAR_HIDEKI_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - Hideki / UPM")
			end
			isEnabled = (bitw.band(msg4, 0x02) == 0x02)
			setVariable(THIS_DEVICE, tabVars.VAR_AD_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - AD (LightwaveRF)")
			end
			isEnabled = (bitw.band(msg4, 0x01) == 0x01)
			setVariable(THIS_DEVICE, tabVars.VAR_MERTIK_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - Mertik")
			end
			isEnabled = (bitw.band(msg5, 0x80) == 0x80)
			setVariable(THIS_DEVICE, tabVars.VAR_VISONIC_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - Visonic")
			end
			isEnabled = (bitw.band(msg5, 0x40) == 0x40)
			setVariable(THIS_DEVICE, tabVars.VAR_ATI_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - ATI")
			end
			isEnabled = (bitw.band(msg5, 0x20) == 0x20)
			setVariable(THIS_DEVICE, tabVars.VAR_OREGON_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - Oregon Scientific")
			end
			isEnabled = (bitw.band(msg5, 0x10) == 0x10)
			setVariable(THIS_DEVICE, tabVars.VAR_MEIANTECH_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - Meiantech")
			end
			isEnabled = (bitw.band(msg5, 0x08) == 0x08)
			setVariable(THIS_DEVICE, tabVars.VAR_HEU_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - HomeEasy EU")
			end
			isEnabled = (bitw.band(msg5, 0x04) == 0x04)
			setVariable(THIS_DEVICE, tabVars.VAR_AC_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - AC")
			end
			isEnabled = (bitw.band(msg5, 0x02) == 0x02)
			setVariable(THIS_DEVICE, tabVars.VAR_ARC_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - ARC")
			end
			isEnabled = (bitw.band(msg5, 0x01) == 0x01)
			setVariable(THIS_DEVICE, tabVars.VAR_X10_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - X10")
			end
			isEnabled = (bitw.band(msg6, 0x02) == 0x02)
			setVariable(THIS_DEVICE, tabVars.VAR_HOMECONFORT_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - Homeconfort")
			end
			isEnabled = (bitw.band(msg6, 0x01) == 0x01)
			setVariable(THIS_DEVICE, tabVars.VAR_KEELOQ_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - Keeloq")
			end
			--tableCmds = { { "", "", nil, 0 } }
		elseif (cmd == 0x6)
			then
			log("Receiving modes saved in non-volatile memory")
			--tableCmds = { { "", "", nil, 0 } }
		else
			error("Response to an unexpected mode command: " .. cmd)
		end
	elseif (subType == tableMsgTypes.UNKNOWN_RTS_REMOTE.subType)
		then
		warning("Unknown RTS remote")
		--tableCmds = { { "", "", nil, 0 } }
	elseif (subType == tableMsgTypes.WRONG_COMMAND.subType)
		then
		warning("Wrong command received")
		--tableCmds = { { "", "", nil, 0 } }
	else
		error("Unexpected subtype for response on a command: " .. subType)
	end

	return tableCmds

end

local function decodeLighting1(subType, data)

	local altid2 = string.format("L1.%X/%s", subType, string.sub(data, 1, 1))
	local altid = altid2 .. string.format("%02d", string.byte(data, 2))

	local tableCmds = {}
	local cmdCode = string.byte(data, 3)
	if (cmdCode == 0)
		then
		-- OFF => scene number from 1 to 16
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_OFF, nil, 0 ) )
		if (subType == 0 or subType == 1 or subType == 7 or subType == 8)
			then
			table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_OFF, string.byte(data, 2), 0 ) )
		end
	elseif (cmdCode == 1)
		then
		-- ON => scene number from 1 to 16
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ON, nil, 0 ) )
		if (subType == 0 or subType == 1 or subType == 7 or subType == 8)
			then
			table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_ON, string.byte(data, 2), 0 ) )
		end
	elseif (cmdCode == 2)
		then
		-- DIM => scene number 102
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_ON, 102, 0 ) )
	elseif (cmdCode == 3)
		then
		-- BRIGHT => scene number 103
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_ON, 103, 0 ) )
	elseif (cmdCode == 5)
		then
		-- GROUP OFF => scene number 100
		table.insert(tableCmds, DeviceCmd(altid2, tableCommandTypes.CMD_SCENE_OFF, 100, 0 ) )
	elseif (cmdCode == 6)
		then
		-- GROUP ON => scene number 100
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_ON, 100, 0 ) )
	elseif (cmdCode == 7)
		then
		-- CHIME => scene number from 131 to 146
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_ON, string.byte(data, 2) + 130, 0 ) )
	else
		warning("Lighting1 unexpected command: " .. cmdCode)
	end

	return tableCmds

end

local function decodeLighting2(subType, data)

	local altid2 = "L2." .. subType .. "/"
	.. string.format("%X", bitw.band(string.byte(data, 1), 0x03))
	.. string.format("%02X", string.byte(data, 2))
	.. string.format("%02X", string.byte(data, 3))
	.. string.format("%02X", string.byte(data, 4))
	local altid = altid2 .. "/" .. string.format("%02d", string.byte(data, 5))

	local tableCmds = {}
	local cmdCode = string.byte(data, 6)
	if (cmdCode == 0)
		then
		-- OFF => scene number from 1 to 16
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_OFF, nil, 0 ) )
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_OFF, string.byte(data, 5), 0 ) )
	elseif (cmdCode == 1)
		then
		-- ON => scene number from 1 to 16
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ON, nil, 0 ) )
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_ON, string.byte(data, 5), 0 ) )
	elseif (cmdCode == 2)
		then
		-- SET LEVEL => scene number from 17 to 32
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_DIM, math.floor((string.byte(data, 7) + 1) * 100 / 0x10 + 0.5), 0 ) )
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_ON, string.byte(data, 5) + 16, 0 ) )
	elseif (cmdCode == 3)
		then
		-- GROUP OFF => scene number 100
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_OFF, 100, 0 ) )
	elseif (cmdCode == 4)
		then
		-- GROUP ON => scene number 100
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_ON, 100, 0 ) )
	elseif (cmdCode == 5)
		then
		-- GROUP LEVEL => scene number 101
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_ON, 101, 0 ) )
	else
		warning("Lighting2 unexpected command: " .. cmdCode)
	end

	return tableCmds

end

local function decodeLighting3(subType, data)

	local ids = {}
	local altid = "L3." .. subType .. "/"
	.. string.format("%X", bitw.band(string.byte(data, 1), 0x0F))
	if (bitw.band(string.byte(data, 2), 0x01) ~= 0)
		then
		table.insert(ids, 1)
	end
	if (bitw.band(string.byte(data, 2), 0x02) ~= 0)
		then
		table.insert(ids, 2)
	end
	if (bitw.band(string.byte(data, 2), 0x04) ~= 0)
		then
		table.insert(ids, 3)
	end
	if (bitw.band(string.byte(data, 2), 0x08) ~= 0)
		then
		table.insert(ids, 4)
	end
	if (bitw.band(string.byte(data, 2), 0x10) ~= 0)
		then
		table.insert(ids, 5)
	end
	if (bitw.band(string.byte(data, 2), 0x20) ~= 0)
		then
		table.insert(ids, 6)
	end
	if (bitw.band(string.byte(data, 2), 0x40) ~= 0)
		then
		table.insert(ids, 7)
	end
	if (bitw.band(string.byte(data, 2), 0x80) ~= 0)
		then
		table.insert(ids, 8)
	end
	if (bitw.band(string.byte(data, 3), 0x01) ~= 0)
		then
		table.insert(ids, 9)
	end
	if (bitw.band(string.byte(data, 3), 0x02) ~= 0)
		then
		table.insert(ids, 10)
	end

	local tableCmds = {}
	local cmd = nil
	local cmdValue = nil
	local cmdCode = string.byte(data, 4)
	--debug("Koppla message received with command code: " .. cmdCode)
	if (cmdCode == 0x1A)
		then
		cmd = tableCommandTypes.CMD_OFF
	elseif (cmdCode == 0x10)
		then
		cmd = tableCommandTypes.CMD_ON
	elseif (cmdCode >= 0x11 and cmdCode <= 0x19)
		then
		cmd = tableCommandTypes.CMD_DIM
		cmdValue = (cmdCode - 0x10) * 10
	else
		warning("Lighting3 command not yet implemented: " .. cmdCode)
	end

	if (ids ~= nil and #ids > 0)
		then
		for _, id in ipairs(ids)
			do
			if (cmd ~= nil)
				then
				table.insert(tableCmds, DeviceCmd( altid .. string.format("%02d", id), cmd, cmdValue, 0 ) )
			end
		end
	end

	return tableCmds

end

local function decodeLighting5(subType, data)

	local altid2 = "L5." .. subType .. "/"
	.. string.format("%02X", string.byte(data, 1))
	.. string.format("%02X", string.byte(data, 2))
	.. string.format("%02X", string.byte(data, 3))
	local altid = altid2 .. "/" .. string.format("%02d", string.byte(data, 4))

	local tableCmds = {}
	local cmdCode = string.byte(data, 5)
	if (cmdCode == 0)
		then
		-- OFF => scene number from 1 to 16
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_OFF, nil, 0 ) )
		if (subType == tableMsgTypes.LIGHTING_LIGHTWARERF.subType)
			then
			table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_LWRF_SCENE_OFF, string.byte(data, 4), 0 ) )
		elseif (subType ~= tableMsgTypes.LIGHTING_EMW100.subType)
			then
			table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_OFF, string.byte(data, 4), 0 ) )
		end
	elseif (cmdCode == 1)
		then
		-- ON => scene number from 1 to 16
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ON, nil, 0 ) )
		if (subType == tableMsgTypes.LIGHTING_LIGHTWARERF.subType)
			then
			table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_LWRF_SCENE_ON, string.byte(data, 4), 0 ) )
		elseif (subType ~= tableMsgTypes.LIGHTING_EMW100.subType)
			then
			table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_ON, string.byte(data, 4), 0 ) )
		end
	elseif (cmdCode == 2)
		then
		-- GROUP OFF => scene number 100
		if (subType == tableMsgTypes.LIGHTING_LIGHTWARERF.subType)
			then
			table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_LWRF_SCENE_OFF, 100, 0 ) )
		elseif (subType ~= tableMsgTypes.LIGHTING_EMW100.subType)
			then
			table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_OFF, 100, 0 ) )
		end
	elseif (cmdCode == 3)
		then
		if (subType == tableMsgTypes.LIGHTING_LIGHTWARERF.subType)
			then
			-- MOOD1 => scene number 111
			table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_LWRF_SCENE_ON, 111, 0 ) )
		elseif (subType ~= tableMsgTypes.LIGHTING_EMW100.subType)
			then
			-- GROUP ON => scene number 100
			table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_ON, 100, 0 ) )
		end
	elseif (cmdCode == 4)
		then
		-- MOOD2 => scene number 112
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_LWRF_SCENE_ON, 112, 0 ) )
	elseif (cmdCode == 5)
		then
		-- MOOD3 => scene number 113
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_LWRF_SCENE_ON, 113, 0 ) )
	elseif (cmdCode == 6)
		then
		-- MOOD4 => scene number 114
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_LWRF_SCENE_ON, 114, 0 ) )
	elseif (cmdCode == 7)
		then
		-- MOOD5 => scene number 115
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_LWRF_SCENE_ON, 115, 0 ) )
	elseif (cmdCode == 0x0A)
		then
		-- UNLOCK => scene number from 33 to 48
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_LWRF_SCENE_OFF, string.byte(data, 4) + 32, 0 ) )
	elseif (cmdCode == 0x0B)
		then
		-- LOCK => scene number from 33 to 48
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_LWRF_SCENE_ON, string.byte(data, 4) + 32, 0 ) )
	elseif (cmdCode == 0x0C)
		then
		-- ALL LOCK => scene number 105
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_LWRF_SCENE_ON, 105, 0 ) )
	elseif (cmdCode == 0x0F)
		then
		-- OPEN => scene number from 49 to 64
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_OPEN, nil, 0 ) )
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_LWRF_SCENE_ON, string.byte(data, 4) + 48, 0 ) )
	elseif (cmdCode == 0x0D)
		then
		-- CLOSE => scene number from 65 to 80
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_CLOSE, nil, 0 ) )
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_LWRF_SCENE_ON, string.byte(data, 4) + 64, 0 ) )
	elseif (cmdCode == 0x0E)
		then
		-- STOP => scene number from 81 to 96
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STOP, nil, 0 ) )
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_LWRF_SCENE_ON, string.byte(data, 4) + 80, 0 ) )
	elseif (cmdCode == 0x10)
		then
		-- SET LEVEL => scene number from 17 to 32
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_DIM, math.floor((string.byte(data, 6) + 1) * 100 / 0x20 + 0.5), 0 ) )
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_LWRF_SCENE_ON, string.byte(data, 4) + 16, 0 ) )
	else
		warning("Lighting5 unexpected command: " .. cmdCode)
	end

	return tableCmds

end

local function decodeLighting6(subType, data)

	local altid2 = "L6." .. subType .. "/"
	.. string.format("%02X", string.byte(data, 1))
	.. string.format("%02X", string.byte(data, 2))
	.. "/" .. string.sub(data, 3, 3)
	local altid = altid2 .. string.byte(data, 4)

	local tableCmds = {}
	local cmdCode = string.byte(data, 5)
	if (cmdCode == 0)
		then
		-- ON => scene number from 1 to 16
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ON, nil, 0 ) )
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_ON, string.byte(data, 4), 0 ) )
	elseif (cmdCode == 1)
		then
		-- OFF => scene number from 1 to 16
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_OFF, nil, 0 ) )
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_OFF, string.byte(data, 4), 0 ) )
	elseif (cmdCode == 2)
		then
		-- GROUP ON => scene number 100
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_ON, 100, 0 ) )
	elseif (cmdCode == 3)
		then
		-- GROUP OFF => scene number 100
		table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_SCENE_OFF, 100, 0 ) )
	else
		warning("Lighting6 unexpected command: " .. cmdCode)
	end

	return tableCmds

end

local function decodeCurtain(subType, data)

	local altid = "C" .. subType .. "/"	.. string.sub(data, 1, 1) .. string.format("%02d", string.byte(data, 2))
	local tableCmds = {}
	local cmd = nil
	local cmdCode = string.byte(data, 3)
	if (cmdCode == 0)
		then
		cmd = tableCommandTypes.CMD_OPEN
	elseif (cmdCode == 1)
		then
		cmd = tableCommandTypes.CMD_CLOSE
	elseif (cmdCode == 2)
		then
		cmd = tableCommandTypes.CMD_STOP
	else
		warning("Curtain command not yet implemented: " .. cmdCode)
	end
	if (cmd ~= nil)
		then
		table.insert(tableCmds, DeviceCmd( altid, cmd, nil, 0 ) )
	end

	return tableCmds

end

local function decodeBlind(subType, data)

	local altid = "B" .. subType .. "/"
	.. string.format("%02X", string.byte(data, 1))
	.. string.format("%02X", string.byte(data, 2))
	.. string.format("%02X", string.byte(data, 3))
	if (subType == tableMsgTypes.BLIND_T6.subType or subType == tableMsgTypes.BLIND_T7.subType)
		then
		altid = altid .. string.format("%X", bitw.rshift(string.byte(data, 4), 4))
	end
	altid = altid .. "/" .. string.format("%02d", bitw.band(string.byte(data, 4), 0x0F))

	local tableCmds = {}
	local cmd = nil
	local cmdCode = string.byte(data, 5)
	if (cmdCode == 0)
		then
		cmd = tableCommandTypes.CMD_OPEN
	elseif (cmdCode == 1)
		then
		cmd = tableCommandTypes.CMD_CLOSE
	elseif (cmdCode == 2)
		then
		cmd = tableCommandTypes.CMD_STOP
	else
		warning("Blind command not yet implemented: " .. cmdCode)
	end
	if (cmd ~= nil)
		then
		table.insert(tableCmds, DeviceCmd( altid, cmd, nil, 0 ) )
	end

	return tableCmds

end

local function decodeThermostat3(subType, data)

	local altid = "HT3." .. subType .. "/"
	.. string.format("%02X", string.byte(data, 1))
	.. string.format("%02X", string.byte(data, 2))
	.. string.format("%02X", string.byte(data, 3))

	local tableCmds = {}
	local cmdCode = string.byte(data, 4)

	-- 0: "Off", 1: "On", 2: "Up", 3: "Down", 4: "Run Up/2nd Off", 5: "Run Down/2nd On", 6: "Stop"
	if (cmdCode == 0x00)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HEATER_SW, 0, 0 ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HEATER, "Off", 0 ) )
	elseif (cmdCode == 0x01)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HEATER_SW, 1, 0 ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HEATER, "HeatOn", 0 ) )
	elseif (cmdCode == 0x02)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HEATER_UP, nil, 0 ) )
	elseif (cmdCode == 0x03)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HEATER_DOWN, nil, 0 ) )
	elseif (cmdCode == 0x04)
		then
		if (subType == 0x00)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HEATER, "HeatOn", 0 ) )
		else
			--table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HEATER_2NDOFF, 0, 0 ) )
		end
	elseif (cmdCode == 0x05)
		then
		if (subType == 0x00)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HEATER, "Off", 0 ) )
		else
			--table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HEATER_2NDON, 0, 0 ) )
		end
	elseif (cmdCode == 0x06) and (subType == 0x00)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HEATER, "Off", 0 ) )
	else
		warning("Thermostat3 command not yet implemented: " .. cmdCode)
	end

	return tableCmds

end

local function decodeTemp(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "T" .. subType .. "/" .. id

	local tableCmds = {}
	local temp = decodeTemperature( altid, data, 3 )
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_TEMP, temp, 0 ) )

	-- Update if necessary the max and min temperatures detected by this device
	checkMaxMinTemp( altid, tableCmds, temp )

	local strength = bitw.rshift(string.byte(data, 5), 4)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	local battery = decodeBatteryLevel(data, 5)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeHum(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "H" .. subType .. "/" .. id

	local tableCmds = {}

	local hum = string.byte(data, 3)
	-- Ignore humidity greater than 100 - must be an error
	if(hum < 100)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HUM, hum, 0 ) )

		-- Update if necessary the max and min humidity detected by this device
		checkMaxMinHum( altid, tableCmds, hum )
	else
		debug("Dubious humidity reading: " .. hum .. "%" .. " altid=" .. altid .. " status=")
	end

	local strength = bitw.rshift(string.byte(data, 5), 4)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	local battery = decodeBatteryLevel(data, 5)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeTempHum(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "TH" .. subType .. "/" .. id

	local tableCmds = {}

	local temp = decodeTemperature( altid, data, 3 )
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_TEMP, temp, 0 ) )

	-- Update if necessary the max and min temperatures detected by this device
	checkMaxMinTemp( altid, tableCmds, temp )

	-- Now handle the humidity data
	local hum = string.byte(data, 5)
	-- Ignore humidity greater than 100 - must be an error
	if(hum < 100)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HUM, hum, 0 ) )

		-- Update if necessary the max and min humidity detected by this device
		checkMaxMinHum( altid, tableCmds, hum )
	else
		debug("Dubious humidity reading: " .. hum .. " altid=" .. altid .. " status=")
	end

	local strength = bitw.rshift(string.byte(data, 7), 4)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	local battery = decodeBatteryLevel(data, 7)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeBaro(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "B" .. subType .. "/" .. id

	local tableCmds = {}

	local baro = string.byte(data, 3) * 256 + string.byte(data, 4)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_PRESSURE, baro, 0 ) )

	local forecast = string.byte(data, 5)
	local strForecast = nil
	if (forecast == 1)
		then
		strForecast = "sunny"
	elseif (forecast == 2)
		then
		strForecast = "partly cloudy"
	elseif (forecast == 3)
		then
		strForecast = "cloudy"
	elseif (forecast == 4)
		then
		strForecast = "rain"
	end
	if (strForecast ~= nil)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_FORECAST, strForecast, 0 ) )
	end

	local strength = bitw.rshift(string.byte(data, 6), 4)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	local battery = decodeBatteryLevel(data, 6)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeTempHumBaro(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "THB" .. subType .. "/" .. id

	local tableCmds = {}

	local temp = decodeTemperature( altid, data, 3 )
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_TEMP, temp, 0 ) )

	-- Update if necessary the max and min temperatures detected by this device
	checkMaxMinTemp( altid, tableCmds, temp )

	local hum = string.byte(data, 5)
	-- Ignore humidity greater than 100 - must be an error
	if(hum < 100)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HUM, hum, 0 ) )

		-- Update if necessary the max and min humidity detected by this device
		checkMaxMinHum( altid, tableCmds, hum )
	else
		debug("Dubious humidity reading: " .. hum .. " altid=" .. altid .. " status=")
	end
	local baro = string.byte(data, 7) * 256 + string.byte(data, 8)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_PRESSURE, baro, 0 ) )

	local forecast = string.byte(data, 9)
	local strForecast = nil
	if (forecast == 1)
		then
		strForecast = "sunny"
	elseif (forecast == 2)
		then
		strForecast = "partly cloudy"
	elseif (forecast == 3)
		then
		strForecast = "cloudy"
	elseif (forecast == 4)
		then
		strForecast = "rain"
	end
	if (strForecast ~= nil)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_FORECAST, strForecast, 0 ) )
	end

	local strength = bitw.rshift(string.byte(data, 10), 4)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	local battery = decodeBatteryLevel(data, 10)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeRain(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "R" .. subType .. "/" .. id

	local tableCmds = {}
	local rainReading = 0
	local rainDiff = 0
	-- Most rain gauges report readings in mm
	--  and we'll store all data this way
	local readingConversionFactor = 1.0
	local lengthUnit = getVariable(THIS_DEVICE, tabVars.VAR_LENGTH_UNIT)
	local lengthConversionFactor = 1.0
	local unitsSpecifier = " mm"
	if (not lengthUnit) then
		lengthConversionFactor = mm2inch
		unitsSpecifier = " in"
	end
	if (subType ~= tableMsgTypes.RAIN6.subType)
		then
		rainReading = (string.byte(data, 5) * 65536 + string.byte(data, 6) * 256 + string.byte(data, 7)) / 10
	else
		rainReading = string.byte(data, 7)
	end
	-- Determine the device number of the rain sensor
	local deviceNum = findChild(THIS_DEVICE, altid, tableDeviceTypes.RAIN.deviceType)
	-- If the device doesn't exist just save the rain amount so it will be created
	--   if autocreate is on
	if (deviceNum == nil) then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAIN, rainReading, 0 ) )
	else
		-- Get the last reading
		local previousRain = getVariable(deviceNum, tabVars.VAR_RAIN)
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAIN, rainReading, 0 ) )
		if(previousRain ~= nil) then
			--Get the old battery time
			local previousSeconds = getVariable(deviceNum, tabVars.VAR_BATTERY_DATE)
			local previousTime  = {}
			previousTime = os.date("*t", previousSeconds)
			--Get the current time
			local currentSeconds = os.time()
			local currentTime  = {}
			currentTime = os.date("*t", currentSeconds)
			-- Determine the difference between this reading and the last
			rainDiff = rainReading - previousRain
			-- If this is a LaCrosse TX5 calculate mm
			if (subType == tableMsgTypes.RAIN6.subType) then
				readingConversionFactor = LacrosseMMPerCount
				if(rainDiff < 0) then
					rainDiff = rainDiff + 16.0
				end
			end
			rainDiff = rainDiff * readingConversionFactor
			-- Get the saved rain data into tables
			local rainByMinute  = getRainTableData(deviceNum, tabVars.VAR_RAINBYMINUTE, 60)
			local rainByHour = getRainTableData(deviceNum, tabVars.VAR_RAINBYHOUR, 24)
			local rainByWkDay = getRainTableData(deviceNum, tabVars.VAR_RAINBYDAY, 7)
			local rainByWeek = getRainTableData(deviceNum, tabVars.VAR_RAINBYWEEK, 52)
			local rainByMonth = getRainTableData(deviceNum, tabVars.VAR_RAINBYMONTH, 12)

			-- calculate the differences in the date and time components
			local yearDiff = currentTime["year"] - previousTime["year"]
			local monthDiff = indexDiff(previousTime["month"], currentTime["month"], 12)
			local currentWeek = weekOfYear(currentTime["year"], currentTime["yday"])
			local previousWeek = weekOfYear(previousTime["year"], previousTime["yday"])
			local weekDiff = indexDiff(previousWeek, currentWeek, 52)
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_CURRENTWEEK, currentWeek, 0 ) )
			local dayDiff
			if(isLeapYear(previousTime["year"])) then
				dayDiff = indexDiff(previousTime["yday"], currentTime["yday"], 366)
			else
				dayDiff = indexDiff(previousTime["yday"], currentTime["yday"], 365)
			end
			local hourDiff = indexDiff(previousTime["hour"], currentTime["hour"], 24)
			local minuteDiff = indexDiff(previousTime["min"], currentTime["min"], 60)
			-- Determine if any of the rain data needs to be cleared (has expired)
			if((yearDiff>1) or ((yearDiff > 0) and (previousTime["month"] <= currentTime["month"])))
				then
				resetRainTable(rainByMonth, #rainByMonth)
				resetRainTable(rainByWeek, #rainByWeek)
				resetRainTable(rainByWkDay, #rainByWkDay)
				resetRainTable(rainByHour, #rainByHour)
				resetRainTable(rainByMinute, #rainByMinute)
			else
				if(monthDiff ~= 0) then
					resetRainData(previousTime["month"]+1, currentTime["month"], rainByMonth)
				end
				if(weekDiff ~= 0) then
					resetRainData(previousWeek+1, currentWeek, rainByWeek)
				end
				if(dayDiff > 7) then
					resetRainTable(rainByWkDay, #rainByWkDay)
				elseif(dayDiff ~= 0) then
					resetRainData(previousTime["wday"]+1, currentTime["wday"], rainByWkDay)
				end
				if((dayDiff>1) or ((dayDiff > 0) and (previousTime["hour"] <= currentTime["hour"])))
					then
					resetRainTable(rainByHour, #rainByHour)
					resetRainTable(rainByMinute, #rainByMinute)
				elseif(hourDiff > 0) then
					resetRainData(previousTime["hour"]+2, currentTime["hour"]+1, rainByHour)
				end
				if((hourDiff > 1)  or ((hourDiff > 0) and (previousTime["min"] <= currentTime["min"])))
					then
					resetRainTable(rainByMinute, #rainByMinute)
				elseif(minuteDiff > 0) then
					resetRainData(previousTime["min"]+2, currentTime["min"]+1, rainByMinute)
				end
			end

			if(rainDiff > 0.0)
				then
				rainByMonth[currentTime["month"]] = rainByMonth[currentTime["month"]] + rainDiff
				rainByWeek[currentWeek] = rainByWeek[currentWeek] + rainDiff
				rainByWkDay[currentTime["wday"]] = rainByWkDay[currentTime["wday"]] + rainDiff
				rainByHour[currentTime["hour"]+1] = rainByHour[currentTime["hour"]+1] + rainDiff
				rainByMinute[currentTime["min"]+1] = rainByMinute[currentTime["min"]+1] + rainDiff
			end
			-- Calculate the rain over the last 24hours
			if(yearDiff+monthDiff+weekDiff+hourDiff+rainDiff ~= 0) then
				local rain24Hrs = 0.0
				for _, v in ipairs(rainByHour)
					do
					rain24Hrs = rain24Hrs + v
				end
				table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAIN24HRS, string.format("%4.2f%s", (rain24Hrs * lengthConversionFactor), unitsSpecifier), 0 ) )
			end

			--			if(DEBUG_MODE) then
			--				debug("               year yday wk m d hr mm ss wday")
			--				debug("previous time: " .. previousTime["year"] .. " " .. previousTime["yday"] .. " " .. previousWeek .. " " .. previousTime["month"] .. " " .. previousTime["day"] .. " " .. previousTime["hour"] .. " " .. previousTime["min"] .. " " .. previousTime["sec"] .. " " .. previousTime["wday"])
			--				debug("current time:  " .. currentTime["year"] .. " " .. currentTime["yday"] .. " " .. currentWeek .. " " .. currentTime["month"] .. " " .. currentTime["day"] .. " " .. currentTime["hour"] .. " " .. currentTime["min"] .. " " .. currentTime["sec"] .. " " .. currentTime["wday"])
			--				debug("Rain this minute: " .. currentTime["min"] .. " " .. rainByMinute[currentTime["min"]+1])
			--				debug("Rain by Minute: " .. recursiveConcat(rainByMinute))
			--				debug("Rain this hour: " .. currentTime["hour"] .. " " .. rainByHour[currentTime["hour"]+1])
			--				debug("Rain by Hour: " .. recursiveConcat(rainByHour))
			--				debug("Rain this day: " .. currentTime["wday"] .. " " .. rainByWkDay[currentTime["wday"]])
			--				debug("Rain by Day: " .. recursiveConcat(rainByWkDay))
			--				debug("Rain this week: " .. currentWeek .. " " .. rainByWeek[currentWeek])
			--				debug("Rain by Week: " .. recursiveConcat(rainByWeek))
			--				debug("Rain this month: " .. currentTime["month"] .. " " .. rainByMonth[currentTime["month"]])
			--				debug("Rain by Month: " .. recursiveConcat(rainByMonth))
			--			end

			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAINBYMONTH, recursiveConcat(rainByMonth), 0 ) )
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAINBYWEEK, recursiveConcat(rainByWeek), 0 ) )
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAINBYDAY, recursiveConcat(rainByWkDay), 0 ) )
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAINBYHOUR, recursiveConcat(rainByHour), 0 ) )
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAINBYMINUTE, recursiveConcat(rainByMinute), 0 ) )
			local rate = nil
			if (subType == tableMsgTypes.RAIN1.subType)
				then
				rate = string.byte(data, 3) * 256 + string.byte(data, 4)
			elseif (subType == tableMsgTypes.RAIN2.subType)
				then
				rate = (string.byte(data, 3) * 256 + string.byte(data, 4)) / 100
			end
			if (rate ~= nil)
				then
				table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAINRATE, rate, 0 ) )
			else
				-- Calculate the rain rate based on the last two readings
				local elapsedSeconds = currentSeconds - previousSeconds
				if(elapsedSeconds > 0)
					then
					local periodsPerHour = 3600 / elapsedSeconds
					rate = periodsPerHour * rainDiff
					table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAINRATE, rate, 0 ) )
				else
					table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAINRATE, 0, 0 ) )
				end
			end
		end
	end

	local strength = bitw.rshift(string.byte(data, 8), 4)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	local battery = decodeBatteryLevel(data, 8)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeTempRain(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "TR" .. subType .. "/" .. id

	local tableCmds = {}

	local temp = decodeTemperature( altid, data, 3 )
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_TEMP, temp, 0 ) )

	-- Update if necessary the max and min temperatures detected by this device
	checkMaxMinTemp( altid, tableCmds, temp )

	local total = (string.byte(data, 5) * 256 + string.byte(data, 6)) / 10
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAIN, total, 0 ) )

	local strength = bitw.rshift(string.byte(data, 7), 4)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	local battery = decodeBatteryLevel(data, 7)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeWind(subType, data)

	local unitKmh = (getVariable(THIS_DEVICE, tabVars.VAR_SPEED_UNIT))

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "W" .. subType .. "/" .. id

	local tableCmds = {}

	local direction = string.byte(data, 3) * 256 + string.byte(data, 4)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_DIRECTION, direction, 0 ) )

	if (subType ~= tableMsgTypes.WIND5.subType)
		then
		local avgSpeed = (string.byte(data, 5) * 256 + string.byte(data, 6)) / 10
		-- Convert m/s to km/h or mph and keep an integer
		if (unitKmh)
			then
			avgSpeed = math.floor(avgSpeed * 3.6 + 0.5)
		else
			avgSpeed = math.floor(avgSpeed * 3.6 * 0.62137 + 0.5)
		end
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_WIND, avgSpeed, 0 ) )
	end

	local gust = (string.byte(data, 7) * 256 + string.byte(data, 8)) / 10
	-- Convert m/s to km/h or mph and keep an integer
	if (unitKmh)
		then
		gust = math.floor(gust * 3.6 + 0.5)
	else
		gust = math.floor(gust * 3.6 * 0.62137 + 0.5)
	end
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_GUST, gust, 0 ) )

	if (subType == tableMsgTypes.WIND4.subType)
		then
		local temp = decodeTemperature( altid, data, 9 )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_TEMP, temp, 0 ) )
		-- Update if necessary the max and min temperatures detected by this device
		checkMaxMinTemp( altid, tableCmds, temp )
	end

	local strength = bitw.rshift(string.byte(data, 13), 4)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	local battery = decodeBatteryLevel(data, 13)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeUV(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "U" .. subType .. "/" .. id

	local tableCmds = {}

	local uv = string.byte(data, 3) / 10
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_UV, uv, 0 ) )

	if (subType == tableMsgTypes.UV3.subType)
		then
		local temp = decodeTemperature( altid, data, 4 )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_TEMP, temp, 0 ) )
		-- Update if necessary the max and min temperatures detected by this device
		checkMaxMinTemp( altid, tableCmds, temp )
	end

	local strength = bitw.rshift(string.byte(data, 6), 4)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	local battery = decodeBatteryLevel(data, 6)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeWeight(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "WT" .. subType .. "/" .. id

	local tableCmds = {}

	local weight = (string.byte(data, 3) * 256 + string.byte(data, 4)) / 10
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_WEIGHT, weight, 0 ) )

	local impedance = nil

	-- Impedance is not supported by the current RFXtrx firmware (v50)

	if (impedance ~= nil)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_IMPEDANCE, impedance, 0 ) )
	end

	-- local strength = bitw.rshift(string.byte(data, 5), 4)

	local battery = decodeBatteryLevel(data, 5)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

-- This function is for door sensors that only transmit when tripped
--  they do not transmit when the door is again closed.
local function decodeSecurity(subType, data)

	-- For a PT2262 type device the first 20 bits are fixed
	-- the last 4 bits could be a status
	local altid = "D/" .. string.format("%02X", string.byte(data, 1))
	.. string.format("%02X", string.byte(data, 2))
	.. string.format("%1X", bitw.rshift(string.byte(data, 3), 4))
	--	.. string.format("%02X", string.byte(data, 3))

	local tableCmds = {}
	-- Since many devices only transmit 'door opened', default the command value to 1
	local cmdValue = 1
	local cmd = tableCommandTypes.CMD_DOOR
	local cmdCode = bitw.band(string.byte(data, 3), 0x0F)

	debug("decodeSecurity: " .. subType .. " altid=" .. altid .. " status=" .. string.format("%02X", cmdCode))

	table.insert(tableCmds, DeviceCmd( altid, cmd, cmdValue, 0 ) )

	local strength = bitw.rshift(string.byte(data, 6), 4)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	-- Don't know if these devices send battery status
	--local battery = decodeBatteryLevel(data, 5)
	--table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end
-- Determine if we need to set or clear the tampered state
-- Attempting to do anything with the HaDevice sl_tamper variable results in
--  unexpected behavior. I wonder if anyone at Vera knows how this works.
local function handleTamperSwitch(altid, deviceType, tampered, tableCmds)
	-- Get the device number
	local deviceNum = findChild(THIS_DEVICE, altid, deviceType)
	if((deviceNum ~= nil) and (tampered ~= nil)) then
		-- Get current state of tampered
		local wasTampered = getVariable(deviceNum, tabVars.VAR_TAMPERED)
		-- Get current state of armed
		local armed = getVariable(deviceNum, tabVars.VAR_ARMED)
		debug("handleTamper - armed: " .. (armed or 'nil') .. " wasTampered: ".. (wasTampered or 'nil') .. " tamperedNow: " .. (tampered or 'nil'))
		if(wasTampered ~= nil) then
			if(tonumber(wasTampered)>0) then wasTampered = 1 else wasTampered = 0 end
		end
		if(((wasTampered == nil) or (wasTampered == 0)) and (tampered == 1)) then
			if(armed ~= nil) then
				if(tonumber(armed)>0) then armed = 1 else armed = 0 end
				if(armed == 1) then
					debug("setting tampered")
					table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_TAMPERED, 1, 0 ))
				end
			end
		elseif((wasTampered ~= nil) and (wasTampered == 1) and (tampered == 0)) then
			debug("resetting tampered")
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_TAMPERED, 0, 0 ))
		end
		-- Get current state of tripped
		--local tripped = getVariable(deviceNum, tabVars.VAR_TRIPPED)
		-- Get current state of AutoUntrip
		--local autoUntrip = getVariable(deviceNum, tabVars.VAR_AUTOUNTRIP)
		-- Get last time tripped
		--local lastTrip = getVariable(deviceNum, tabVars.VAR_LAST_TRIP)
	end
	return tableCmds
end

local function decodeSecurityMS(subType, data)

	local altid = "M/" .. string.format("%02X", string.byte(data, 1))
	.. string.format("%02X", string.byte(data, 2))
	.. string.format("%02X", string.byte(data, 3))

	debug("decodeSecurityMS: " .. subType .. " altid=" .. altid .. " status=" .. string.byte(data, 4))

	local tableCmds = {}
	local cmd = nil
	local cmdValue = nil
	local cmdCode = bitw.band(string.byte(data, 4), 0x7F)
	local tampered = (bitw.band(string.byte(data, 4), 0x80))/128

	if (cmdCode == 0x04)
		then
		cmd = tableCommandTypes.CMD_MOTION
		cmdValue = "1"
	elseif (cmdCode == 0x05)
		then
		cmd = tableCommandTypes.CMD_MOTION
		cmdValue = "0"
	else
		if (cmdCode ~= nil)
			then
			warning("decodeSecurityMS command not yet implemented: " .. cmdCode .. "hex=" .. formattohex(cmdCode))
		else
			warning("decodeSecurityMS command not yet implemented")
		end
	end
	if (cmd ~= nil)
		then
		table.insert(tableCmds, DeviceCmd( altid, cmd, cmdValue, 0 ) )
		--		tableCmds = handleTamperSwitch(altid, tableDeviceTypes.MOTION.deviceType, tampered, tableCmds)
	end

	local battery = decodeBatteryLevel(data, 5)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeSecurityDS(subType, data)

	local altid = "D/" .. string.format("%02X", string.byte(data, 1))
	.. string.format("%02X", string.byte(data, 2))
	.. string.format("%02X", string.byte(data, 3))

	debug("decodeSecurityDS: " .. subType .. " altid=" .. altid .. " status=" .. string.byte(data, 4))

	local tableCmds = {}
	local cmd = nil
	local cmdValue = nil
	local cmdCode = bitw.band(string.byte(data, 4), 0x7F)
	local tampered = (bitw.band(string.byte(data, 4), 0x80))/128
	-- If the cmdCode is 4 or 5 then this is really a motion sensor
	if (cmdCode == 0x04 or cmdCode == 0x05) then
		tableCmds = decodeSecurityMS(subType, data)
	else
		if (cmdCode == 0x00 or cmdCode == 0x01)
			then
			cmd = tableCommandTypes.CMD_DOOR
			cmdValue = "0"
		elseif (cmdCode == 0x02 or cmdCode == 0x03)
			then
			cmd = tableCommandTypes.CMD_DOOR
			cmdValue = "1"
		else
			if (cmdCode ~= nil)
				then
				warning("decodeSecurityDS command not yet implemented: " .. cmdCode .. "hex=" .. formattohex(cmdCode))
			else
				warning("decodeSecurityDS command not yet implemented")
			end
		end
		if (cmd ~= nil)
			then
			table.insert(tableCmds, DeviceCmd( altid, cmd, cmdValue, 0 ) )
			--			tableCmds = handleTamperSwitch(altid, tableDeviceTypes.DOOR.deviceType, tampered, tableCmds)
		end

		local battery = decodeBatteryLevel(data, 5)
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )
	end

	return tableCmds

end

local function decodeSecurityRemote(subType, data)

	local tableCmds = {}
	local altid = ""
	local cmd = bitw.band(string.byte(data, 4), 0x7F)

	local exitDelay = 0

	local battery = decodeBatteryLevel(data, 5)

	if (subType == tableMsgTypes.SECURITY_X10SR.subType)
		then
		altid = "X10/SR/" .. string.format("%02X", string.byte(data, 1))
		.. string.format("%02X", string.byte(data, 2))
		.. string.format("%02X", string.byte(data, 3))

		local deviceNum = findChild(THIS_DEVICE, altid, tableDeviceTypes.ALARM.deviceType)
		if (deviceNum ~= nil)
			then
			exitDelay = tonumber(getVariable(deviceNum, tabVars.VAR_EXIT_DELAY) or "0")
		end
	elseif (subType == tableMsgTypes.SECURITY_MEISR.subType)
		then
		altid = "MEI/SR/" .. string.format("%02X", string.byte(data, 1))
		.. string.format("%02X", string.byte(data, 2))
		.. string.format("%02X", string.byte(data, 3))
	elseif (subType == tableMsgTypes.KD101.subType)
		then
		altid = "KD1/SR/" .. string.format("%02X", string.byte(data, 1))
		.. string.format("%02X", string.byte(data, 2))
		.. string.format("%02X", string.byte(data, 3))

		battery = -1
	elseif (subType == tableMsgTypes.SA30.subType)
		then
		altid = "S30/SR/" .. string.format("%02X", string.byte(data, 1))
		.. string.format("%02X", string.byte(data, 2))
		.. string.format("%02X", string.byte(data, 3))

		battery = -1
	end

	if ((cmd == 0x09 or cmd == 0x0A) and exitDelay > 0)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_DETAILED_ARM_MODE, "ExitDelay", 0 ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ARM_MODE, "Armed", exitDelay ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_DETAILED_ARM_MODE, "Armed", exitDelay ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ARM_MODE_NUM, "1", exitDelay ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ALARM_SCENE_ON, 121, 0 ) )
		if (battery >= 0 and battery <= 100)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )
		end
	elseif ((cmd == 0x09 or cmd == 0x0A) and exitDelay == 0)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ARM_MODE, "Armed", 0 ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_DETAILED_ARM_MODE, "Armed", 0 ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ARM_MODE_NUM, "1", 0 ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ALARM_SCENE_ON, 121, 0 ) )
		if (battery >= 0 and battery <= 100)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )
		end
	elseif ((cmd == 0x0B or cmd == 0x0C) and exitDelay > 0)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_DETAILED_ARM_MODE, "ExitDelay", 0 ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ARM_MODE, "Armed", exitDelay ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_DETAILED_ARM_MODE, "Stay", exitDelay ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ARM_MODE_NUM, "1", exitDelay ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ALARM_SCENE_ON, 122, 0 ) )
		if (battery >= 0 and battery <= 100)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )
		end
	elseif ((cmd == 0x0B or cmd == 0x0C) and exitDelay == 0)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ARM_MODE, "Armed", 0 ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_DETAILED_ARM_MODE, "Stay", 0 ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ARM_MODE_NUM, "1", 0 ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ALARM_SCENE_ON, 122, 0 ) )
		if (battery >= 0 and battery <= 100)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )
		end
	elseif (cmd == 0x0D)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ARM_MODE, "Disarmed", 0 ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_DETAILED_ARM_MODE, "Disarmed", 0 ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ARM_MODE_NUM, "0", 0 ) )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ALARM_SCENE_ON, 123, 0 ) )
		if (battery >= 0 and battery <= 100)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )
		end
	elseif (cmd == 0x06)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ALARM_SCENE_ON, 120, 0 ) )
		if (battery >= 0 and battery <= 100)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )
		end
		if (subType == tableMsgTypes.KD101.subType or subType == tableMsgTypes.SA30.subType)
			then
			if (subType == tableMsgTypes.KD101.subType)
				then
				altid = "KD1/SS/" .. string.format("%02X", string.byte(data, 1))
				.. string.format("%02X", string.byte(data, 2))
				.. string.format("%02X", string.byte(data, 3))
			else
				altid = "S30/SS/" .. string.format("%02X", string.byte(data, 1))
				.. string.format("%02X", string.byte(data, 2))
				.. string.format("%02X", string.byte(data, 3))
			end
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_SMOKE, "1", 0 ) )
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_SMOKE_OFF, nil, 30 ) )
			if (battery >= 0 and battery <= 100)
				then
				table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )
			end
		end
	elseif (cmd == 0x07)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ALARM_SCENE_OFF, 120, 0 ) )
		if (battery >= 0 and battery <= 100)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )
		end
		if (subType == tableMsgTypes.KD101.subType or subType == tableMsgTypes.SA30.subType)
			then
			if (subType == tableMsgTypes.KD101.subType)
				then
				altid = "KD1/SS/" .. string.format("%02X", string.byte(data, 1))
				.. string.format("%02X", string.byte(data, 2))
				.. string.format("%02X", string.byte(data, 3))
			else
				altid = "S30/SS/" .. string.format("%02X", string.byte(data, 1))
				.. string.format("%02X", string.byte(data, 2))
				.. string.format("%02X", string.byte(data, 3))
			end
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_SMOKE, "0", 0 ) )
			if (battery >= 0 and battery <= 100)
				then
				table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )
			end
		end
	elseif (cmd == 0x10)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ALARM_SCENE_OFF, 1, 0 ) )
		if (battery >= 0 and battery <= 100)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )
		end
		altid = "X10/L1/" .. string.format("%02X", string.byte(data, 1))
		.. string.format("%02X", string.byte(data, 2))
		.. string.format("%02X", string.byte(data, 3))
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_OFF, nil, 0 ) )
	elseif (cmd == 0x11)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ALARM_SCENE_ON, 1, 0 ) )
		if (battery >= 0 and battery <= 100)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )
		end
		altid = "X10/L1/" .. string.format("%02X", string.byte(data, 1))
		.. string.format("%02X", string.byte(data, 2))
		.. string.format("%02X", string.byte(data, 3))
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ON, nil, 0 ) )
	elseif (cmd == 0x12)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ALARM_SCENE_OFF, 2, 0 ) )
		if (battery >= 0 and battery <= 100)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )
		end
		altid = "X10/L2/" .. string.format("%02X", string.byte(data, 1))
		.. string.format("%02X", string.byte(data, 2))
		.. string.format("%02X", string.byte(data, 3))
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_OFF, nil, 0 ) )
	elseif (cmd == 0x13)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ALARM_SCENE_ON, 2, 0 ) )
		if (battery >= 0 and battery <= 100)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )
		end
		altid = "X10/L2/" .. string.format("%02X", string.byte(data, 1))
		.. string.format("%02X", string.byte(data, 2))
		.. string.format("%02X", string.byte(data, 3))
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ON, nil, 0 ) )
	elseif (cmd == 0x16)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )
	elseif (cmd == 0x17)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ALARM_SCENE_ON, 124, 0 ) )
		if (subType == tableMsgTypes.KD101.subType or subType == tableMsgTypes.SA30.subType)
			then
			if (subType == tableMsgTypes.KD101.subType)
				then
				altid = "KD1/SS/" .. string.format("%02X", string.byte(data, 1))
				.. string.format("%02X", string.byte(data, 2))
				.. string.format("%02X", string.byte(data, 3))
			else
				altid = "S30/SS/" .. string.format("%02X", string.byte(data, 1))
				.. string.format("%02X", string.byte(data, 2))
				.. string.format("%02X", string.byte(data, 3))
			end
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_SMOKE, "0", 0 ) )
		end
	else
		warning("x10securityRemote command not yet implemented: " .. cmd .. "hex=" .. formattohex(cmd))
	end

	return tableCmds

end

local function decodeSecurityMeiantech(subType, data)

	local cmdCode = bitw.band(string.byte(data, 4), 0x7F)

	if (cmdCode == 0x00 or cmdCode == 0x02)
		then
		return decodeSecurityDS(subType, data)
	elseif (cmdCode == 0x04 or cmdCode == 0x05)
		then
		return decodeSecurityMS(subType, data)
	else
		return decodeSecurityRemote(subType, data)
	end

end

local function decodeRemote(subType, data)

	local altid = "RC" .. subType .. "/" .. string.format("%02X", string.byte(data, 1))
	local cmd = string.byte(data, 2)
	local tableCmds = {}
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ATI_SCENE_ON, cmd, 0 ) )

	return tableCmds

end

local function decodeElec1(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local num = tonumber(subType)
	local altid = "ELEC" .. num .. "/" .. id
	local altid1 = "ELEC" .. num .. "/" .. id .. "/1"
	local altid2 = "ELEC" .. num .. "/" .. id .. "/2"
	local altid3 = "ELEC" .. num .. "/" .. id .. "/3"
	local tableCmds = {}

	local voltage = tonumber(getVariable(THIS_DEVICE, tabVars.VAR_VOLTAGE) or "230") or 230

	local watt1 = math.floor((string.byte(data, 4) * math.pow(2, 8) + string.byte(data, 5)) / 10 * voltage + 0.5)
	table.insert(tableCmds, DeviceCmd( altid1, tableCommandTypes.CMD_WATT, watt1, 0 ) )

	local watt2 = math.floor((string.byte(data, 6) * math.pow(2, 8) + string.byte(data, 7)) / 10 * voltage + 0.5)
	table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_WATT, watt2, 0 ) )

	local watt3 = math.floor((string.byte(data, 8) * math.pow(2, 8) + string.byte(data, 9)) / 10 * voltage + 0.5)
	table.insert(tableCmds, DeviceCmd( altid3, tableCommandTypes.CMD_WATT, watt3, 0 ) )

	local watt = watt1 + watt2 + watt3
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_WATT, watt, 0 ) )

	-- local strength = bitw.rshift(string.byte(data, 10), 4)

	local battery = decodeBatteryLevel(data, 10)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeElec2Elec3(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local num = tonumber(subType) + 1
	local altid = "ELEC" .. num .. "/" .. id

	local tableCmds = {}

	local instant = string.byte(data, 4) * math.pow(2, 24) + string.byte(data, 5) * math.pow(2, 16)
	+ string.byte(data, 6) * math.pow(2, 8) + string.byte(data, 7)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_WATT, instant, 0 ) )

	if ((num == 2) or (string.byte(data, 3) == 0))
		then
		local kwh = math.floor((string.byte(data, 8) * math.pow(2, 40) + string.byte(data, 9) * math.pow(2, 32)
		+ string.byte(data, 10) * math.pow(2, 24) + string.byte(data, 11) * math.pow(2, 16)
		+ string.byte(data, 12) * math.pow(2, 8) + string.byte(data, 13)) / 223666 + 0.5)
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_KWH, kwh, 0 ) )
	end

	-- local strength = bitw.rshift(string.byte(data, 14), 4)

	local battery = decodeBatteryLevel(data, 14)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeElec4(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local num = tonumber(subType) + 3
	local altid = "ELEC" .. num .. "/" .. id
	local altid1 = "ELEC" .. num .. "/" .. id .. "/1"
	local altid2 = "ELEC" .. num .. "/" .. id .. "/2"
	local altid3 = "ELEC" .. num .. "/" .. id .. "/3"
	local tableCmds = {}

	local voltage = tonumber(getVariable(THIS_DEVICE, tabVars.VAR_VOLTAGE) or "230") or 230

	local watt1 = math.floor((string.byte(data, 4) * math.pow(2, 8) + string.byte(data, 5)) / 10 * voltage + 0.5)
	table.insert(tableCmds, DeviceCmd( altid1, tableCommandTypes.CMD_WATT, watt1, 0 ) )

	local watt2 = math.floor((string.byte(data, 6) * math.pow(2, 8) + string.byte(data, 7)) / 10 * voltage + 0.5)
	table.insert(tableCmds, DeviceCmd( altid2, tableCommandTypes.CMD_WATT, watt2, 0 ) )

	local watt3 = math.floor((string.byte(data, 8) * math.pow(2, 8) + string.byte(data, 9)) / 10 * voltage + 0.5)
	table.insert(tableCmds, DeviceCmd( altid3, tableCommandTypes.CMD_WATT, watt3, 0 ) )

	local watt = watt1 + watt2 + watt3
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_WATT, watt, 0 ) )

	if (string.byte(data, 3) == 0)
		then
		local kwh = math.floor((string.byte(data, 10) * math.pow(2, 40) + string.byte(data, 11) * math.pow(2, 32)
		+ string.byte(data, 12) * math.pow(2, 24) + string.byte(data, 13) * math.pow(2, 16)
		+ string.byte(data, 14) * math.pow(2, 8) + string.byte(data, 15)) / 223666 + 0.5)
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_KWH, kwh, 0 ) )
	end

	-- local strength = bitw.rshift(string.byte(data, 16), 4)

	local battery = decodeBatteryLevel(data, 16)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeRFXSensor(subType, data)

	local id = string.byte(data, 1)
	local altid = "RFXSENSOR" .. subType .. "/" .. id
	local tableCmds = {}

	if (subType == tableMsgTypes.RFXSENSOR_T.subType)
		then
		local temp = decodeTemperature( altid, data, 2 )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_TEMP, temp, 0 ) )
		-- Update if necessary the max and min temperatures detected by this device
		checkMaxMinTemp( altid, tableCmds, temp )
		local strength = bitw.rshift(string.byte(data, 4), 4)
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )
	else
		warning("RFXSensor subtype not yet implemented: " .. subType)
	end

	return tableCmds

end

local function decodeRFXMeter(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local num = tonumber(subType) + 1
	local altid = "RFXMETER" .. num .. "/" .. id
	local instant = 0.1
	local waarde = 0
	local multiplier = 1
	local tableCmds = {}

	local deviceNum = findChild(THIS_DEVICE, altid, tableDeviceTypes.RFXMETER.deviceType)
	if (deviceNum ~= nil)
		then
		waarde = getVariable(deviceNum, tabVars.VAR_OFFSET)
		if (waarde == nil)
			then
			waarde = 0
		end

		multiplier = getVariable(deviceNum, tabVars.VAR_MULT)
		if ((multiplier == nil) or (multiplier == 0))
			then
			multiplier = 1
		end
	end

	instant = (string.byte(data, 3) * math.pow(2, 24) + string.byte(data, 4) * math.pow(2, 16)
	+ string.byte(data, 5) * math.pow(2, 8) + string.byte(data, 6) + waarde)/multiplier

	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_PULSEN, instant, 0 ) )
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_OFFSET, waarde, 0 ) )
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_MULT, multiplier, 0 ) )

	return tableCmds

end

local function initDecodingFunctions()

	tableMsgTypes.RESPONSE_MODE_COMMAND.decodeFunction = decodeResponseMode
	tableMsgTypes.UNKNOWN_RTS_REMOTE.decodeFunction = decodeResponseMode
	tableMsgTypes.WRONG_COMMAND.decodeFunction = decodeResponseMode
	tableMsgTypes.RECEIVER_LOCK_ERROR.decodeFunction = decodeResponse
	tableMsgTypes.TRANSMITTER_RESPONSE.decodeFunction = decodeResponse
	tableMsgTypes.LIGHTING_X10.decodeFunction = decodeLighting1
	tableMsgTypes.LIGHTING_ARC.decodeFunction = decodeLighting1
	tableMsgTypes.LIGHTING_AB400D.decodeFunction = decodeLighting1
	tableMsgTypes.LIGHTING_WAVEMAN.decodeFunction = decodeLighting1
	tableMsgTypes.LIGHTING_EMW200.decodeFunction = decodeLighting1
	tableMsgTypes.LIGHTING_IMPULS.decodeFunction = decodeLighting1
	tableMsgTypes.LIGHTING_RISINGSUN.decodeFunction = decodeLighting1
	tableMsgTypes.LIGHTING_PHILIPS.decodeFunction = decodeLighting1
	tableMsgTypes.LIGHTING_ENERGENIE_ENER010.decodeFunction = decodeLighting1
	tableMsgTypes.LIGHTING_ENERGENIE_5GANG.decodeFunction = decodeLighting1
	tableMsgTypes.LIGHTING_COCO.decodeFunction = decodeLighting1
	tableMsgTypes.LIGHTING_AC.decodeFunction = decodeLighting2
	tableMsgTypes.LIGHTING_HEU.decodeFunction = decodeLighting2
	tableMsgTypes.LIGHTING_ANSLUT.decodeFunction = decodeLighting2
	tableMsgTypes.LIGHTING_KOPPLA.decodeFunction = decodeLighting3
	tableMsgTypes.SECURITY_DOOR.decodeFunction = decodeSecurity
	tableMsgTypes.LIGHTING_LIGHTWARERF.decodeFunction = decodeLighting5
	tableMsgTypes.LIGHTING_EMW100.decodeFunction = decodeLighting5
	tableMsgTypes.LIGHTING_BBSB.decodeFunction = decodeLighting5
	tableMsgTypes.LIGHTING_RSL2.decodeFunction = decodeLighting5
	tableMsgTypes.LIGHTING_KANGTAI.decodeFunction = decodeLighting5
	tableMsgTypes.LIGHTING_BLYSS.decodeFunction = decodeLighting6
	tableMsgTypes.CURTAIN_HARRISON.decodeFunction = decodeCurtain
	tableMsgTypes.BLIND_T0.decodeFunction = decodeBlind
	tableMsgTypes.BLIND_T1.decodeFunction = decodeBlind
	tableMsgTypes.BLIND_T2.decodeFunction = decodeBlind
	tableMsgTypes.BLIND_T3.decodeFunction = decodeBlind
	tableMsgTypes.BLIND_T4.decodeFunction = decodeBlind
	tableMsgTypes.BLIND_T5.decodeFunction = decodeBlind
	tableMsgTypes.BLIND_T6.decodeFunction = decodeBlind
	tableMsgTypes.BLIND_T7.decodeFunction = decodeBlind
	tableMsgTypes.SECURITY_X10DS.decodeFunction = decodeSecurityDS
	tableMsgTypes.SECURITY_X10MS.decodeFunction = decodeSecurityMS
	tableMsgTypes.SECURITY_X10SR.decodeFunction = decodeSecurityRemote
	tableMsgTypes.SECURITY_MEISR.decodeFunction = decodeSecurityMeiantech
	tableMsgTypes.KD101.decodeFunction = decodeSecurityRemote
	tableMsgTypes.POWERCODE_PRIMDS.decodeFunction = decodeSecurityDS
	tableMsgTypes.POWERCODE_AUXDS.decodeFunction = decodeSecurityDS
	tableMsgTypes.POWERCODE_MS.decodeFunction = decodeSecurityMS
	tableMsgTypes.SA30.decodeFunction = decodeSecurityRemote
	tableMsgTypes.ATI_REMOTE_WONDER.decodeFunction = decodeRemote
	tableMsgTypes.ATI_REMOTE_WONDER_PLUS.decodeFunction = decodeRemote
	tableMsgTypes.MEDION_REMOTE.decodeFunction = decodeRemote
	tableMsgTypes.X10_PC_REMOTE.decodeFunction = decodeRemote
	tableMsgTypes.ATI_REMOTE_WONDER_II.decodeFunction = decodeRemote
	tableMsgTypes.HEATER3_MERTIK1.decodeFunction = decodeThermostat3
	tableMsgTypes.HEATER3_MERTIK2.decodeFunction = decodeThermostat3
	tableMsgTypes.TR1.decodeFunction = decodeTempRain
	tableMsgTypes.TEMP1.decodeFunction = decodeTemp
	tableMsgTypes.TEMP2.decodeFunction = decodeTemp
	tableMsgTypes.TEMP3.decodeFunction = decodeTemp
	tableMsgTypes.TEMP4.decodeFunction = decodeTemp
	tableMsgTypes.TEMP5.decodeFunction = decodeTemp
	tableMsgTypes.TEMP6.decodeFunction = decodeTemp
	tableMsgTypes.TEMP7.decodeFunction = decodeTemp
	tableMsgTypes.TEMP8.decodeFunction = decodeTemp
	tableMsgTypes.TEMP9.decodeFunction = decodeTemp
	tableMsgTypes.TEMP10.decodeFunction = decodeTemp
	tableMsgTypes.TEMP11.decodeFunction = decodeTemp
	tableMsgTypes.HUM1.decodeFunction = decodeHum
	tableMsgTypes.HUM2.decodeFunction = decodeHum
	tableMsgTypes.TEMP_HUM1.decodeFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM2.decodeFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM3.decodeFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM4.decodeFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM5.decodeFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM6.decodeFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM7.decodeFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM8.decodeFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM9.decodeFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM10.decodeFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM11.decodeFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM12.decodeFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM13.decodeFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM14.decodeFunction = decodeTempHum
	tableMsgTypes.BARO1.decodeFunction = decodeBaro
	tableMsgTypes.TEMP_HUM_BARO1.decodeFunction = decodeTempHumBaro
	tableMsgTypes.TEMP_HUM_BARO2.decodeFunction = decodeTempHumBaro
	tableMsgTypes.RAIN1.decodeFunction = decodeRain
	tableMsgTypes.RAIN2.decodeFunction = decodeRain
	tableMsgTypes.RAIN3.decodeFunction = decodeRain
	tableMsgTypes.RAIN4.decodeFunction = decodeRain
	tableMsgTypes.RAIN5.decodeFunction = decodeRain
	tableMsgTypes.RAIN6.decodeFunction = decodeRain
	tableMsgTypes.RAIN7.decodeFunction = decodeRain
	tableMsgTypes.WIND1.decodeFunction = decodeWind
	tableMsgTypes.WIND2.decodeFunction = decodeWind
	tableMsgTypes.WIND3.decodeFunction = decodeWind
	tableMsgTypes.WIND4.decodeFunction = decodeWind
	tableMsgTypes.WIND5.decodeFunction = decodeWind
	tableMsgTypes.WIND6.decodeFunction = decodeWind
	tableMsgTypes.WIND7.decodeFunction = decodeWind
	tableMsgTypes.UV1.decodeFunction = decodeUV
	tableMsgTypes.UV2.decodeFunction = decodeUV
	tableMsgTypes.UV3.decodeFunction = decodeUV
	tableMsgTypes.ELEC1.decodeFunction = decodeElec1
	tableMsgTypes.ELEC2.decodeFunction = decodeElec2Elec3
	tableMsgTypes.ELEC3.decodeFunction = decodeElec2Elec3
	tableMsgTypes.ELEC4.decodeFunction = decodeElec4
	tableMsgTypes.WEIGHT1.decodeFunction = decodeWeight
	tableMsgTypes.WEIGHT2.decodeFunction = decodeWeight
	tableMsgTypes.RFXSENSOR_T.decodeFunction = decodeRFXSensor
	tableMsgTypes.RFXMETER.decodeFunction = decodeRFXMeter

end

-- Function called at plugin startup
function startup(lul_device)
--require('mobdebug').start('<PC IP address>')

	THIS_DEVICE = lul_device

	task("Starting RFXtrx device: " .. tostring(lul_device), TASK_SUCCESS)
	setDefaultValue(lul_device, tabVars.VAR_VERAPORT, "10000")
	setDefaultValue(lul_device, tabVars.VAR_DEBUG_LOGS, "0")
	DEBUG_MODE = getVariable(lul_device, tabVars.VAR_DEBUG_LOGS)

	local ipAddress = luup.devices[lul_device].ip or ""
	if (ipAddress == "")
		then
		local IOdevice = getVariable(lul_device, tabVars.VAR_IO_DEVICE)
		if ((luup.io.is_connected(lul_device) == false) or (IOdevice == nil))
			then
			error("Serial port not connected. First choose the seial port and restart the lua engine.")
			task("Choose the Serial Port", TASK_ERROR_PERM)
			return false
		end

		log("Serial port is connected")

		-- Check serial settings
		local baud = getVariable(tonumber(IOdevice), tabVars.VAR_BAUD)
		if ((baud == nil) or (baud ~= "38400"))
			then
			error("Incorrect setup of the serial port. Select 38400 bauds.")
			task("Select 38400 bauds for the Serial Port", TASK_ERROR_PERM)
			return false
		end

		log("Baud is 38400")
	else
		local port = getVariable(lul_device, tabVars.VAR_VERAPORT)
		log("Connecting to remote RFXtrx...")
		luup.io.open(lul_device, ipAddress, port)

		if (luup.io.is_connected(lul_device) == false)
			then
			error("Remote connection failed. First connect the LAN RFXtrx to the LAN or start the virtual serial port emulator on the remote machine where the USB RFXtrx is attached.")
			task("Connect the RFXtrx to the LAN", TASK_ERROR_PERM)
			return false
		end

		log("Connection is established")
	end

	luup.call_delay("deferredStartup", 1)

	task("RFXtrx is ready", TASK_SUCCESS)

	return true

end

function deferredStartup(data)

	-- Build a table for selecting the message type based on the key
	for _, msgType in pairs(tableMsgTypes) do
		tableMsgSelect[msgType.key] = msgType
	end

	initIDLookup()

	initDecodingFunctions()

	initStateVariables()

	checkExistingDevices(THIS_DEVICE)

	-- Disable buffering
	buffering = false

	-- Send a reset command
	debug("reset...")
	debug("MODE_COMMAND.packetType: " .. tableMsgTypes.MODE_COMMAND.type or 'nil')
	sendCommand(tableMsgTypes.MODE_COMMAND.type, tableMsgTypes.MODE_COMMAND.subType, DATA_MSG_RESET, nil)

	-- Wait at least 50 ms and max 9 s
	luup.sleep(2000)

	-- Send a get status command
	sendCommand(tableMsgTypes.MODE_COMMAND.type, tableMsgTypes.MODE_COMMAND.subType, DATA_MSG_GET_STATUS, nil)

	-- Clear the buffer and enable buffering
	buffer = ""
	buffering = true

end

-- Function called when data incoming
function incomingData(lul_device, lul_data)

	if (buffering == false)
		then
		return
	end

	-- Store data in buffer
	local data = tostring(lul_data)
	local val = string.byte(data, 1)
	if (#buffer == 0 and (val < 4 or val > 40))
		then
		warning("Bad starting message; ignore byte " .. string.format("%02X", val))
		return
	end

	buffer = buffer .. data

	local length = string.byte(buffer, 1)
	if (#buffer > length)
		then
		local message = getStringPart(buffer, 1, length + 1)
		buffer = getStringPart(buffer, length + 2, #buffer)

		debug("Received message: " .. formattohex(message))
		setVariable(THIS_DEVICE, tabVars.VAR_LAST_RECEIVED_MSG, formattohex(message))
		setVariable(THIS_DEVICE, tabVars.VAR_VERATIME, os.time())
		if (getVariable(THIS_DEVICE, tabVars.VAR_COMM_FAILURE) ~= "0")
			then
			luup.set_failure(false)
		end

		local success, error = pcall(decodeMessage,message)
		if(not success)then
			warning("No decode message for message: ".. formattohex(message) .. "Error: " .. error)
		end
	end

end

function saveSettings()

	log("Saving receiving modes in non-volatile memory...")
	sendCommand(tableMsgTypes.MODE_COMMAND.type, tableMsgTypes.MODE_COMMAND.subType, DATA_MSG_SAVE, nil)

end

function switchPower(deviceNum, newTargetValue)

	local id = luup.devices[deviceNum].id
	newTargetValue = newTargetValue or "0"
	debug("switchPower " .. id .. " target " .. newTargetValue)

	local category
	if ((string.len(id) == 18) and (string.sub(id, 1, 8) == "WC/L2.0/"))
		then
		category = 0
	elseif ((string.len(id) >= 9) and (string.sub(id, 3, 4) == "/L") and (string.sub(id, 6, 6) == ".") and (string.sub(id, 8, 8) == "/"))
		then
		category = tonumber(string.sub(id, 5, 5))
	elseif ((string.len(id) == 9) and (string.sub(id, 1, 4) == "WC/C") and (string.sub(id, 6, 6) == "/"))
		then
		category = 0
	elseif ((string.len(id) == 15) and (string.sub(id, 1, 4) == "WC/B") and (string.sub(id, 6, 6) == "/"))
		then
		category = 0
	elseif ((string.len(id) == 16) and (string.sub(id, 1, 6) == "WC/B6/"))
		then
		category = 0
	elseif ((string.len(id) == 16) and (string.sub(id, 1, 6) == "WC/B7/"))
		then
		category = 0
	elseif ((string.len(id) == 16) and (string.sub(id, 1, 8) == "WC/RFY0/"))
		then
		category = 0
	elseif ((string.len(id) == 16) and (string.sub(id, 1, 8) == "LS/X10/L") and (string.sub(id, 10, 10) == "/"))
		then
		category = 7
	elseif ((string.len(id) == 15) and (string.sub(id, 1, 5) == "HT/HT") and (string.sub(id, 7, 7) == ".")  and (string.sub(id, 9, 9) == "/"))
		then
		category = 8
	elseif ((string.len(id) == 15) and (string.sub(id, 1, 5) == "L4/L4"))
		then
		category = 9
	else
		warning("Unexpected device id " .. id .. ". Switch Power command not sent")
		return
	end

	local type
	local subType
	local housecode
	local unitcode
	local remoteId
	local cmdCode
	local nbTimes = 1
	local cmd = tableCommandTypes.CMD_OFF
	if (newTargetValue == "1")
		then
		cmd = tableCommandTypes.CMD_ON
	end
	local data = nil

	if (category == 0)
		then
		if (cmd == tableCommandTypes.CMD_ON)
			then
			windowCovering(deviceNum, "Up")
		elseif (cmd == tableCommandTypes.CMD_OFF)
			then
			windowCovering(deviceNum, "Down")
		end
	elseif (category == 1)
		then
		type = tableMsgTypes.LIGHTING_ARC.type
		subType = tonumber(string.sub(id, 7, 7), 16)
		if (cmd == tableCommandTypes.CMD_ON)
			then
			cmdCode = 1
		elseif (cmd == tableCommandTypes.CMD_OFF)
			then
			cmdCode = 0
		end
		housecode = string.sub(id, 9, 9)
		unitcode = tonumber(string.sub(id, 10, 11))
		data = housecode .. string.char(unitcode, cmdCode, 0)
	elseif (category == 2)
		then
		type = tableMsgTypes.LIGHTING_AC.type
		subType = tonumber(string.sub(id, 7, 7))
		if (cmd == tableCommandTypes.CMD_ON)
			then
			cmdCode = 1
		elseif (cmd == tableCommandTypes.CMD_OFF)
			then
			cmdCode = 0
		end
		remoteId = string.sub(id, 9, 18)
		data = string.char(tonumber(string.sub(remoteId, 1, 1), 16),
		tonumber(string.sub(remoteId, 2, 3), 16),
		tonumber(string.sub(remoteId, 4, 5), 16),
		tonumber(string.sub(remoteId, 6, 7), 16),
		tonumber(string.sub(remoteId, 9, 10)),
		cmdCode, 0, 0)
	elseif (category == 3)
		then
		type = tableMsgTypes.LIGHTING_KOPPLA.type
		subType = tonumber(string.sub(id, 7, 7))
		if (cmd == tableCommandTypes.CMD_ON)
			then
			cmdCode = 0x10
		elseif (cmd == tableCommandTypes.CMD_OFF)
			then
			cmdCode = 0x1A
		end
		remoteId = tonumber(string.sub(id, 9, 9), 16)
		unitcode = tonumber(string.sub(id, 10, 11))
		local channel1 = 0
		local channel2 = 0
		if (unitcode >= 1 and unitcode <= 8)
			then
			channel1 = 1
			if (unitcode > 1)
				then
				channel1 = bitw.lshift(channel1, unitcode-1)
			end
		elseif (unitcode >= 9 and unitcode <= 10)
			then
			channel2 = 1
			if (unitcode > 9)
				then
				channel2 = bitw.lshift(channel2, unitcode-9)
			end
		end
		data = string.char(remoteId, channel1, channel2, cmdCode, 0)
	elseif (category == 5)
		then
		if (luup.devices[deviceNum].device_type == tableDeviceTypes.COVER.deviceType)
			then
			if (cmd == tableCommandTypes.CMD_ON)
				then
				windowCovering(deviceNum, "Up")
			elseif (cmd == tableCommandTypes.CMD_OFF)
				then
				windowCovering(deviceNum, "Down")
			end
		else
			type = tableMsgTypes.LIGHTING_LIGHTWARERF.type
			subType = tonumber(string.sub(id, 7, 7))
			if (subType == tableMsgTypes.LIGHTING_LIVOLO.subType)
				then
				-- Livolo
				if (luup.devices[deviceNum].device_type == tableDeviceTypes.LIGHT.deviceType)
					then
					if (cmd == tableCommandTypes.CMD_ON)
						then
						remoteId = string.sub(id, 9, 16)
						cmdCode = tonumber(string.sub(remoteId, 8, 8))
						data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
						tonumber(string.sub(remoteId, 3, 4), 16),
						tonumber(string.sub(remoteId, 5, 6), 16),
						0,
						cmdCode, 0, 0)
						if (tonumber(getVariable(deviceNum, tabVars.VAR_LIGHT) or "0") == 1)
							then
							cmd = tableCommandTypes.CMD_OFF
						end
					elseif (cmd == tableCommandTypes.CMD_OFF)
						then
						groupOff(deviceNum)
					end
				elseif (luup.devices[deviceNum].device_type == tableDeviceTypes.DIMMER.deviceType)
					then
					if (cmd == tableCommandTypes.CMD_ON)
						then
						cmdCode = 0x2
					elseif (cmd == tableCommandTypes.CMD_OFF)
						then
						cmdCode = 0x3
					end
					nbTimes = 6
					remoteId = string.sub(id, 9, 16)
					data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
					tonumber(string.sub(remoteId, 3, 4), 16),
					tonumber(string.sub(remoteId, 5, 6), 16),
					0,
					cmdCode, 0, 0)
				end
			else
				if (cmd == tableCommandTypes.CMD_ON)
					then
					cmdCode = 1
				elseif (cmd == tableCommandTypes.CMD_OFF)
					then
					cmdCode = 0
				end
				remoteId = string.sub(id, 9, 17)
				data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
				tonumber(string.sub(remoteId, 3, 4), 16),
				tonumber(string.sub(remoteId, 5, 6), 16),
				tonumber(string.sub(remoteId, 8, 9)),
				cmdCode, 0, 0)
			end
		end
	elseif (category == 6)
		then
		type = tableMsgTypes.LIGHTING_BLYSS.type
		subType = tonumber(string.sub(id, 7, 7))
		if (cmd == tableCommandTypes.CMD_ON)
			then
			cmdCode = 0
		elseif (cmd == tableCommandTypes.CMD_OFF)
			then
			cmdCode = 1
		end
		remoteId = string.sub(id, 9, 12)
		housecode = string.sub(id, 14, 14)
		unitcode = tonumber(string.sub(id, 15, 15))
		data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16))
		.. housecode
		.. string.char(unitcode, cmdCode, 1, 0, 0)
	elseif (category == 7)
		then
		type = tableMsgTypes.SECURITY_X10SR.type
		subType = tableMsgTypes.SECURITY_X10SR.subType
		local light_num = string.sub(id, 9, 9)
		if (cmd == tableCommandTypes.CMD_ON and light_num == "1")
			then
			cmdCode = 0x11
		elseif (cmd == tableCommandTypes.CMD_ON and light_num == "2")
			then
			cmdCode = 0x13
		elseif (cmd == tableCommandTypes.CMD_OFF and light_num == "1")
			then
			cmdCode = 0x10
		elseif (cmd == tableCommandTypes.CMD_OFF and light_num == "2")
			then
			cmdCode = 0x12
		else
			cmdCode = nil
		end
		if (cmdCode ~= nil)
			then
			remoteId = string.sub(id, 11, 16)
			data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
			tonumber(string.sub(remoteId, 3, 4), 16),
			tonumber(string.sub(remoteId, 5, 6), 16),
			cmdCode, 0)
		end
		-- elseif (category == 8)
		-- then
		-- TODO: Mertik
	elseif (category == 9)
		then
		type = tableMsgTypes.SECURITY_DOOR.type
		subType = tableMsgTypes.SECURITY_DOOR.subType
		nbTimes = 1
		remoteId = string.sub(id, 7, 12)
		data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16),
		tonumber(string.sub(remoteId, 5, 6), 16),
		tonumber("01", 16),
		tonumber("76", 16),
		0)
	else
		warning("Unimplemented lighting type " .. category .. ". Switch Power command not sent")
	end

	if (data ~= nil)
		then
		local tableCmds = {}
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), cmd, nil, 0 ))
		sendRepeatCommand(type, subType, data, nbTimes, tableCmds)
	end

end

function setDimLevel(deviceNum, newLoadlevelTarget)

	local id = luup.devices[deviceNum].id
	newLoadlevelTarget = newLoadlevelTarget or "0"
	debug("setDimLevel " .. id .. " target " .. newLoadlevelTarget)

	local category
	if ((string.len(id) == 18) and (string.sub(id, 1, 8) == "WC/L2.0/"))
		then
		category = 0
	elseif ((string.len(id) >= 9) and (string.sub(id, 3, 4) == "/L") and (string.sub(id, 6, 6) == ".") and (string.sub(id, 8, 8) == "/"))
		then
		category = tonumber(string.sub(id, 5, 5))
	elseif ((string.len(id) == 9) and (string.sub(id, 1, 4) == "WC/C") and (string.sub(id, 6, 6) == "/"))
		then
		category = 0
	elseif ((string.len(id) == 15) and (string.sub(id, 1, 4) == "WC/B") and (string.sub(id, 6, 6) == "/"))
		then
		category = 0
	elseif ((string.len(id) == 16) and (string.sub(id, 1, 6) == "WC/B6/"))
		then
		category = 0
	elseif ((string.len(id) == 16) and (string.sub(id, 1, 6) == "WC/B7/"))
		then
		category = 0
	elseif ((string.len(id) == 16) and (string.sub(id, 1, 8) == "WC/RFY0/"))
		then
		category = 0
	else
		warning("Unexpected device id " .. id .. ". Set level command not sent")
		return
	end

	local type
	local subType
	local housecode
	local unitcode
	local remoteId
	local cmdCode
	local nbTimes = 1
	local cmd = tableCommandTypes.CMD_DIM
	local level
	local data = nil

	if (category == 0)
		then
		if (tonumber(newLoadlevelTarget) == 0)
			then
			windowCovering(deviceNum, "Down")
		else
			windowCovering(deviceNum, "Up")
		end
	elseif (category == 2)
		then
		if (tonumber(newLoadlevelTarget) == 0)
			then
			switchPower(deviceNum, "0")
		else
			type = tableMsgTypes.LIGHTING_AC.type
			subType = tonumber(string.sub(id, 7, 7))
			remoteId = string.sub(id, 9, 18)
			cmdCode = 0x2
			level = math.floor(newLoadlevelTarget * 0x0F / 100 + 0.5)
			data = string.char(tonumber(string.sub(remoteId, 1, 1), 16),
			tonumber(string.sub(remoteId, 2, 3), 16),
			tonumber(string.sub(remoteId, 4, 5), 16),
			tonumber(string.sub(remoteId, 6, 7), 16),
			tonumber(string.sub(remoteId, 9, 10)),
			cmdCode, level, 0)
		end
	elseif (category == 3)
		then
		level = math.floor(newLoadlevelTarget / 10 + 0.5)
		if (level == 0)
			then
			switchPower(deviceNum, "0")
		elseif (level == 10)
			then
			switchPower(deviceNum, "1")
		else
			type = tableMsgTypes.LIGHTING_KOPPLA.type
			subType = tonumber(string.sub(id, 7, 7))
			remoteId = tonumber(string.sub(id, 9, 9), 16)
			unitcode = tonumber(string.sub(id, 10, 11))
			local channel1 = 0
			local channel2 = 0
			if (unitcode >= 1 and unitcode <= 8)
				then
				channel1 = 1
				if (unitcode > 1)
					then
					channel1 = bitw.lshift(channel1, unitcode-1)
				end
			elseif (unitcode >= 9 and unitcode <= 10)
				then
				channel2 = 1
				if (unitcode > 9)
					then
					channel2 = bitw.lshift(channel2, unitcode-9)
				end
			end
			cmdCode = level + 0x10
			data = string.char(remoteId, channel1, channel2, cmdCode, 0)
		end
	elseif (category == 5)
		then
		if (luup.devices[deviceNum].device_type == tableDeviceTypes.COVER.deviceType and tonumber(newLoadlevelTarget) > 0)
			then
			newLoadlevelTarget = "100"
		end
		type = tableMsgTypes.LIGHTING_LIGHTWARERF.type
		subType = tonumber(string.sub(id, 7, 7))
		newLoadlevelTarget = tonumber(newLoadlevelTarget)
		if (subType == tableMsgTypes.LIGHTING_LIVOLO.subType)
			then
			-- Livolo
			local curLevel = tonumber(getVariable(deviceNum, tabVars.VAR_DIMMER) or "0") or 0
			if (newLoadlevelTarget == 0)
				then
				switchPower(deviceNum, "0")
			elseif (newLoadlevelTarget == 100)
				then
				switchPower(deviceNum, "1")
			else
				local tableLevels = { 0, 17, 33, 50, 67, 83, 100 }
				local idx1 = 0
				local delta = 100
				local diff
				for i = 1, #tableLevels
					do
					diff = math.abs(curLevel - tableLevels[i])
					if (diff < delta)
						then
						delta = diff
						idx1 = i
					end
				end
				if (newLoadlevelTarget < curLevel)
					then
					local idx2 = 1
					delta = 100
					for i = 1, (idx1-1)
						do
						diff = math.abs(newLoadlevelTarget - tableLevels[i])
						if (diff < delta)
							then
							delta = diff
							idx2 = i
						end
					end
					newLoadlevelTarget = tableLevels[idx2]
					nbTimes = idx1 - idx2
					cmdCode = 0x3
					remoteId = string.sub(id, 9, 16)
					data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
					tonumber(string.sub(remoteId, 3, 4), 16),
					tonumber(string.sub(remoteId, 5, 6), 16),
					0,
					cmdCode, 0, 0)
				elseif (newLoadlevelTarget > curLevel)
					then
					local idx2 = 7
					delta = 100
					for i = (idx1+1), #tableLevels
						do
						diff = math.abs(newLoadlevelTarget - tableLevels[i])
						if (diff < delta)
							then
							delta = diff
							idx2 = i
						end
					end
					newLoadlevelTarget = tableLevels[idx2]
					nbTimes = idx2 - idx1
					cmdCode = 0x2
					remoteId = string.sub(id, 9, 16)
					data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
					tonumber(string.sub(remoteId, 3, 4), 16),
					tonumber(string.sub(remoteId, 5, 6), 16),
					0,
					cmdCode, 0, 0)
				end
			end
		else
			if (newLoadlevelTarget == 0)
				then
				switchPower(deviceNum, "0")
			else
				remoteId = string.sub(id, 9, 17)
				cmdCode = 0x10
				level = math.floor(newLoadlevelTarget * 0x1F / 100 + 0.5)
				data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
				tonumber(string.sub(remoteId, 3, 4), 16),
				tonumber(string.sub(remoteId, 5, 6), 16),
				tonumber(string.sub(remoteId, 8, 9)),
				cmdCode, level, 0)
			end
		end
	else
		warning("Unimplemented lighting type " .. category .. ". Set level command not sent")
	end

	if (data ~= nil)
		then
		local tableCmds = {}
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), cmd, newLoadlevelTarget, 0 ))
		sendRepeatCommand(type, subType, data, nbTimes, tableCmds)
	end

end

function windowCovering(deviceNum, action)

	local id = luup.devices[deviceNum].id
	debug("windowCovering " .. action .. " ".. id)

	local cmd = nil
	if (action == "Up")
		then
		cmd = tableCommandTypes.CMD_OPEN
	elseif (action == "Down")
		then
		cmd = tableCommandTypes.CMD_CLOSE
	elseif (action == "Stop")
		then
		cmd = tableCommandTypes.CMD_STOP
	else
		warning("windowCovering: unexpected value for action parameter")
		return
	end

	local category
	if ((string.len(id) >= 9) and (string.sub(id, 3, 6) == "/L5.") and (string.sub(id, 8, 8) == "/"))
		then
		category = 5
	elseif ((string.len(id) == 9) and (string.sub(id, 1, 4) == "WC/C") and (string.sub(id, 6, 6) == "/"))
		then
		category = 0
	elseif ((string.len(id) == 15) and (string.sub(id, 1, 4) == "WC/B") and (string.sub(id, 6, 6) == "/"))
		then
		category = 6
	elseif ((string.len(id) == 16) and (string.sub(id, 1, 6) == "WC/B6/"))
		then
		category = 6
	elseif ((string.len(id) == 16) and (string.sub(id, 1, 6) == "WC/B7/"))
		then
		category = 6
	elseif ((string.len(id) == 16) and (string.sub(id, 1, 8) == "WC/RFY0/"))
		then
		category = 7
	elseif ((string.len(id) == 18) and (string.sub(id, 1, 8) == "WC/L2.0/"))
		then
		category = 2
	else
		warning("Unexpected device id " .. id .. ". " .. action .. " command not sent")
		return
	end

	local type
	local subType
	local housecode
	local unitcode
	local remoteId
	local id4
	local cmdCode = 0
	local data = nil

	if (category == 0)
		then
		type = tableMsgTypes.CURTAIN_HARRISON.type
		subType = tonumber(string.sub(id, 5, 5))
		if (cmd == tableCommandTypes.CMD_OPEN)
			then
			cmdCode = 0
		elseif (cmd == tableCommandTypes.CMD_CLOSE)
			then
			cmdCode = 1
		elseif (cmd == tableCommandTypes.CMD_STOP)
			then
			cmdCode = 2
		end
		housecode = string.sub(id, 7, 7)
		unitcode = tonumber(string.sub(id, 8, 9))
		data = housecode .. string.char(unitcode, cmdCode, 0)
	elseif (category == 2)
		then
		if (cmd == tableCommandTypes.CMD_STOP)
			then
			windowCovering(deviceNum, "Up")
			luup.sleep(1000)
			windowCovering(deviceNum, "Down")
			luup.sleep(1000)
			windowCovering(deviceNum, "Down")
		else
			type = tableMsgTypes.LIGHTING_AC.type
			subType = tonumber(string.sub(id, 7, 7))
			remoteId = string.sub(id, 9, 18)
			if (cmd == tableCommandTypes.CMD_OPEN)
				then
				cmdCode = 1
			elseif (cmd == tableCommandTypes.CMD_CLOSE)
				then
				cmdCode = 0
			end
			data = string.char(tonumber(string.sub(remoteId, 1, 1), 16),
			tonumber(string.sub(remoteId, 2, 3), 16),
			tonumber(string.sub(remoteId, 4, 5), 16),
			tonumber(string.sub(remoteId, 6, 7), 16),
			tonumber(string.sub(remoteId, 9, 10)),
			cmdCode, 0, 0)
		end
	elseif (category == 5)
		then
		type = tableMsgTypes.LIGHTING_LIGHTWARERF.type
		subType = tonumber(string.sub(id, 7, 7))
		if (cmd == tableCommandTypes.CMD_OPEN)
			then
			cmdCode = 0x0F
		elseif (cmd == tableCommandTypes.CMD_CLOSE)
			then
			cmdCode = 0x0D
		elseif (cmd == tableCommandTypes.CMD_STOP)
			then
			cmdCode = 0x0E
		end
		remoteId = string.sub(id, 9, 17)
		data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16),
		tonumber(string.sub(remoteId, 5, 6), 16),
		tonumber(string.sub(remoteId, 8, 9)),
		cmdCode, 0, 0)
	elseif (category == 6)
		then
		type = tableMsgTypes.BLIND_T0.type
		subType = tonumber(string.sub(id, 5, 5))
		if (cmd == tableCommandTypes.CMD_OPEN)
			then
			cmdCode = 0
		elseif (cmd == tableCommandTypes.CMD_CLOSE)
			then
			cmdCode = 1
		elseif (cmd == tableCommandTypes.CMD_STOP)
			then
			cmdCode = 2
		end
		remoteId = string.sub(id, 7, 12)
		if (subType == tableMsgTypes.BLIND_T6.subType or subType == tableMsgTypes.BLIND_T7.subType)
			then
			id4 = tonumber(string.sub(id, 13, 13), 16)
			unitcode = tonumber(string.sub(id, 15, 16)) % 16
		else
			id4 = 0
			unitcode = tonumber(string.sub(id, 14, 15)) % 16
		end
		data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16),
		tonumber(string.sub(remoteId, 5, 6), 16),
		id4 * 16 + unitcode, cmdCode, 0)
	elseif (category == 7)
		then
		local mode = getVariable(deviceNum, tabVars.VAR_RFY_MODE) or ""
		type = tableMsgTypes.RFY0.type
		subType = tonumber(string.sub(id, 7, 7))
		if (cmd == tableCommandTypes.CMD_OPEN)
			then
			if (mode == "VENETIAN_US")
				then
				cmdCode = 0x0F
			elseif (mode == "VENETIAN_EU")
				then
				cmdCode = 0x11
			else
				cmdCode = 0x01
			end
		elseif (cmd == tableCommandTypes.CMD_CLOSE)
			then
			if (mode == "VENETIAN_US")
				then
				cmdCode = 0x10
			elseif (mode == "VENETIAN_EU")
				then
				cmdCode = 0x12
			else
				cmdCode = 0x03
			end
		elseif (cmd == tableCommandTypes.CMD_STOP)
			then
			cmdCode = 0
		end
		remoteId = string.sub(id, 9, 13)
		unitcode = tonumber(string.sub(id, 15, 16))
		data = string.char(tonumber(string.sub(remoteId, 1, 1), 16),
		tonumber(string.sub(remoteId, 2, 3), 16),
		tonumber(string.sub(remoteId, 4, 5), 16),
		unitcode, cmdCode, 0, 0, 0, 0)
	end

	if (data ~= nil)
		then
		local tableCmds = {}
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), cmd, nil, 0 ))
		sendCommand(type, subType, data, tableCmds)
	end

end

function setArmed(deviceNum, newArmedValue)

	local id = luup.devices[deviceNum].id
	debug("setArmed " .. id .. " target " .. (newArmedValue or "nil"))

	setVariable(deviceNum, tabVars.VAR_ARMED, newArmedValue)

end

function requestArmMode(deviceNum, state, PINcode)

	local id = luup.devices[deviceNum].id
	debug("requestArmMode " .. id .. " state " .. state .. " PIN code " .. PINcode)
	requestQuickArmMode(deviceNum, state)

end

function requestQuickArmMode(deviceNum, state)

	local id = luup.devices[deviceNum].id
	debug("requestQuickArmMode " .. id .. " state " .. state)

	if ((string.len(id) ~= 16) or (string.sub(id, 1, 10) ~= "SR/X10/SR/" and string.sub(id, 1, 10) ~= "SR/MEI/SR/"))
		then
		warning("Unexpected device id " .. id .. ". Quick Arm Mode command not sent")
		return
	end

	local type = nil
	local subType = nil
	local exitDelay = 0
	if (string.sub(id, 1, 9) == "SR/X10/SR")
		then
		type = tableMsgTypes.SECURITY_X10SR.type
		subType = tableMsgTypes.SECURITY_X10SR.subType
		exitDelay = tonumber(getVariable(deviceNum, tabVars.VAR_EXIT_DELAY) or "0")
	elseif (string.sub(id, 1, 9) == "SR/MEI/SR")
		then
		type = tableMsgTypes.SECURITY_MEISR.type
		subType = tableMsgTypes.SECURITY_MEISR.subType
	end

	local cmdCode = nil
	local data = nil
	local tableCmds = {}

	if ((state == "Armed" or state == "ArmedInstant") and exitDelay > 0)
		then
		cmdCode = 0x0A
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_DETAILED_ARM_MODE, "ExitDelay", 0 ) )
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ARM_MODE, "Armed", exitDelay ) )
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_DETAILED_ARM_MODE, "Armed", exitDelay ) )
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ARM_MODE_NUM, "1", exitDelay ) )
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ALARM_SCENE_ON, 121, 0 ) )
	elseif ((state == "Armed" or state == "ArmedInstant") and exitDelay == 0)
		then
		cmdCode = 0x09
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ARM_MODE, "Armed", 0 ) )
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_DETAILED_ARM_MODE, "Armed", 0 ) )
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ARM_MODE_NUM, "1", 0 ) )
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ALARM_SCENE_ON, 121, 0 ) )
	elseif ((state == "Stay" or state == "StayInstant") and exitDelay > 0)
		then
		cmdCode = 0x0C
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_DETAILED_ARM_MODE, "ExitDelay", 0 ) )
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ARM_MODE, "Armed", exitDelay ) )
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_DETAILED_ARM_MODE, "Stay", exitDelay ) )
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ARM_MODE_NUM, "1", exitDelay ) )
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ALARM_SCENE_ON, 122, 0 ) )
	elseif ((state == "Stay" or state == "StayInstant") and exitDelay == 0)
		then
		cmdCode = 0x0B
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ARM_MODE, "Armed", 0 ) )
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_DETAILED_ARM_MODE, "Stay", 0 ) )
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ARM_MODE_NUM, "1", 0 ) )
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ALARM_SCENE_ON, 122, 0 ) )
	elseif (state == "Disarmed")
		then
		cmdCode = 0x0D
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ARM_MODE, "Disarmed", 0 ) )
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_DETAILED_ARM_MODE, "Disarmed", 0 ) )
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ARM_MODE_NUM, "0", 0 ) )
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ALARM_SCENE_ON, 123, 0 ) )
	else
		cmdCode = nil
		warning("Unimplemented state " .. state .. ". Quick Arm Mode command not sent")
	end
	if (cmdCode ~= nil)
		then
		local remoteId = string.sub(id, 11, 16)
		data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16),
		tonumber(string.sub(remoteId, 5, 6), 16),
		cmdCode, 0)
		sendCommand(type, subType, data, tableCmds)
	end

end

function requestPanicMode(deviceNum, state)

	local id = luup.devices[deviceNum].id
	debug("requestPanicMode " .. id .. " state " .. state)

	if ((string.len(id) ~= 16) or (string.sub(id, 1, 10) ~= "SR/X10/SR/"
		and string.sub(id, 1, 10) ~= "SR/MEI/SR/"
		and string.sub(id, 1, 10) ~= "SR/KD1/SR/"
		and string.sub(id, 1, 10) ~= "SR/S30/SR/"))
		then
		warning("Unexpected device id " .. id .. ". Panic Mode command not sent")
		return
	end

	local type = nil
	local subType = nil
	if (string.sub(id, 1, 9) == "SR/X10/SR")
		then
		type = tableMsgTypes.SECURITY_X10SR.type
		subType = tableMsgTypes.SECURITY_X10SR.subType
	elseif (string.sub(id, 1, 9) == "SR/MEI/SR")
		then
		type = tableMsgTypes.SECURITY_MEISR.type
		subType = tableMsgTypes.SECURITY_MEISR.subType
	elseif (string.sub(id, 1, 9) == "SR/KD1/SR")
		then
		type = tableMsgTypes.KD101.type
		subType = tableMsgTypes.KD101.subType
	elseif (string.sub(id, 1, 9) == "SR/S30/SR")
		then
		type = tableMsgTypes.SA30.type
		subType = tableMsgTypes.SA30.subType
	end

	local remoteId = string.sub(id, 11, 16)
	local data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
	tonumber(string.sub(remoteId, 3, 4), 16),
	tonumber(string.sub(remoteId, 5, 6), 16),
	0x06, 0)
	local tableCmds = {}
	table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ALARM_SCENE_ON, 120, 0 ))
	if (type == tableMsgTypes.KD101.type)
		then
		id = "KD1/SS/" .. string.sub(remoteId, 1, 2)
		.. string.sub(remoteId, 3, 4)
		.. string.sub(remoteId, 5, 6)
		table.insert(tableCmds, DeviceCmd( id, tableCommandTypes.CMD_SMOKE, "1", 0 ) )
		table.insert(tableCmds, DeviceCmd( id, tableCommandTypes.CMD_SMOKE_OFF, nil, 30 ) )
	elseif (type == tableMsgTypes.SA30.type)
		then
		id = "S30/SS/" .. string.sub(remoteId, 1, 2)
		.. string.sub(remoteId, 3, 4)
		.. string.sub(remoteId, 5, 6)
		table.insert(tableCmds, DeviceCmd( id, tableCommandTypes.CMD_SMOKE, "1", 0 ) )
		table.insert(tableCmds, DeviceCmd( id, tableCommandTypes.CMD_SMOKE_OFF, nil, 30 ) )
	end
	sendCommand(type, subType, data, tableCmds)

end

function setExitDelay(deviceNum, newValue)

	local id = luup.devices[deviceNum].id
	debug("setExitDelay " .. id .. " new value " .. (newValue or ""))

	if ((string.len(id) ~= 16) or string.sub(id, 1, 10) ~= "SR/X10/SR/")
		then
		task("Exit delay is not relevant for device id " .. id, TASK_ERROR)
		return
	end

	setVariable(deviceNum, tabVars.VAR_EXIT_DELAY, newValue or "0")

end

function dim(deviceNum)

	local id = luup.devices[deviceNum].id
	debug("dim " .. id)

	if ((string.len(id) ~= 9) or (string.sub(id, 1, 8) ~= "RC/L1.0/"))
		then
		task("Dim command is not relevant for device " .. id, TASK_ERROR)
		return
	end

	local tableCmds = {}
	table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_SCENE_ON, 102, 0 ))

	local data = string.sub(id, 9, 9) .. string.char(0, 0x02, 0)
	sendCommand(tableMsgTypes.LIGHTING_X10.type, tableMsgTypes.LIGHTING_X10.subType, data, tableCmds)

end

function bright(deviceNum)

	local id = luup.devices[deviceNum].id
	debug("bright " .. id)

	if ((string.len(id) ~= 9) or (string.sub(id, 1, 8) ~= "RC/L1.0/"))
		then
		task("Bright command is not relevant for device " .. id, TASK_ERROR)
		return
	end

	local tableCmds = {}
	table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_SCENE_ON, 103, 0 ))

	local data = string.sub(id, 9, 9) .. string.char(0, 0x03, 0)
	sendCommand(tableMsgTypes.LIGHTING_X10.type, tableMsgTypes.LIGHTING_X10.subType, data, tableCmds)

end

function groupOff(deviceNum)

	local id = luup.devices[deviceNum].id
	debug("groupOff " .. id)

	local category
	if ((string.len(id) >= 9) and (string.sub(id, 3, 4) == "/L") and (string.sub(id, 6, 6) == ".") and (string.sub(id, 8, 8) == "/"))
		then
		category = tonumber(string.sub(id, 5, 5))
	else
		task("Group Off command is not relevant for device " .. id, TASK_ERROR)
		return
	end

	local cmd
	local type
	local subType
	local remoteId
	local cmdCode
	local unitCodeMin = nil
	local unitCodeMax = nil
	local altid, formatAltid, device2
	local data = nil
	local tableCmds = {}

	if (category == 1)
		then
		cmd = tableCommandTypes.CMD_SCENE_OFF
		type = tableMsgTypes.LIGHTING_ARC.type
		subType = tonumber(string.sub(id, 7, 7), 16)
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), cmd, 100, 0 ))
		for _, v in pairs(tableCategories)
			do
			if (string.find(id, v[26]) == 4)
				then
				unitCodeMin = v[18]
				unitCodeMax = v[19]
				formatAltid = "%s%02d"
				break
			end
		end
		data = string.sub(id, 9, 9) .. string.char(0, 0x05, 0)
	elseif (category == 2)
		then
		cmd = tableCommandTypes.CMD_SCENE_OFF
		type = tableMsgTypes.LIGHTING_AC.type
		subType = tonumber(string.sub(id, 7, 7))
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), cmd, 100, 0 ))
		for _, v in pairs(tableCategories)
			do
			if (string.find(id, v[26]) == 4)
				then
				unitCodeMin = v[18]
				unitCodeMax = v[19]
				formatAltid = "%s/%02d"
				break
			end
		end
		remoteId = string.sub(id, 9, 15)
		data = string.char(tonumber(string.sub(remoteId, 1, 1), 16),
		tonumber(string.sub(remoteId, 2, 3), 16),
		tonumber(string.sub(remoteId, 4, 5), 16),
		tonumber(string.sub(remoteId, 6, 7), 16),
		0, 0x03, 0, 0)
	elseif (category == 5)
		then
		type = tableMsgTypes.LIGHTING_LIGHTWARERF.type
		subType = tonumber(string.sub(id, 7, 7))
		cmdCode = 0x02
		if (subType == tableMsgTypes.LIGHTING_LIVOLO.subType)
			then
			-- Livolo
			unitCodeMin = 1
			unitCodeMax = 3
			id = string.sub(id, 1, #id-2)
			formatAltid = "%s/%d"
			cmdCode = 0
		else
			if (subType == tableMsgTypes.LIGHTING_LIGHTWARERF.subType)
				then
				cmd = tableCommandTypes.CMD_LWRF_SCENE_OFF
			else
				cmd = tableCommandTypes.CMD_SCENE_OFF
			end
			table.insert(tableCmds, DeviceCmd( string.sub(id, 4), cmd, 100, 0 ))
			for _, v in pairs(tableCategories)
				do
				if (string.find(id, v[26]) == 4)
					then
					unitCodeMin = v[18]
					unitCodeMax = v[19]
					formatAltid = "%s/%02d"
					break
				end
			end
		end
		remoteId = string.sub(id, 9, 14)
		data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16),
		tonumber(string.sub(remoteId, 5, 6), 16),
		0, cmdCode, 0, 0)
	elseif (category == 6)
		then
		cmd = tableCommandTypes.CMD_SCENE_OFF
		type = tableMsgTypes.LIGHTING_BLYSS.type
		subType = tonumber(string.sub(id, 7, 7))
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), cmd, 100, 0 ))
		for _, v in pairs(tableCategories)
			do
			if (string.find(id, v[26]) == 4)
				then
				unitCodeMin = v[18]
				unitCodeMax = v[19]
				formatAltid = "%s%d"
				break
			end
		end
		remoteId = string.sub(id, 9, 12)
		data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16))
		.. string.sub(id, 14, 14)
		.. string.char(0, 0x03, 1, 0, 0)
	else
		task("Unimpemented lighting type " .. category .. ". Group Off command not sent", TASK_ERROR)
	end

	if (data ~= nil)
		then
		if (unitCodeMin ~= nil and unitCodeMax ~= nil)
			then
			for i = unitCodeMin, unitCodeMax
				do
				altid = string.format(formatAltid, string.sub(id, 4), i)
				device2 = findChild(THIS_DEVICE, altid, nil)
				if (device2 ~= nil)
					then
					table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_OFF, nil, 0 ))
				end
			end
		end
		sendCommand(type, subType, data, tableCmds)
	end

end

function groupOn(deviceNum)

	local id = luup.devices[deviceNum].id
	debug("groupOn " .. id)

	local category
	if ((string.len(id) >= 9) and (string.sub(id, 1, 4) == "RC/L") and (string.sub(id, 6, 6) == ".") and (string.sub(id, 8, 8) == "/"))
		then
		category = tonumber(string.sub(id, 5, 5))
	else
		task("Group On command is not relevant for device " .. id, TASK_ERROR)
		return
	end

	local cmd
	local type
	local subType
	local remoteId
	local unitCodeMin = nil
	local unitCodeMax = nil
	local altid, formatAltid, device2
	local data = nil
	local tableCmds = {}

	if (category == 1)
		then
		cmd = tableCommandTypes.CMD_SCENE_ON
		type = tableMsgTypes.LIGHTING_ARC.type
		subType = tonumber(string.sub(id, 7, 7), 16)
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), cmd, 100, 0 ))
		for _, v in pairs(tableCategories)
			do
			if (string.find(id, v[26]) == 4)
				then
				unitCodeMin = v[18]
				unitCodeMax = v[19]
				formatAltid = "%s%02d"
				break
			end
		end
		data = string.sub(id, 9, 9) .. string.char(0, 0x06, 0)
	elseif (category == 2)
		then
		cmd = tableCommandTypes.CMD_SCENE_ON
		type = tableMsgTypes.LIGHTING_AC.type
		subType = tonumber(string.sub(id, 7, 7))
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), cmd, 100, 0 ))
		for _, v in pairs(tableCategories)
			do
			if (string.find(id, v[26]) == 4)
				then
				unitCodeMin = v[18]
				unitCodeMax = v[19]
				formatAltid = "%s/%02d"
				break
			end
		end
		remoteId = string.sub(id, 9, 15)
		data = string.char(tonumber(string.sub(remoteId, 1, 1), 16),
		tonumber(string.sub(remoteId, 2, 3), 16),
		tonumber(string.sub(remoteId, 4, 5), 16),
		tonumber(string.sub(remoteId, 6, 7), 16),
		0, 0x04, 0, 0)
	elseif (category == 5)
		then
		cmd = tableCommandTypes.CMD_SCENE_ON
		type = tableMsgTypes.LIGHTING_LIGHTWARERF.type
		subType = tonumber(string.sub(id, 7, 7))
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), cmd, 100, 0 ))
		for _, v in pairs(tableCategories)
			do
			if (string.find(id, v[26]) == 4)
				then
				unitCodeMin = v[18]
				unitCodeMax = v[19]
				formatAltid = "%s/%02d"
				break
			end
		end
		remoteId = string.sub(id, 9, 14)
		data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16),
		tonumber(string.sub(remoteId, 5, 6), 16),
		0, 0x03, 0, 0)
	elseif (category == 6)
		then
		cmd = tableCommandTypes.CMD_SCENE_ON
		type = tableMsgTypes.LIGHTING_BLYSS.type
		subType = tonumber(string.sub(id, 7, 7))
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), cmd, 100, 0 ))
		for _, v in pairs(tableCategories)
			do
			if (string.find(id, v[26]) == 4)
				then
				unitCodeMin = v[18]
				unitCodeMax = v[19]
				formatAltid = "%s%d"
				break
			end
		end
		remoteId = string.sub(id, 9, 12)
		data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16))
		.. string.sub(id, 14, 14)
		.. string.char(0, 0x02, 1, 0, 0)
	else
		task("Unimpemented lighting type " .. category .. ". Group On command not sent", TASK_ERROR)
	end

	if (data ~= nil)
		then
		if (unitCodeMin ~= nil and unitCodeMax ~= nil)
			then
			for i = unitCodeMin, unitCodeMax
				do
				altid = string.format(formatAltid, string.sub(id, 4), i)
				device2 = findChild(THIS_DEVICE, altid, nil)
				if (device2 ~= nil)
					then
					table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ON, nil, 0 ))
				end
			end
		end
		sendCommand(type, subType, data, tableCmds)
	end

end

function mood(deviceNum, param)

	local id = luup.devices[deviceNum].id
	debug("mood" .. param .. " " .. id)

	if ((string.len(id) ~= 14) or (string.sub(id, 1, 8) ~= "RC/L5.0/"))
		then
		task("Mood command is not relevant for device " .. id, TASK_ERROR)
		return
	end

	local cmdCode = nil

	local value = tonumber(param)
	if (value == 1)
		then
		cmdCode = 0x03
	elseif (value == 2)
		then
		cmdCode = 0x04
	elseif (value == 3)
		then
		cmdCode = 0x05
	elseif (value == 4)
		then
		cmdCode = 0x06
	elseif (value == 5)
		then
		cmdCode = 0x07
	else
		task("action Mood: unexpected value for argument", TASK_ERROR)
		return
	end

	if (cmdCode ~= nil)
		then
		local tableCmds = {}
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_LWRF_SCENE_ON, 110+value, 0 ))

		local remoteId = string.sub(id, 9, 14)
		local data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16),
		tonumber(string.sub(remoteId, 5, 6), 16),
		0, cmdCode, 0, 0)
		sendCommand(tableMsgTypes.LIGHTING_LIGHTWARERF.type, tableMsgTypes.LIGHTING_LIGHTWARERF.subType, data, tableCmds)
	end

end

function sendATICode(deviceNum, code)

	local id = luup.devices[deviceNum].id
	debug("sendATICode " .. id .. " code " .. code)

	if ((string.len(id) ~= 9) or (string.sub(id, 1, 5) ~= "RC/RC") or (string.sub(id, 7, 7) ~= "/"))
		then
		task("Send code is not relevant for device " .. id, TASK_ERROR)
		return
	end
	local subType = tonumber(string.sub(id, 6, 6))
	if (subType >= 0x4)
		then
		task("Send code is not relevant for device " .. id, TASK_ERROR)
		return
	end

	local tableCmds = {}
	table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ATI_SCENE_ON, tonumber(code), 0 ))

	local data = string.char(tonumber(string.sub(id, 8, 9), 16), tonumber(code), 0)
	-- TODO toggle
	sendCommand(tableMsgTypes.ATI_REMOTE_WONDER.type, subType, data, tableCmds)

end

function setModeTarget(deviceNum, NewModeTarget)
	local id = luup.devices[deviceNum].id
	debug("setModeTarget " .. id .. " target " .. NewModeTarget)

	local category
	if ((string.len(id) == 15) and (string.sub(id, 1, 5) == "HT/HT") and (string.sub(id, 7, 7) == ".")  and (string.sub(id, 9, 9) == "/"))
		then
		category = 3
	else
		warning("Unexpected device id " .. id .. ". Set Mode command not sent")
		return
	end

	local type = nil
	local subType = nil
	local tableCmds = {}
	local data = nil

	if (category == 3) -- Mertik
		then
		type = tableMsgTypes.HEATER3_MERTIK1.type
		subType = tonumber(string.sub(id, 8, 8))
		local cmdCode = nil
		local currentState = getVariable(deviceNum, tabVars.VAR_HEATER) or "Off"
		local currentSwState = getVariable(deviceNum, tabVars.VAR_HEATER_SW) or "0"
		if (NewModeTarget == "HeatOn")
			then
			if (currentSwState == "0")
				then
				cmdCode = 0x01 -- Turn on
				table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_HEATER_SW, 1, 0 ))
				table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_HEATER, "HeatOn", 0 ))
			else
				cmdCode = 0x04 -- Run up
				table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_HEATER, "HeatOn", 0 ))
			end
		elseif (NewModeTarget == "Off")
			then
			if (currentState == "Off")
				then
				cmdCode = 0x00 -- Turn off
				table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_HEATER_SW, 0, 0 ))
				table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_HEATER, "Off", 0 ))
			else
				cmdCode = 0x05 -- Run down
				table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_HEATER, "Off", 0 ))
			end
		else
			warning("setModeTarget: unexpected value for NewModeTarget parameter")
			return
		end
		local remoteId = string.sub(id, 10, 15)
		data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16),
		tonumber(string.sub(remoteId, 5, 6), 16),
		cmdCode, 0)
	end

	if (data ~= nil)
		then
		sendCommand(type, subType, data, tableCmds)
	end

end

function toggleState(deviceNum)
	debug("toggleState: " .. deviceNum)
	local devType = string.sub(luup.devices[deviceNum].id, 1, 2)
	debug("Device type: " .. devType)

	-- Only implemented for Sonoff switches, Light Switches and Heaters so far
	if (devType == "LS")
		then
		local curStat = getVariable(deviceNum, tabVars.VAR_LIGHT) or "0"
		local newTargetState
		if (curStat == "0")
			then
			newTargetState = "1"
		else
			newTargetState = "0"
		end
		switchPower(deviceNum, newTargetState)
	elseif (devType == "HT")
		then
		local curStat = getVariable(deviceNum, tabVars.VAR_HEATER) or "Off"
		local NewModeTarget
		if (curStat == "Off")
			then
			NewModeTarget = "HeatOn"
		else
			NewModeTarget = "Off"
		end
		setModeTarget(deviceNum, NewModeTarget)
	elseif (devType == "L4")
		then
		local currentState = getVariable(deviceNum,tabVars.VAR_STATE) or "0"
		local newTargetState
		if (currentState == "0")
			then
			newTargetState = "1"
		else
			newTargetState = "0"
		end
		setVariable(deviceNum, tabVars.VAR_STATE, newTargetState)
		-- Send a command to toggle the switch state
		switchPower(deviceNum, newTargetState)

	end
end

function createNewDevice(category, deviceType, name, id, houseCode, groupCode, unitCode, systemCode, channel)
	debug("createNewDevice " .. (category or "nil") .. " " .. (deviceType or "nil"))

	if (category == nil or tableCategories[category] == nil)
		then
		warning("action CreateNewDevice: invalid value for the Category argument")
		task("CreateNewDevice: invalid arguments", TASK_ERROR)
		return
	end

	local valid = true
	local params = {}

	if (deviceType == nil)
		then
		warning("action CreateNewDevice: missing value for the DeviceType argument")
		valid = false
	elseif (deviceType ~= "SWITCH_LIGHT" and deviceType ~= "DIMMABLE_LIGHT"
		and deviceType ~= "MOTION_SENSOR" and deviceType ~= "DOOR_SENSOR"
		and deviceType ~= "LIGHT_SENSOR" and deviceType ~= "WINDOW_COVERING")
		then
		warning("action CreateNewDevice: invalid value for the DeviceType argument")
		valid = false
	elseif ((deviceType == "SWITCH_LIGHT" and not tableCategories[category][2])
		or (deviceType == "DIMMABLE_LIGHT" and not tableCategories[category][3])
		or (deviceType == "MOTION_SENSOR" and not tableCategories[category][4])
		or (deviceType == "DOOR_SENSOR" and not tableCategories[category][5])
		or (deviceType == "LIGHT_SENSOR" and not tableCategories[category][6])
		or (deviceType == "WINDOW_COVERING" and not tableCategories[category][7]))
		then
		warning("action CreateNewDevice: DeviceType value not accepted for this category")
		valid = false
	end

	if (tableCategories[category][8])
		then
		if (id == nil)
			then
			warning("action CreateNewDevice: missing value for the Id argument")
			valid = false
		elseif (tonumber(id) == nil)
			then
			warning("action CreateNewDevice: invalid value for the Id argument")
			valid = false
		elseif (tableCategories[category][9] ~= nil and tableCategories[category][10] ~= nil
			and (tonumber(id) < tableCategories[category][9]
			or tonumber(id) > tableCategories[category][10]))
			then
			warning(string.format("action CreateNewDevice: value for the Id argument must be in range %d - %d",
			tableCategories[category][9],
			tableCategories[category][10]))
			valid = false
		else
			table.insert(params, tonumber(id))
		end
	end
	if (tableCategories[category][11])
		then
		if (houseCode == nil)
			then
			warning("action CreateNewDevice: missing value for the HouseCode argument")
			valid = false
		elseif (#houseCode ~= 1)
			then
			warning("action CreateNewDevice: invalid value for the HouseCode argument")
			valid = false
		elseif (tableCategories[category][12] ~= nil and tableCategories[category][13] ~= nil
			and (string.byte(houseCode) < tableCategories[category][12]
			or string.byte(houseCode) > tableCategories[category][13]))
			then
			warning(string.format("action CreateNewDevice: value for the HouseCode argument must be in range %s - %s",
			string.char(tableCategories[category][12]),
			string.char(tableCategories[category][13])))
			valid = false
		else
			table.insert(params, houseCode)
		end
	end
	if (tableCategories[category][14])
		then
		if (groupCode == nil)
			then
			warning("action CreateNewDevice: missing value for the GroupCode argument")
			valid = false
		elseif (#groupCode ~= 1)
			then
			warning("action CreateNewDevice: invalid value for the GroupCode argument")
			valid = false
		elseif (tableCategories[category][15] ~= nil and tableCategories[category][16] ~= nil
			and (string.byte(groupCode) < tableCategories[category][15]
			or string.byte(groupCode) > tableCategories[category][16]))
			then
			warning(string.format("action CreateNewDevice: value for the GroupCode argument must be in range %s - %s",
			string.char(tableCategories[category][15]),
			string.char(tableCategories[category][16])))
			valid = false
		else
			table.insert(params, groupCode)
		end
	end
	if (tableCategories[category][17])
		then
		if (unitCode == nil)
			then
			warning("action CreateNewDevice: missing value for the UnitCode argument")
			valid = false
		elseif (tonumber(unitCode) == nil)
			then
			warning("action CreateNewDevice: invalid value for the UnitCode argument")
			valid = false
		elseif (tableCategories[category][18] ~= nil and tableCategories[category][19] ~= nil
			and (tonumber(unitCode) < tableCategories[category][18]
			or tonumber(unitCode) > tableCategories[category][19]))
			then
			warning(string.format("action CreateNewDevice: value for the UnitCode argument must be in range %d - %d",
			tableCategories[category][18],
			tableCategories[category][19]))
			valid = false
		else
			table.insert(params, unitCode)
		end
	end
	if (tableCategories[category][20])
		then
		if (systemCode == nil)
			then
			warning("action CreateNewDevice: missing value for the SystemCode argument")
			valid = false
		elseif (tonumber(systemCode) == nil)
			then
			warning("action CreateNewDevice: invalid value for the SystemCode argument")
			valid = false
		elseif (tableCategories[category][21] ~= nil and tableCategories[category][22] ~= nil
			and (tonumber(systemCode) < tableCategories[category][21]
			or tonumber(systemCode) > tableCategories[category][22]))
			then
			warning(string.format("action CreateNewDevice: value for the SystemCode argument must be in range %d - %d",
			tableCategories[category][21],
			tableCategories[category][22]))
			valid = false
		else
			table.insert(params, tonumber(systemCode-1))
		end
	end
	if (tableCategories[category][23])
		then
		if (channel == nil)
			then
			warning("action CreateNewDevice: missing value for the Channel argument")
			valid = false
		elseif (tonumber(channel) == nil)
			then
			warning("action CreateNewDevice: invalid value for the Channel argument")
			valid = false
		elseif (tableCategories[category][24] ~= nil and tableCategories[category][25] ~= nil
			and (tonumber(channel) < tableCategories[category][24]
			or tonumber(channel) > tableCategories[category][25]))
			then
			warning(string.format("action CreateNewDevice: value for the Channel argument must be in range %d - %d",
			tableCategories[category][24],
			tableCategories[category][25]))
			valid = false
		else
			table.insert(params, tonumber(channel))
		end
	end
	if (not valid)
		then
		task("CreateNewDevice: invalid arguments", TASK_ERROR)
		return
	end

	while (#params < 3)
		do
		table.insert(params, "")
	end

	local devType
	if (deviceType == "SWITCH_LIGHT")
		then
		devType = "LIGHT"
		-- This is part of the SONOFF hack
		if (category == "SONOFF")
			then
			devType = "SWITCH_TOGGLE"
		end
	elseif (deviceType == "DIMMABLE_LIGHT")
		then
		devType = "DIMMER"
	elseif (deviceType == "MOTION_SENSOR")
		then
		devType = "MOTION"
	elseif (deviceType == "DOOR_SENSOR")
		then
		devType = "DOOR"
	elseif (deviceType == "LIGHT_SENSOR")
		then
		devType = "LIGHT_LEVEL"
	elseif (deviceType == "WINDOW_COVERING")
		then
		devType = "COVER"
	end

	local devices = {}
	local altid = string.format(tableCategories[category][27], tableCategories[category][26],
	params[1], params[2], params[3])
	if (findChild(THIS_DEVICE, altid, nil) == nil)
		then
		table.insert(devices, { name, nil, altid, devType })
	end
	if (tableCategories[category][28] ~= nil and tableCategories[category][29] ~= nil)
		then
		altid = string.format(tableCategories[category][29], tableCategories[category][26],
		params[1], params[2], params[3])
		if (findChild(THIS_DEVICE, altid, nil) == nil)
			then
			table.insert(devices, { name, nil, altid, tableCategories[category][28] })
		end
	end
	if (tableCategories[category][30] ~= nil and tableCategories[category][31] ~= nil)
		then
		altid = string.format(tableCategories[category][31], tableCategories[category][26],
		params[1], params[2], params[3])
		if (findChild(THIS_DEVICE, altid, nil) == nil)
			then
			table.insert(devices, { name, nil, altid, tableCategories[category][30] })
		end
	end
	if (#devices > 0)
		then
		updateManagedDevices(devices, nil, nil)
	else
		task("CreateNewDevice: device already exists", TASK_ERROR)
	end
end

function changeDeviceType(deviceId, deviceType, name)

	debug("changeDeviceType " .. (deviceId or "nil") .. " " .. (deviceType or "nil"))

	if (deviceId ~= nil)
		then
		deviceId = tonumber(deviceId)
	end

	if (deviceId == nil)
		then
		warning("action ChangeDeviceType: missing value for the DeviceId argument")
		task("ChangeDeviceType: invalid arguments", TASK_ERROR)
		return
	elseif (luup.devices[deviceId] == nil)
		then
		warning("action ChangeDeviceType: the device " .. deviceId .. " does not exist")
		task("ChangeDeviceType: invalid arguments", TASK_ERROR)
		return
	end

	local altid = string.sub(luup.devices[deviceId].id, 4)

	local category = nil
	for k, v in pairs(tableCategories)
		do
		if (string.find(altid, v[26]) == 1)
			then
			category = k
			break
		end
	end
	if (category == nil)
		then
		warning("action ChangeDeviceType: invalid altid for the device " .. deviceId)
		task("ChangeDeviceType: invalid arguments", TASK_ERROR)
		return
	end

	local currentType = nil
	for _, deviceType in pairs(tableDeviceTypes)
		do
		if (string.find(luup.devices[deviceId].id, deviceType.prefix, 1) == 1)
			then
			currentType = deviceType
			break
		end
	end
	if (currentType == nil or currentType.jsDeviceType == nil)
		then
		warning("action ChangeDeviceType: the device type cannot be changed for the device " .. deviceId)
		task("ChangeDeviceType: forbidden for this device", TASK_ERROR)
		return
	elseif (deviceType == currentType.jsDeviceType and luup.devices[deviceId].device_type == currentType.deviceType)
		then
		warning("action ChangeDeviceType: the device " .. deviceId .. " has already the requested type")
		task("ChangeDeviceType: type is ok", TASK_ERROR)
		return
	end

	if (deviceType == nil)
		then
		warning("action ChangeDeviceType: missing value for the DeviceType argument")
		task("ChangeDeviceType: invalid arguments", TASK_ERROR)
		return
	elseif (deviceType ~= "SWITCH_LIGHT" and deviceType ~= "DIMMABLE_LIGHT"
		and deviceType ~= "MOTION_SENSOR" and deviceType ~= "DOOR_SENSOR"
		and deviceType ~= "LIGHT_SENSOR" and deviceType ~= "WINDOW_COVERING")
		then
		warning("action ChangeDeviceType: invalid value for the DeviceType argument")
		task("ChangeDeviceType: invalid arguments", TASK_ERROR)
		return
	elseif ((deviceType == "SWITCH_LIGHT" and not tableCategories[category][2])
		or (deviceType == "DIMMABLE_LIGHT" and not tableCategories[category][3])
		or (deviceType == "MOTION_SENSOR" and not tableCategories[category][4])
		or (deviceType == "DOOR_SENSOR" and not tableCategories[category][5])
		or (deviceType == "LIGHT_SENSOR" and not tableCategories[category][6])
		or (deviceType == "WINDOW_COVERING" and not tableCategories[category][7]))
		then
		warning("action ChangeDeviceType: DeviceType value not accepted for the device " .. deviceId)
		task("ChangeDeviceType: new type forbidden for this device", TASK_ERROR)
		return
	end

	local devType
	if (deviceType == "SWITCH_LIGHT")
		then
		devType = "LIGHT"
	elseif (deviceType == "DIMMABLE_LIGHT")
		then
		devType = "DIMMER"
	elseif (deviceType == "MOTION_SENSOR")
		then
		devType = "MOTION"
	elseif (deviceType == "DOOR_SENSOR")
		then
		devType = "DOOR"
	elseif (deviceType == "LIGHT_SENSOR")
		then
		devType = "LIGHT_LEVEL"
	elseif (deviceType == "WINDOW_COVERING")
		then
		devType = "COVER"
	end

	local newName = luup.devices[deviceId].description
	if (name ~= nil and name ~= "")
		then
		newName = name
	end
	debug("changeDeviceType " .. altid .. " " .. devType .. " "  .. newName)
	updateManagedDevices(nil,
		{ { newName,
			luup.devices[deviceId].room_num,
			altid,
	devType } },
	nil)

end

function deleteDevices(listDevices, disableCreation)

	debug("deleteDevices " .. (listDevices or "nil") .. " " .. (disableCreation or "nil"))

	local tableDeletion = {}
	if (listDevices ~= nil)
		then
		for value in string.gmatch(listDevices, "[%u%d/.]+")
			do
			table.insert(tableDeletion, value)
			if (disableCreation == "true" or disableCreation == "yes" or disableCreation == "1")
				then
				disableDevice(value)
			end
		end
	end

	updateManagedDevices(nil, nil, tableDeletion)

end

function sendUnusualCommand(deviceId, commandType)

	debug("sendUnusualCommand " .. (deviceId or "nil") .. " " .. (commandType or "nil"))

	if (deviceId ~= nil)
		then
		deviceId = tonumber(deviceId)
	end

	if (deviceId == nil)
		then
		warning("action SendCommand: missing value for the DeviceId argument")
		task("SendCommand: invalid arguments", TASK_ERROR)
		return
	elseif (luup.devices[deviceId] == nil)
		then
		warning("action SendCommand: the device " .. deviceId .. " does not exist")
		task("SendCommand: invalid arguments", TASK_ERROR)
		return
	end

	local id = luup.devices[deviceId].id

	local tableCommandTypes = {
		{ "L5.1/", "LEARN", tableMsgTypes.LIGHTING_EMW100.type, tableMsgTypes.LIGHTING_EMW100.subType, 0x02 },
		{ "L3.0/", "PROGRAM", tableMsgTypes.LIGHTING_KOPPLA.type, tableMsgTypes.LIGHTING_KOPPLA.subType, 0x1C },
		{ "C0/", "PROGRAM", tableMsgTypes.CURTAIN_HARRISON.type, tableMsgTypes.CURTAIN_HARRISON.subType, 0x03 },
		{ "B0/", "CONFIRM_PAIR", tableMsgTypes.BLIND_T0.type, tableMsgTypes.BLIND_T0.subType, 0x03 },
		{ "B1/", "CONFIRM_PAIR", tableMsgTypes.BLIND_T1.type, tableMsgTypes.BLIND_T1.subType, 0x03 },
		{ "B2/", "CONFIRM_PAIR", tableMsgTypes.BLIND_T2.type, tableMsgTypes.BLIND_T2.subType, 0x03 },
		{ "B3/", "CONFIRM_PAIR", tableMsgTypes.BLIND_T3.type, tableMsgTypes.BLIND_T3.subType, 0x03 },
		{ "B4/", "CONFIRM_PAIR", tableMsgTypes.BLIND_T4.type, tableMsgTypes.BLIND_T4.subType, 0x03 },
		{ "B6/", "CONFIRM_PAIR", tableMsgTypes.BLIND_T6.type, tableMsgTypes.BLIND_T6.subType, 0x03 },
		{ "B7/", "CONFIRM_PAIR", tableMsgTypes.BLIND_T7.type, tableMsgTypes.BLIND_T7.subType, 0x03 },
		{ "RFY0/", "PROGRAM", tableMsgTypes.RFY0.type, tableMsgTypes.RFY0.subType, 0x07 },
		{ "RFY0/", "LOWER_LIMIT", tableMsgTypes.RFY0.type, tableMsgTypes.RFY0.subType, 0x04 },
		{ "RFY0/", "UPPER_LIMIT", tableMsgTypes.RFY0.type, tableMsgTypes.RFY0.subType, 0x02 },
		{ "RFY0/", "VENETIAN_US_ANGLE_PLUS", tableMsgTypes.RFY0.type, tableMsgTypes.RFY0.subType, 0x11 },
		{ "RFY0/", "VENETIAN_US_ANGLE_MINUS", tableMsgTypes.RFY0.type, tableMsgTypes.RFY0.subType, 0x12 },
		{ "RFY0/", "VENETIAN_EU_ANGLE_PLUS", tableMsgTypes.RFY0.type, tableMsgTypes.RFY0.subType, 0x0F },
		{ "RFY0/", "VENETIAN_EU_ANGLE_MINUS", tableMsgTypes.RFY0.type, tableMsgTypes.RFY0.subType, 0x10 },
		{ "RFY0/", "ENABLE_DETECTOR", tableMsgTypes.RFY0.type, tableMsgTypes.RFY0.subType, 0x13 },
		{ "RFY0/", "DISABLE_DETECTOR", tableMsgTypes.RFY0.type, tableMsgTypes.RFY0.subType, 0x14 }
	}

	local idxCmd = nil
	for k, v in pairs(tableCommandTypes)
		do
		if ((string.find(id, v[1], 4) == 4) and (commandType == v[2]))
			then
			idxCmd = k
			break
		end
	end
	if (idxCmd == nil)
		then
		warning("action SendCommand: invalid command for the device " .. deviceId)
		task("SendCommand: invalid arguments", TASK_ERROR)
		return
	end

	debug("Command " .. tableCommandTypes[idxCmd].name .. " " .. tableCommandTypes[idxCmd].deviceType)

	local remoteId
	local housecode
	local unitcode
	local id4
	local data = nil

	if (idxCmd == 1)
		then
		remoteId = string.sub(id, 9, 17)
		data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16),
		tonumber(string.sub(remoteId, 5, 6), 16),
		tonumber(string.sub(remoteId, 8, 9)),
		tableCommandTypes[idxCmd][5], 0, 0)
	elseif (idxCmd == 2)
		then
		remoteId = tonumber(string.sub(id, 9, 9), 16)
		unitcode = tonumber(string.sub(id, 10, 11))
		local channel1 = 0
		local channel2 = 0
		if (unitcode >= 1 and unitcode <= 8)
			then
			channel1 = 1
			if (unitcode > 1)
				then
				channel1 = bitw.lshift(channel1, unitcode-1)
			end
		elseif (unitcode >= 9 and unitcode <= 10)
			then
			channel2 = 1
			if (unitcode > 9)
				then
				channel2 = bitw.lshift(channel2, unitcode-9)
			end
		end
		data = string.char(remoteId, channel1, channel2, tableCommandTypes[idxCmd][5], 0)
	elseif (idxCmd == 3)
		then
		housecode = string.sub(id, 7, 7)
		unitcode = tonumber(string.sub(id, 8, 9))
		data = housecode .. string.char(unitcode, tableCommandTypes[idxCmd][5], 0)
	elseif (idxCmd >= 4 and idxCmd <= 10)
		then
		remoteId = string.sub(id, 7, 12)
		if (tableCommandTypes[idxCmd][4] == tableMsgTypes.BLIND_T6.subType or tableCommandTypes[idxCmd][4] == tableMsgTypes.BLIND_T7.subType)
			then
			id4 = tonumber(string.sub(id, 13, 13), 16)
			unitcode = tonumber(string.sub(id, 15, 16)) % 16
		else
			id4 = 0
			unitcode = tonumber(string.sub(id, 14, 15)) % 16
		end
		data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16),
		tonumber(string.sub(remoteId, 5, 6), 16),
		id4 * 16 + unitcode, tableCommandTypes[idxCmd][5], 0)
	elseif (idxCmd >= 11 and idxCmd <= 19)
		then
		remoteId = string.sub(id, 9, 13)
		unitcode = tonumber(string.sub(id, 15, 16))
		data = string.char(tonumber(string.sub(remoteId, 1, 1), 16),
		tonumber(string.sub(remoteId, 2, 3), 16),
		tonumber(string.sub(remoteId, 4, 5), 16),
		unitcode, tableCommandTypes[idxCmd][5], 0, 0, 0, 0)
	end

	if (data ~= nil)
		then
		local tableCmds = {}
		table.insert(tableCmds, DeviceCmd( string.sub(id, 4), "", nil, 0 ))
		sendCommand(tableCommandTypes[idxCmd][3], tableCommandTypes[idxCmd][4], data, tableCmds)
	end

end

function receiveMessage(message)

	if (#message < 10)
		then
		warning("Action ReceiveMessage: invalid message")
		return
	end

	debug("Action ReceiveMessage: message received: " .. message)

	local msg = ""
	for i = 1, #message / 2
		do
		msg = msg .. string.char(tonumber(string.sub(message, i*2-1, i*2), 16))
	end

	decodeMessage(msg)

end

function sendMessage(message)

	if (#message < 10)
		then
		warning("Action SendMessage: invalid message - too short")
		return
	end

	debug("Action SendMessage: message to send: " .. message)

	local msg = ""
	for i = 1, #message / 2
		do
		msg = msg .. string.char(tonumber(string.sub(message, i*2-1, i*2), 16))
	end

	local length = string.byte(msg, 1)
	local type = string.byte(msg, 2)
	local subType = string.byte(msg, 3)
	local tableCmds = { { "", "", nil, 0 } }
	if(#msg ~= (length+1)) then
		warning("Action SendMessage: invalid message - incorrect length")
		return
	end
	sendCommand(type, subType, string.sub(msg, 5, length+1), tableCmds)

end

function setTemperatureUnit(unit)

	debug("setTemperatureUnit " .. (unit or "nil"))

	if (unit ~= "CELCIUS" and unit ~= "FAHRENHEIT")
		then
		task("SetTemperatureUnit: invalid argument", TASK_ERROR)
		return
	end

	local value = true
	if (unit == "FAHRENHEIT")
		then
		value = false
	end
	setVariable(THIS_DEVICE, tabVars.VAR_TEMP_UNIT, value)

end

function setLengthUnit(newUnit)

	debug("setLengthUnit " .. (newUnit or "nil"))
	if (newUnit ~= "MILLIMETERS" and newUnit ~= "INCHES")
		then
		task("setLengthUnit: invalid argument", TASK_ERROR)
		return
	end

	local value = true
	if (newUnit == "INCHES") then
		value = false
	end
	setVariable(THIS_DEVICE, tabVars.VAR_LENGTH_UNIT, value)
end

function setSpeedUnit(unit)

	debug("setSpeedUnit " .. (unit or "nil"))
	if (unit ~= "KMH" and unit ~= "MPH")
		then
		task("SetSpeedUnit: invalid argument", TASK_ERROR)
		return
	end

	local value = true
	if (unit == "MPH")
		then
		value = false
	end
	setVariable(THIS_DEVICE, tabVars.VAR_SPEED_UNIT, value)
end

function setVoltage(value)

	debug("setVoltage " .. (value or "nil"))
	setVariable(THIS_DEVICE, tabVars.VAR_VOLTAGE, value or 230)
end

function setAutoCreate(enable)

	debug("setAutoCreate " .. (enable or "nil"))
	if (enable ~= "true" and enable ~= "false")
		then
		task("SetAutoCreate: invalid argument", TASK_ERROR)
		return
	end
	local value = true
	if (enable == "false")
		then
		value = false
	end
	setVariable(THIS_DEVICE, tabVars.VAR_AUTO_CREATE, value)
end

function setDebugLogs(enable)

	debug("setDebugLogs " .. (enable or "nil"))
	if ((enable == "true") or (enable == "yes"))
		then
		enable = true
	elseif ((enable == "false") or (enable == "no"))
		then
		enable = false
	end
	if ((enable ~= false) and (enable ~= true))
		then
		task("SetDebugLogs: invalid argument", TASK_ERROR)
		return
	end
	setVariable(THIS_DEVICE, tabVars.VAR_DEBUG_LOGS, enable)
	DEBUG_MODE = enable

end

local function setMode()

	local msg3 = 0
	if (getVariable(THIS_DEVICE, tabVars.VAR_UNDECODED_RECEIVING))
		then
		msg3 = msg3 + 0x80
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_IMAGINTRONIX_RECEIVING))
		then
		msg3 = msg3 + 0x40
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_BYRONSX_RECEIVING))
		then
		msg3 = msg3 + 0x20
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_RSL_RECEIVING))
		then
		msg3 = msg3 + 0x10
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_LIGHTING4_RECEIVING))
		then
		msg3 = msg3 + 0x08
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_FINEOFFSET_RECEIVING))
		then
		msg3 = msg3 + 0x04
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_RUBICSON_RECEIVING))
		then
		msg3 = msg3 + 0x02
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_AE_RECEIVING))
		then
		msg3 = msg3 + 0x01
	end

	local msg4 = 0
	if (getVariable(THIS_DEVICE, tabVars.VAR_BLINDST1_RECEIVING))
		then
		msg4 = msg4 + 0x80
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_BLINDST0_RECEIVING))
		then
		msg4 = msg4 + 0x40
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_PROGUARD_RECEIVING))
		then
		msg4 = msg4 + 0x20
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_FS20_RECEIVING))
		then
		msg4 = msg4 + 0x10
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_LACROSSE_RECEIVING))
		then
		msg4 = msg4 + 0x08
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_HIDEKI_RECEIVING))
		then
		msg4 = msg4 + 0x04
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_AD_RECEIVING))
		then
		msg4 = msg4 + 0x02
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_MERTIK_RECEIVING))
		then
		msg4 = msg4 + 0x01
	end

	local msg5 = 0
	if (getVariable(THIS_DEVICE, tabVars.VAR_VISONIC_RECEIVING))
		then
		msg5 = msg5 + 0x80
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_ATI_RECEIVING))
		then
		msg5 = msg5 + 0x40
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_OREGON_RECEIVING))
		then
		msg5 = msg5 + 0x20
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_MEIANTECH_RECEIVING))
		then
		msg5 = msg5 + 0x10
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_HEU_RECEIVING))
		then
		msg5 = msg5 + 0x08
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_AC_RECEIVING))
		then
		msg5 = msg5 + 0x04
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_ARC_RECEIVING))
		then
		msg5 = msg5 + 0x02
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_X10_RECEIVING))
		then
		msg5 = msg5 + 0x01
	end

	local msg6 = 0
	if (getVariable(THIS_DEVICE, tabVars.VAR_HOMECONFORT_RECEIVING))
		then
		msg6 = msg6 + 0x02
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_KEELOQ_RECEIVING))
		then
		msg6 = msg6 + 0x01
	end

	local data = string.char(3, typeRFX, 0, msg3, msg4, msg5, msg6, 0, 0, 0)
	sendCommand(tableMsgTypes.MODE_COMMAND.type, tableMsgTypes.MODE_COMMAND.subType, data, nil)

end

function setupReceiving(protocol, enable)

	debug("setupReceiving " .. (protocol or "nil") .. " " .. (enable or "nil"))

	local tabProtocols = {
		X10Receiving = "VAR_X10_RECEIVING",
		ARCReceiving = "VAR_ARC_RECEIVING",
		ACReceiving = "VAR_AC_RECEIVING",
		HEUReceiving = "VAR_HEU_RECEIVING",
		MeiantechReceiving = "VAR_MEIANTECH_RECEIVING",
		OregonReceiving = "VAR_OREGON_RECEIVING",
		ATIReceiving = "VAR_ATI_RECEIVING",
		VisonicReceiving = "VAR_VISONIC_RECEIVING",
		MertikReceiving = "VAR_MERTIK_RECEIVING",
		ADReceiving = "VAR_AD_RECEIVING",
		HidekiReceiving = "VAR_HIDEKI_RECEIVING",
		LaCrosseReceiving = "VAR_LACROSSE_RECEIVING",
		FS20Receiving = "VAR_FS20_RECEIVING",
		ProGuardReceiving = "VAR_PROGUARD_RECEIVING",
		BlindsT0Receiving = "VAR_BLINDST0_RECEIVING",
		BlindsT1Receiving = "VAR_BLINDST1_RECEIVING",
		AEReceiving = "VAR_AE_RECEIVING",
		RubicsonReceiving = "VAR_RUBICSON_RECEIVING",
		FineOffsetReceiving = "VAR_FINEOFFSET_RECEIVING",
		Lighting4Receiving = "VAR_LIGHTING4_RECEIVING",
		RSLReceiving = "VAR_RSL_RECEIVING",
		ByronSXReceiving = "VAR_BYRONSX_RECEIVING",
		ImagintronixReceiving = "VAR_IMAGINTRONIX_RECEIVING",
		KeelogReceiving = "VAR_KEELOQ_RECEIVING",
		HomeConfortReceiving = "VAR_HOMECONFORT_RECEIVING",
		UndecodedReceiving = "VAR_UNDECODED_RECEIVING"
	}

	local valid = true

	if (protocol == nil or tabProtocols[protocol] == nil)
		then
		warning("SetupReceiving: unexpected value for first argument")
		valid = false
	end

	if ((enable == "true") or (enable == "yes") or (enable == 1))
		then
		enable = "1"
	elseif ((enable == "false") or (enable == "no") or (enable == 0))
		then
		enable = "0"
	end
	if ((enable ~= "0") and (enable ~= "1"))
		then
		warning("SetupReceiving: unexpected value for second argument")
		valid = false
	end

	if (not valid)
		then
		task("SetupReceiving: invalid arguments", TASK_ERROR)
		return
	end

	setVariable(THIS_DEVICE, tabVars[tabProtocols[protocol]], enable)
	setMode()

end
