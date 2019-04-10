module("L_RFXtrx", package.seeall)

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
	mt.__call = function(class_tbl,...)
		local obj = {}
		setmetatable(obj,c)
		if init then
			init(obj,...)
		else
			-- make sure that any stuff from the base class is initialized!
			if base and base.init then
				base.init(obj,...)
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

local bitw = require("bit")

local PLUGIN_VERSION = "1.81"

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

local DEBUG_MODE = false

local DATA_MSG_RESET = string.char(0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
local DATA_MSG_GET_STATUS = string.char(2, 0, 0, 0, 0, 0, 0, 0, 0, 0)
local DATA_MSG_SAVE = string.char(6, 0, 0, 0, 0, 0, 0, 0, 0, 0)

-- Forward definitions
local findChild
local getVariable
local tableMsgTypes

local function log(text, level)
	luup.log("RFXtrx: "..text, (level or 50))
end

local function warning(stuff)
	log("warning: "..stuff, 2)
end

local function error(stuff)
	log("error: "..stuff, 1)
end

local function debug(stuff)
	if (DEBUG_MODE) then
		log("dbg: "..stuff)
	end
end

local CmdCodeCmd = class(function(a, cmdCode, cmd)
	a.cmdCode = cmdCode	-- the command to be sent to the device
	a.cmd = cmd			-- the command to be acted on for the UI - translates to a variable
end)

-- Function called when an unhandled input message is received from the RFXtrx
local function decodeUnkMsg()
	warning("Unhandled message received.")
	return {}
end

-- Function called when an attempt is made to create a message to be transmitted
-- from an unrecognized UI input.
local function createUnkMsg()
	warning("Attempt to create untransmitted message.")
	return nil
end

-----------------------------------------------------------------------------------------
-- LUA is all about tables. Since this plugin's main purpose is to translate UI commands into
--  device command codes or device command codes into UI updates, it uses lots of tables.
--
-- This table keeps track of messages sent by the plugin to the RFXtrx
-- Each entry is a table of 2 elements:
-- 1) sequence number of the message
-- 2) table of commands
local tableMsgSent = {}
--
-- A class for commands
local Command = class(function(a, name, deviceType, variable)
	a.name = name				-- Name of the command
	a.deviceType = deviceType	-- the device type it operates on
	a.variable = variable		-- the variable used or modified (may be nil)
end)

-- A class method to print a command class object
function Command:__tostring()
	return("Command.name: "..self.name.." .deviceType: "..self.deviceType..' .variable: '..self.variable or 'nil')
end

local CmdAction = class(function(a, cmd, action)
	a.cmd = cmd			-- the command to be acted on for the UI - translates to a variable
	a.actin = action	-- the associated action, used as a value for a variable
end)

-- The table defines all commands used by the plugin
-- Each command object (defined above)
-- 1) command (a string)
-- 2) type of the device to act on or create
-- 3) variable (can be nil for commands that don't require a value)
local tableCommandTypes = {
	CMD_ON = Command("On", "LIGHT", "VAR_LIGHT"),
	CMD_OFF = Command("Off", "LIGHT", "VAR_LIGHT"),
	CMD_LIGHT = Command("Light", "LIGHT", "VAR_LIGHT"),
	CMD_OPEN = Command("Open", "COVER", nil),
	CMD_CLOSE = Command("Close", "COVER", nil),
	CMD_STOP = Command("Stop", "COVER", nil),
	CMD_DIM = Command("Dim", "DIMMER", "VAR_DIMMER"),
	CMD_DIMLAST = Command("DimLast", "DIMMER", "VAR_DIMMERLAST"),
	CMD_PROGRAM = Command("Program", nil, nil),
	CMD_FANLIGHT = Command("Light", "FAN", "VAR_LIGHT"),
	CMD_REVERSE = Command("Reverse", "FAN", "VAR_REVERSE"),
	CMD_SPEED = Command("Speed", "FAN", "VAR_SPEED"),
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
-- These tables are used to translate an action initiated in the UI
--  into a device command code. All of the command codes are here
--  even though there may not be a UI button to trigger some of them.
local tableActions2CmdCodes = {
	-- Lighting devices
	L1Action2CmdCode = {
		['Off'] = 0x00,
		['On'] = 0x01,
		['Dim'] = 0x02,
		['Bright'] = 0x03,
		['Program'] = 0x04,
		['GroupOff'] = 0x05,
		['GroupOn'] = 0x06,
		['Chime'] = 0x07
	},
	L2Action2CmdCode = {
		['Off'] = 0x00,
		['On'] = 0x01,
		['SetLevel'] = 0x02,
		['Dim'] = 0x02,	-- The command resulting from the JSON file
		['GroupOff'] = 0x03,
		['GroupOn'] = 0x04,
		['SetGroupLevel'] = 0x05
	},
	L5aAction2CmdCode = {
		['Off'] = 0x00,
		['Toggle'] = 0x00,
		['On'] = 0x01,
		['GroupOff'] = 0x02,
		['Learn'] = 0x02,
		['GroupOn'] = 0x03,
		['Mood1'] = 0x03,
		['Mood2'] = 0x04,
		['Mood3'] = 0x05,
		['Mood4'] = 0x06,
		['Mood5'] = 0x07,
		['reserved1'] = 0x08,
		['reserved2'] = 0x09,
		['Unlock'] = 0x0A,
		['Lock'] = 0x0B,
		['AllLock'] = 0x0C,
		['Close'] = 0x0D,
		['Stop'] = 0x0E,
		['Open'] = 0x0F,
		['SetLevel'] = 0x10,
		['ColourPalette'] = 0x11,
		['ColourTone'] = 0x12,
		['ColourCycle'] = 0x13,
		['Power'] = 0x00,
		['Light'] = 0x01,
		['Bright'] = 0x02,
		['Dim'] = 0x03,
		['100%'] = 0x04,
		['50%'] = 0x05,
		['25%'] = 0x06,
		['Mode+'] = 0x07,
		['Speed-'] = 0x08,
		['Speed+'] = 0x09,
		['Mode-'] = 0x0A,
		['Color+'] = 0x04,
		['Color-'] = 0x05,
		['SelectColor'] = 0xFF
	},
	L5bAction2CmdCode = {
		['Off'] = 0x03,
		['On'] = 0x02,
		['GroupOff'] = 0x00,
		['ToggleGang1'] = 0x01,
		['ToggleGang2'] = 0x02,
		['ToggleGang3'] = 0x03,
		['Bright'] = 0x02,
		['Dim'] = 0x03,
		['Toggle1'] = 0x01,
		['Toggle2'] = 0x02,
		['Toggle3'] = 0x03,
		['Toggle4'] = 0x04,
		['Toggle5'] = 0x05,
		['Toggle6'] = 0x06,
		['Toggle7'] = 0x07,
		['Bright7'] = 0x08,
		['Dim7'] = 0x09,
		['Toggle8'] = 0x0A,
		['Toggle9'] = 0x0B,
		['Bright9'] = 0x0C,
		['Dim9'] = 0x0D,
		['Toggle10'] = 0x0E,
		['Scene1'] = 0x0F,
		['Scene2'] = 0x10,
		['Scene3'] = 0x11,
		['Scene4'] = 0x12,
		['OK_Set'] = 0x13
	},
	L5cAction2CmdCode = {
		['Power'] = 0x00,
		['Bright'] = 0x01,
		['Dim'] = 0x02,
		['100%'] = 0x03,
		['80%'] = 0x04,
		['60%'] = 0x05,
		['40%'] = 0x06,
		['20%'] = 0x07,
		['10%'] = 0x08,
	},
	L6Action2CmdCode = {
		['Off'] = 0x01,
		['On'] = 0x00,
		['GroupOn'] = 0x02,
		['GroupOff'] = 0x03
	},
	-- Blinds, window covers
	BaAction2CmdCode = {
		['Open'] = 0x00,
		['Close'] = 0x01,
		['Stop'] = 0x02,
		['Confirm_Pair'] = 0x03,
		['SetLimit'] = 0x04,
		['SetLowerLimit'] = 0x05,
		['DeleteLimits'] = 0x06,
		['ChangeDir'] = 0x07,
		['Left'] = 0x08,
		['Right'] = 0x09,
		['IntPosA'] = 0x04,
		['ChangeAngle+'] = 0x04,
		['ChangeAngle-'] = 0x05
	},
	BbAction2CmdCode = {
		['Open'] = 0x00,
		['Close'] = 0x01,
		['Stop'] = 0x02,
		['Confirm_Pair'] = 0x03,
		['SetLimit'] = 0x04,
		['SetLowerLimit'] = 0x05,
		['ChangeDir'] = 0x06,
		['IntPosA'] = 0x07,
		['IntPosCntr'] = 0x08,
		['IntPosB'] = 0x09,
		['EraseChannel'] = 0x0A,
		['EraseChannels'] = 0x0B
	},
	BcAction2CmdCode = {
		['Open'] = 0x00,
		['Close'] = 0x01,
		['Stop'] = 0x02,
		['Confirm_Pair'] = 0x03,
		['ChangeDir'] = 0x06,
		['EraseChannel'] = 0x05,
		['LearnMaster'] = 0x04
	},
	BdAction2CmdCode = {
		['Open'] = 0x00,
		['Close'] = 0x01,
		['Stop'] = 0x02,
		['Confirm_Pair'] = 0x03,
		['ChangeDir'] = 0x05,
		['EraseChannel'] = 0x04
	},
	-- Both Up and Open and Down and Close are defined for each RFY type
	--  even though a particular device will only really respond to Up or Open
	--  and Down or close. Doing this avoids a lot of if-then-else code
	MotorAction2CmdCode = {
		['Up'] = 0x01,
		['Open'] = 0x01,
		['Down'] = 0x03,
		['Close'] = 0x03,
		['Stop'] = 0x00,
		['Program'] = 0x07
	},
	CentralisAction2CmdCode = {
		['Up'] = 0x11,
		['Open'] = 0x11,
		['Down'] = 0x12,
		['UpperLimit'] = 0x02,
		['LowerLimit'] = 0x04,
		['Close'] = 0x12,
		['Stop'] = 0x00
	},
	VenetianUSAction2CmdCode = {
		['Open'] = 0x0F,
		['Up'] = 0x0F,
		['Close'] = 0x10,
		['Down'] = 0x10,
		['Stop'] = 0x00,
		['Angle+'] = 0x11,
		['Angle-'] = 0x12,
		['Program'] = 0x07
	},
	VenetianEUAction2CmdCode = {
		['Open'] = 0x11,
		['Up'] = 0x11,
		['Close'] = 0x12,
		['Down'] = 0x12,
		['Stop'] = 0x00,
		['Angle+'] = 0x0F,
		['Angle-'] = 0x10,
	},
	AwningAction2CmdCode = {
		['Up'] = 0x01,
		['Open'] = 0x01,
		['Down'] = 0x03,
		['Close'] = 0x03,
		['Stop'] = 0x00,
		['UpperLimit'] = 0x02,
		['LowerLimit'] = 0x04,
		['Program'] = 0x07,
		['Disable'] = 0x14,
		['Enable'] = 0x13
	},
	CAction2CmdCode = {
		['Open'] = 0x00,
		['Close'] = 0x01,
		['Stop'] = 0x02,
		['Program'] = 0x03
	},
	SAction2CmdCode = {
		['Off1'] = 0x10,
		['Off2'] = 0x12,
		['On1'] = 0x11,
		['On2'] = 0x13
	},
	-- Fans
	FaAction2CmdCode = { -- Siemens -> Fan0.json
		['Timer']	= CmdCodeCmd(0x01, nil),
		['SpeedDown']= CmdCodeCmd(0x02, tableCommandTypes.CMD_SPEED),
		['Learn']	= CmdCodeCmd(0x03, nil),
		['SpeedUp']	= CmdCodeCmd(0x04, tableCommandTypes.CMD_SPEED),
		['Confirm']	= CmdCodeCmd(0x05, nil),
		['Light']	= CmdCodeCmd(0x06, tableCommandTypes.CMD_FANLIGHT)
		},
	FbAction2CmdCode = { -- Lucci Air, Westinghouse, Casafan -> Fan2.json
		['Hi']		= CmdCodeCmd(0x01, tableCommandTypes.CMD_SPEED),
		['Med']		= CmdCodeCmd(0x02, tableCommandTypes.CMD_SPEED),
		['Low']		= CmdCodeCmd(0x03, tableCommandTypes.CMD_SPEED),
		['Off']		= CmdCodeCmd(0x04, tableCommandTypes.CMD_SPEED),
		['Light']	= CmdCodeCmd(0x05, tableCommandTypes.CMD_FANLIGHT)
		},
	FcAction2CmdCode = { -- Lucci Air DC -> Fan5.json
		['Power']	= CmdCodeCmd(0x01, tableCommandTypes.CMD_DIM),
		['SpeedUp']	= CmdCodeCmd(0x02, tableCommandTypes.CMD_SPEED),
		['SpeedDown']= CmdCodeCmd(0x03, tableCommandTypes.CMD_SPEED),
		['Light']	= CmdCodeCmd(0x04, tableCommandTypes.CMD_FANLIGHT),
		['Reverse']	= CmdCodeCmd(0x05, tableCommandTypes.CMD_REVERSE),
		['Flow']	= CmdCodeCmd(0x06, tableCommandTypes.CMD_SPEED),
		['Pair']	= CmdCodeCmd(0x07, nil)
		},
	FdAction2CmdCode = { -- Falmec -> Fan8.json
		['PowerOff']= CmdCodeCmd(0x01, tableCommandTypes.CMD_SPEED),
		['Speed1']	= CmdCodeCmd(0x02, tableCommandTypes.CMD_SPEED),
		['Speed2']	= CmdCodeCmd(0x03, tableCommandTypes.CMD_SPEED),
		['Speed3']	= CmdCodeCmd(0x04, tableCommandTypes.CMD_SPEED),
		['Speed4']	= CmdCodeCmd(0x05, tableCommandTypes.CMD_SPEED),
		['Timer1']	= CmdCodeCmd(0x06, nil),
		['Timer2']	= CmdCodeCmd(0x07, nil),
		['Timer3']	= CmdCodeCmd(0x08, nil),
		['Timer4']	= CmdCodeCmd(0x09, nil),
		['LightOn']	= CmdCodeCmd(0x0A, tableCommandTypes.CMD_FANLIGHT),
		['LightOff']= CmdCodeCmd(0x0B, tableCommandTypes.CMD_FANLIGHT)
		},
	FeAction2CmdCode = { -- Seav
		['T1']		= CmdCodeCmd(0x04, nil),
		['T2']		= CmdCodeCmd(0x05, nil),
		['T3']		= CmdCodeCmd(0x06, nil),
		['T4']		= CmdCodeCmd(0x07, nil)
	},
	FfAction2CmdCode = { -- FT1211R -> Fan7.json
		['Power']	= CmdCodeCmd(0x01, tableCommandTypes.CMD_SPEED),
		['Light']	= CmdCodeCmd(0x02, tableCommandTypes.CMD_FANLIGHT),
		['One']		= CmdCodeCmd(0x03, tableCommandTypes.CMD_SPEED),
		['Two']		= CmdCodeCmd(0x04, tableCommandTypes.CMD_SPEED),
		['Three']	= CmdCodeCmd(0x05, tableCommandTypes.CMD_SPEED),
		['Four']	= CmdCodeCmd(0x06, tableCommandTypes.CMD_SPEED),
		['Five']	= CmdCodeCmd(0x07, tableCommandTypes.CMD_SPEED),
		['Reverse']	= CmdCodeCmd(0x08, tableCommandTypes.CMD_REVERSE),
		['1H']		= CmdCodeCmd(0x09, nil),
		['4H']		= CmdCodeCmd(0x0A, nil),
		['8H']		= CmdCodeCmd(0x0B, nil)
	},
	FgAction2CmdCode = { -- Lucci Air DC II -> Fan9.json
		['Off']		= CmdCodeCmd(0x01, tableCommandTypes.CMD_SPEED),
		['One']		= CmdCodeCmd(0x02, tableCommandTypes.CMD_SPEED),
		['Two']		= CmdCodeCmd(0x03, tableCommandTypes.CMD_SPEED),
		['Three']	= CmdCodeCmd(0x04, tableCommandTypes.CMD_SPEED),
		['Four']	= CmdCodeCmd(0x05, tableCommandTypes.CMD_SPEED),
		['Five']	= CmdCodeCmd(0x06, tableCommandTypes.CMD_SPEED),
		['Six']		= CmdCodeCmd(0x07, tableCommandTypes.CMD_SPEED),
		['Light']	= CmdCodeCmd(0x08, tableCommandTypes.CMD_FANLIGHT),
		['Reverse']	= CmdCodeCmd(0x09, tableCommandTypes.CMD_REVERSE)
	},
	FhAction2CmdCode = { -- For Itho Fans - not implemented 868Mhz
		['One']		= CmdCodeCmd(0x01, tableCommandTypes.CMD_SPEED),
		['Two']		= CmdCodeCmd(0x02, tableCommandTypes.CMD_SPEED),
		['Three']	= CmdCodeCmd(0x03, tableCommandTypes.CMD_SPEED),
		['Timer']	= CmdCodeCmd(0x04, nil),
		['Away']	= CmdCodeCmd(0x05, nil),
		['Learn']	= CmdCodeCmd(0x06, nil),
		['Erase']	= CmdCodeCmd(0x07, nil)
	}
}
-- This table is initialized in deferredStartup
--  It is used to select a UI cmd uaing a command code received an incoming message
--  Currently it is only used for fan devices.
local tableCmdCodes2Commands = {
	FaCmdCode2Command = {},
	FbCmdCode2Command = {},
	FcCmdCode2Command = {},
	FdCmdCode2Command = {},
	FeCmdCode2Command = {},
	FfCmdCode2Command = {},
	FgCmdCode2Command = {},
	FhCmdCode2Command = {},
}

-- A table of JSON filenames associated with device altid prefix.
-- It is used to set the JSON file in cases where different files
-- exist for similar devices. This avoids the need for many device
-- files when only the JSON file is different. Entries are only needed
-- when the required JSON file differs from the one in the device file (D_<device>.xml)
-- Currently it is only used for fan devices.
local tableDevice2Json = {
	["F0"] = "D_Fan0.json",
	["F2"] = "D_Fan2.json",
	["F4"] = "D_Fan2.json",
	["F5"] = "D_Fan5.json",
	["F6"] = "D_Fan2.json",
	["F7"] = "D_Fan7.json",
	["F8"] = "D_Fan8.json",
	["F9"] = "D_Fan9.json",
	["L4.0"] = "D_SwitchToggle1.json"
	}
-- Define a class for commands to be processed
local DeviceCmd = class(function(a, altid, cmd, value, delay)
	a.altid = altid		-- the altid of the device to act on
	a.cmd = cmd			-- the Command object defining what to do. Most often this is a variable name
	a.value = value		-- the value data used by the command
	a.delay = delay		-- the delay amount for delayed message actions
end)

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
	VAR_DIMMERLAST = Variable( "urn:upnp-org:serviceId:Dimming1", "LoadLevelLast", false, false, true ),
	VAR_PRESSURE = Variable( "urn:upnp-org:serviceId:BarometerSensor1", "CurrentPressure", false, true, true ),
	VAR_FORECAST = Variable( "urn:upnp-org:serviceId:BarometerSensor1", "Forecast", false, false, true ),
	VAR_RAIN = Variable( "urn:upnp-org:serviceId:RainSensor1", "CurrentTRain", false, false, true ),
	VAR_RAIN24HRS = Variable( "urn:upnp-org:serviceId:RainSensor1", "Rain24Hrs", false, false, true ),
	VAR_RAINRATE = Variable( "urn:upnp-org:serviceId:RainSensor1", "CurrentRain", false, false, true ),
	VAR_WEEKNUM = Variable( "urn:upnp-org:serviceId:RainSensor1", "WeekNumber", false, false, true ),
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
	VAR_REVERSE = Variable( "urn:rfxcom-com:serviceId:Fan1", "Reversed", false, false, true ),
	VAR_SPEED = Variable( "urn:rfxcom-com:serviceId:Fan1", "Speed", false, false, true ),
	VAR_COMM_FAILURE = Variable( "urn:micasaverde-com:serviceId:HaDevice1", "CommFailure", false, false, true ),
	VAR_COMM_STRENGTH = Variable( "urn:micasaverde-com:serviceId:HaDevice1", "CommStrength", false, false, true ),

	VAR_PLUGIN_VERSION = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "PluginVersion", false, false, true ),
	VAR_AUTO_CREATE = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "AutoCreate", true, false, true ),
	VAR_DISABLED_DEVICES = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "DisabledDevices", false, false, true ),
	VAR_FIRMWARE_VERSION = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "FirmwareVersion", false, false, true ),
	VAR_FIRMWARE_TYPE = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "FirmwareType", false, false, true ),
	VAR_HARDWARE_VERSION = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "HardwareVersion", false, false, true ),
	VAR_NOISE = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "NoiseLevel", false, false, true ),
	VAR_TEMP_UNIT = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "CelciusTemp", true, false, true ),
	VAR_LENGTH_UNIT = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "MMLength", true, false, true ),
	VAR_SPEED_UNIT = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "KmhSpeed", true, false, true ),
	VAR_VOLTAGE = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "Voltage", false, false, true ),
	VAR_VERATIME = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "VeraTime", false, false, false ),
	VAR_VERAPORT = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "IPPort", false, false, true ),
	VAR_UNDECODED_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "UndecodedReceiving", true, false, true ),
	VAR_IMAGINTRONIX_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "ImagintronixReceiving", true, false, true ),
	VAR_BYRONSX_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "ByronSXReceiving", true, false, true ),
	VAR_RSL_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "RSLReceiving", true, false, true ),
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
	VAR_FUNKBUS_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "FunkbusReceiving", true, false, true ),
	VAR_MCZ_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "MCZReceiving", true, false, true ),
	VAR_HOMECONFORT_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "HomeconfortReceiving", true, false, true ),
	VAR_KEELOQ_RECEIVING = Variable( "upnp-rfxcom-com:serviceId:rfxtrx1", "KeeloqReceiving", true, false, true ),
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
-- A class for a device parameter and value to be used when creating a new device
local Parameter = class(function(a, variable, value)
	a.variable = variable
	a.value = value
end)
-- These are parameters (variables and values) to be used when creating a new device
local tableParams = {
	ADJUSTMENTS = {
		Parameter(tabVars.VAR_ADJUST_MULTIPLIER, "1.0"),
		Parameter(tabVars.VAR_ADJUST_CONSTANT, "0.0"),
		Parameter(tabVars.VAR_ADJUST_CONSTANT2, "0.0")
	},
	LIGHT = {
		Parameter(tabVars.VAR_LIGHT, "0"),
		Parameter(tabVars.VAR_REPEAT_EVENT, "0")
	},
	DIMMER = {
		Parameter(tabVars.VAR_DIMMER, "0"),
		Parameter(tabVars.VAR_LIGHT, "0")
	},
	DOOR = {
		Parameter(tabVars.VAR_ARMEDTRIPPED, "0"),
		Parameter(tabVars.VAR_REPEAT_EVENT, "1"),
		Parameter(tabVars.VAR_TRIPPED, "0"),
		Parameter(tabVars.VAR_ARMED, "0"),
		Parameter(tabVars.VAR_AUTOUNTRIP, "0")
	},
	LIGHT_LEVEL = {
		Parameter(tabVars.VAR_LIGHT_LEVEL, "0")
	},
	FAN = {
		Parameter(tabVars.VAR_LIGHT, "0"),
		Parameter(tabVars.VAR_REVERSE, "0"),
		Parameter(tabVars.VAR_SPEED, "Off")
	},
	ALARM = {
		Parameter(tabVars.VAR_EXIT_DELAY, "0")
	}
}
-- Define a class for devices
local Device = class(function(a, deviceType, deviceFile, name, prefix, hasAssociation, hasMode, hasAdjustments, jsDeviceType, parameters)
	a.deviceType = deviceType			-- the upnp device type
	a.deviceFile = deviceFile			-- the upnp device definition file D_<device>.xml
	a.name = name						-- the device name
	a.prefix = prefix					-- a prefix for the altid
	a.hasAssociation = hasAssociation	-- used to enable device conversions
	a.hasMode = hasMode					-- used to allow setting device modes
	a.hasAdjustments = hasAdjustments	-- on device creation, creates offset and multiplier variables
	a.jsDeviceType = jsDeviceType		-- the device type sent from the js file
	a.parameters = parameters			-- the parameters (variables and values) to include when creating a device
end)

-- This table defines all the device types that can be managed by the plugin
-- Name = Device(
-- 	device type (URN)
-- 	XML description file
-- 	Prefix for the device name - TODO: this parameter is never used?
--	Prefix for the device id
--	a boolean indicating if variable "Association" must be created for this device type
--	a boolean indicating if variable "RFYMode" must be created for this device type
--	a boolean indicating if variables "AdjustMultiplier" and "AdjustConstant" must be created for this device type
--	the device type sent from the js file)
local tableDeviceTypes = {
	DOOR = Device("urn:schemas-micasaverde-com:device:DoorSensor:1", "D_DoorSensor1.xml", "RFX Door ", "DS/", false, false, false, "DOOR", tableParams.DOOR ),
	MOTION = Device("urn:schemas-micasaverde-com:device:MotionSensor:1", "D_MotionSensor1.xml", "RFX Motion ", "MS/", false, false, false, "MOTION", tableParams.DOOR ),
	SMOKE = Device("urn:schemas-micasaverde-com:device:SmokeSensor:1", "D_SmokeSensor1.xml", "RFX Smoke ", "SS/", false, false, false, nil, tableParams.DOOR ),
	LIGHT = Device("urn:schemas-upnp-org:device:BinaryLight:1", "D_BinaryLight1.xml", "RFX Light ", "LS/", true, false, false, "LIGHT", tableParams.LIGHT ),
	DIMMER = Device("urn:schemas-upnp-org:device:DimmableLight:1", "D_DimmableLight1.xml", "RFX dim Light ", "DL/", true, false, false, "DIMMER", tableParams.DIMMER ),
	COVER = Device("urn:schemas-micasaverde-com:device:WindowCovering:1", "D_WindowCovering1.xml", "RFX Window ", "WC/", true, true, false, "COVER", tableParams.DIMMER  ),
	FAN = Device("urn:rfxcom-com:device:Fan:1", "D_Fan1.xml", "RFX Fan ", "FN/", false, false, false, "FAN", tableParams.FAN ),
	TEMP = Device("urn:schemas-micasaverde-com:device:TemperatureSensor:1", "D_TemperatureSensor1.xml", "RFX Temp ", "TS/", false, false, true, nil, tableParams.ADJUSTMENTS ),
	HUM = Device("urn:schemas-micasaverde-com:device:HumiditySensor:1", "D_HumiditySensor1.xml", "RFX Hum ", "HS/", false, false, true, nil, tableParams.ADJUSTMENTS ),
	BARO = Device("urn:schemas-micasaverde-com:device:BarometerSensor:1", "D_BarometerSensor1.xml", "RFX Baro ", "BS/", false, false, true, nil, tableParams.ADJUSTMENTS ),
	WIND = Device("urn:schemas-micasaverde-com:device:WindSensor:1", "D_WindSensor1.xml", "RFX Wind ", "WS/", false, false, false, nil ),
	RAIN = Device("urn:schemas-micasaverde-com:device:RainSensor:1", "D_RainSensor1.xml", "RFX Rain ", "RS/", false, false, false, nil ),
	UV = Device("urn:schemas-micasaverde-com:device:UvSensor:1", "D_UvSensor1.xml", "RFX UV ", "UV/", false, false, true, nil, tableParams.ADJUSTMENTS ),
	WEIGHT = Device("urn:schemas-micasaverde-com:device:ScaleSensor:1", "D_ScaleSensor1.xml", "RFX Weight ", "WT/", false, false, false, nil ),
	POWER = Device("urn:schemas-micasaverde-com:device:PowerMeter:1", "D_PowerMeter1.xml", "RFX Power ", "PM/", false, false, false, nil ),
	RFXMETER = Device("urn:casa-delanghe-com:device:RFXMeter:1", "D_RFXMeter1.xml", "RFX Meter ", "RM/", false, false, false, nil ),
	ALARM = Device("urn:rfxcom-com:device:SecurityRemote:1", "D_SecurityRemote1.xml", "RFX Remote ", "SR/", false, false, false, nil ),
	REMOTE = Device("urn:rfxcom-com:device:X10ChaconRemote:1", "D_X10ChaconRemote1.xml", "RFX Remote ", "RC/", false, false, false, nil ),
	LWRF_REMOTE = Device("urn:rfxcom-com:device:LWRFRemote:1", "D_LWRFRemote1.xml", "RFX Remote ", "RC/", false, false, false, nil ),
	ATI_REMOTE = Device("urn:rfxcom-com:device:ATIRemote:1", "D_ATIRemote1.xml", "RFX Remote ", "RC/", false, false, false, nil ),
	HEATER = Device("urn:schemas-upnp-org:device:Heater:1", "D_Heater1.xml", "RFX Heater ", "HT/", false, false, false, nil ),
	LIGHT_LEVEL = Device("urn:schemas-micasaverde-com:device:LightSensor:1", "D_LightSensor1.xml", "RFX Light level ", "LL/", false, false, false, "LIGHT_LEVEL", tableParams.LIGHT_LEVEL )
}

-- Define a class for parameter limits
local Limit = class(function(a, minimum, maximum)
	a.minimum = minimum			-- the minimum value for the parameter
	a.maximum = maximum			-- the maximum value for the parameter
end)

-- Define a class for a device category
-- A category is a specific subtype of one of the device types shown above
local Category = class(function(a, displayName, isaLIGHT, isaDIMMER, isaMOTION, isaDOOR, isaLIGHT_LEVEL, isaCOVER, isaFAN,
						idLimits, houseCodeLimits, groupCodeLimits, unitCodeLimits, systemCodeLimits, channelLimits,
						subAltid, altidFmt, type2, altid2Fmt, type3, altid3Fmt)
	a.displayName = displayName
	a.isaLIGHT = isaLIGHT
	a.isaDIMMER = isaDIMMER
	a.isaMOTION = isaMOTION
	a.isaDOOR = isaDOOR
	a.isaLIGHT_LEVEL = isaLIGHT_LEVEL
	a.isaCOVER = isaCOVER
	a.isaFAN = isaFAN
	a.isCreatable = isaLIGHT or isaDIMMER or isaMOTION or isaDOOR or isaLIGHT_LEVEL or isaCOVER or isaFAN
	a.idLimits = idLimits
	a.houseCodeLimits = houseCodeLimits
	a.groupCodeLimits = groupCodeLimits
	a.unitCodeLimits = unitCodeLimits
	a.systemCodeLimits = systemCodeLimits
	a.channelLimits = channelLimits
	a.subAltid = subAltid
	a.altidFmt = altidFmt
	a.type2 = type2
	a.altid2Fmt = altid2Fmt
	a.type3 = type3
	a.altid3Fmt = altid3Fmt
end)

local tableCategories = {
	A_OK_AC114 = Category(	"A-OK AC114", false, false, false, false, false, true, false,
		Limit(1, 0xFFFFFF),
		nil,
		nil,
		nil,
		nil,
		nil,
	"B3/", "%s%06X/00", nil, nil, nil, nil	),
	A_OK_RF01 = Category(	"A-OK RF01", false, false, false, false, false, true, false,
		Limit(1, 0xFFFFFF),
		nil,
		nil,
		nil,
		nil,
		nil,
	"B2/", "%s%06X/00", nil, nil, nil, nil	),
	AC = Category(	"AC", true, true, true, true, true, true, false,
		Limit(1, 0x3FFFFFF),
		nil,
		nil,
		Limit(1, 16),
		nil,
		nil,
	"L2.0/", "%s%07X/%02d", "REMOTE", "%s%07X", nil, nil	),
	ANSLUT = Category(	"ANSLUT", true, true, false, false, false, false, false,
		Limit(1, 0x3FFFFFF),
		nil,
		nil,
		Limit(1, 16),
		nil,
		nil,
	"L2.2/", "%s%07X/%02d", "REMOTE", "%s%07X", nil, nil	),
	ARC = Category(	"ARC", true, false, true, true, false, false, false,
		nil,
		Limit(0x41, 0x50),
		nil,
		Limit(1, 16),
		nil,
		nil,
	"L1.1/", "%s%s%02d", "REMOTE", "%s%s", nil, nil	),
	ASA = Category(	"ASA", false, false, false, false, false, true, false,
		Limit(1, 0x0FFFFF),
		nil,
		nil,
		Limit(1, 5),
		nil,
		nil,
	"RFY.3/", "%s%05X/%02d", nil, nil, nil, nil	),
	BBSB = Category(	"Bye Bye Standby (new)", true, false, false, false, false, false, false,
		Limit(1, 0x7FFFF),
		nil,
		nil,
		Limit(1, 6),
		nil,
		nil,
	"L5.2/", "%s%06X/%02d", "REMOTE", "%s%06X", nil, nil	),
	BLYSS = Category(	"Blyss", true, false, true, true, false, false, false,
		Limit(0, 0xFFFF),
		nil,
		Limit(0x41, 0x50),
		Limit(1, 5),
		nil,
		nil,
	"L6.0/", "%s%04X/%s%d", "REMOTE", "%s%04X/%s", nil, nil	),
	CASAFAN = Category(	"Casafan", false, false, false, false, false, false, true,
		Limit(0, 0x00000F),
		nil,
		nil,
		nil,
		nil,
		nil,
	"F6/", "%s%06X", nil, nil, nil, nil	),
	COCO = Category(	"COCO GDR2-2000R", true, false, false, false, false, false, false,
		nil,
		Limit(0x41, 0x44),
		nil,
		Limit(1, 4),
		nil,
		nil,
	"L1.A/", "%s%s%02d", nil, nil, nil, nil	),
	DC_RMF_YOODA = Category(	"DC106, YOODA, Rohrmotor24 RMF", false, false, false, false, false, true, false,
		Limit(1, 0x0FFFFFFF),
		nil,
		nil,
		Limit(0, 15),
		nil,
		nil,
	"B6/", "%s%07X/%02d", nil, nil, nil, nil	),
	ELRO_AB400D = Category(	"ELRO AB400D, Flamingo, Sartano", true, false, false, false, false, false, false,
		nil,
		Limit(0x41, 0x50),
		nil,
		Limit(1, 64),
		nil,
		nil,
	"L1.2/", "%s%s%02d", nil, nil, nil, nil	),
	EMW100 = Category(	"GAO/Everflourish EMW100", true, false, false, false, false, false, false,
		Limit(1, 0x3FFF),
		nil,
		nil,
		Limit(1, 4),
		nil,
		nil,
	"L5.1/", "%s%06X/%02d", nil, nil, nil, nil	),
	EMW200 = Category(	"Chacon EMW200", true, false, false, false, false, false, false,
		nil,
		Limit(0x41, 0x43),
		nil,
		Limit(1, 4),
		nil,
		nil,
	"L1.4/", "%s%s%02d", nil, nil, nil, nil	),
	ENERGENIE_5GANG = Category(	"Energenie 5 gang", true, false, false, false, false, false, false,
		nil,
		Limit(0x41, 0x50),
		nil,
		Limit(1, 10),
		nil,
		nil,
	"L1.9/", "%s%s%02d", nil, nil, nil, nil	),
	ENERGENIE_ENER010 = Category(	"Energenie ENER010", true, false, false, false, false, false, false,
		nil,
		Limit(0x41, 0x50),
		nil,
		Limit(1, 4),
		nil,
		nil,
	"L1.8/", "%s%s%02d", "REMOTE", "%s%s", nil, nil	),
	FALMEC_FAN = Category(	"Falmec Fan", false, false, false, false, false, false, true,
		Limit(0, 0x00000F),
		nil,
		nil,
		nil,
		nil,
		nil,
	"F8/", "%s%06X", nil, nil, nil, nil	),
	FOREST = Category(	"Forest", false, false, false, false, false, true, false,
		Limit(1, 0x0FFFFFFF),
		nil,
		nil,
		Limit(0, 15),
		nil,
		nil,
	"B7/", "%s%07X/%02d", nil, nil, nil, nil	),
	FT1211R_FAN = Category(	"FT1211R Fan", false, false, false, false, false, false, true,
		Limit(1, 0x00FFFF),
		nil,
		nil,
		nil,
		nil,
		nil,
	"F7/", "%s%06X", nil, nil, nil, nil	),
	HARRISON_CURTAIN = Category(	"Harrison Curtain", false, false, false, false, false, true, false,
		nil,
		Limit(0x41, 0x50),
		nil,
		Limit(1, 16),
		nil,
		nil,
	"C0/", "%s%s%02d", nil, nil, nil, nil	),
	HASTA_NEW = Category(	"Hasta (new)", false, false, false, false, false, true, false,
		Limit(1, 0xFFFF),
		nil,
		nil,
		Limit(0, 15),
		nil,
		nil,
	"B0/", "%s%06X/%02d", nil, nil, nil, nil	),
	HASTA_OLD = Category(	"Hasta (old)", false, false, false, false, false, true, false,
		Limit(1, 0xFFFF),
		nil,
		nil,
		Limit(0, 15),
		nil,
		nil,
	"B1/", "%s%06X/%02d", nil, nil, nil, nil	),
	HOMEEASY_EU = Category(	"HomeEasy EU", true, true, false, false, false, false, false,
		Limit(1, 0x3FFFFFF),
		nil,
		nil,
		Limit(1, 16),
		nil,
		nil,
	"L2.1/", "%s%07X/%02d", "REMOTE", "%s%07X", nil, nil	),
	IKEA_KOPPLA = Category(	"Ikea Koppla", true, false, false, false, false, false, false,
		nil,
		nil,
		nil,
		nil,
		Limit(1, 16),
		Limit(1, 10),
	"L3.0/", "%s%X%02d", nil, nil, nil, nil	),
	IMPULS = Category(	"Impuls", true, false, false, false, false, false, false,
		nil,
		Limit(0x41, 0x50),
		nil,
		Limit(1, 64),
		nil,
		nil,
	"L1.5/", "%s%s%02d", nil, nil, nil, nil	),
	KANGTAI = Category(	"Kangtai", true, false, false, false, false, false, false,
		Limit(1, 0xFFFF),
		nil,
		nil,
		Limit(1,30),
		nil,
		nil,
	"L5.11/", "%s%06X/%02d", "REMOTE", "%s%06X", nil, nil	),
	LIGHTWAVERF_SIEMENS = Category(	"LightwaveRF, Siemens", true, true, true, true, false, true, false,
		Limit(1, 0xFFFFFF),
		nil,
		nil,
		Limit(1, 16),
		nil,
		nil,
	"L5.0/", "%s%06X/%02d", "LWRF_REMOTE", "%s%06X", nil, nil	),
	LIVOLO_1GANG = Category(	"Livolo (1 gang)", true, true, false, false, false, false, false,
		Limit(1, 0xFFFF),
		nil,
		nil,
		nil,
		nil,
		nil,
	"L5.5/", "%s%06X/1", nil, nil, nil, nil	),
	LIVOLO_2GANG = Category(	"Livolo (2 gang)", true, false, false, false, false, false, false,
		Limit(1, 0xFFFF),
		nil,
		nil,
		nil,
		nil,
		nil,
	"L5.5/", "%s%06X/1", "LIGHT", "%s%06X/2", nil, nil	),
	LIVOLO_3GANG = Category(	"Livolo (3 gang)", true, false, false, false, false, false, false,
		Limit(1, 0xFFFF),
		nil,
		nil,
		nil,
		nil,
		nil,
	"L5.5/", "%s%06X/1", "LIGHT", "%s%06X/2", "LIGHT", "%s%06X/3"	),
	LUCCI_AIR_DC = Category(	"Lucci Air DC", false, false, false, false, false, false, true,
		Limit(0, 0x0F),
		nil,
		nil,
		nil,
		nil,
		nil,
	"F5/", "%s%06X", nil, nil, nil, nil	),
	LUCCI_AIR_DCII = Category(	"Lucci Air DCII", false, false, false, false, false, false, true,
		Limit(0, 0x0F),
		nil,
		nil,
		nil,
		nil,
		nil,
	"F9/", "%s%06X", nil, nil, nil, nil	),
	LUCCI_AIR_FAN = Category(	"Lucci Air Fan", false, false, false, false, false, false, true,
		Limit(0, 0x0F),
		nil,
		nil,
		nil,
		nil,
		nil,
	"F2/", "%s%06X", nil, nil, nil, nil	),
	MEDIA_MOUNT = Category(	"Media Mount projector screen", false, false, false, false, false, true, false,
		Limit(1, 0xFFFFFF),
		nil,
		nil,
		nil,
		nil,
		nil,
	"B5/", "%s%06X/00", nil, nil, nil, nil	),
	PHENIX = Category(	"Phenix", true, false, false, false, false, false, false,
		nil,
		Limit(0x41, 0x50),
		nil,
		Limit(1,32),
		nil,
		nil,
	"L1.2/", "%s%s%02d", nil, nil, nil, nil	),
	PHILIPS_SBC = Category(	"Philips SBC", true, false, false, false, false, false, false,
		nil,
		Limit(0x41, 0x50),
		nil,
		Limit(1, 8),
		nil,
		nil,
	"L1.7/", "%s%s%02d", "REMOTE", "%s%s", nil, nil	),
	RAEX = Category(	"Raex YR1326 T16 motor", false, false, false, false, false, true, false,
		Limit(1, 0xFFFFFF),
		nil,
		nil,
		nil,
		nil,
		nil,
	"B4/", "%s%06X/00", nil, nil, nil, nil	),
	RFY0 = Category(	"Somfy RTS", false, false, false, false, false, true, false,
		Limit(1, 0x0FFFFF),
		nil,
		nil,
		Limit(0, 4),
		nil,
		nil,
	"RFY.0/", "%s%05X/%02d", nil, nil, nil, nil	),
	RFY1 = Category(	"Somfy RTS", false, false, false, false, false, true, false,
		Limit(1, 0x0FFFFF),
		nil,
		nil,
		Limit(0, 4),
		nil,
		nil,
	"RFY.1/", "%s%05X/%02d", nil, nil, nil, nil	),
	RISINGSUN = Category(	"RisingSun", true, false, false, false, false, false, false,
		nil,
		Limit(0x41, 0x44),
		nil,
		Limit(1, 4),
		nil,
		nil,
	"L1.6/", "%s%s%02d", nil, nil, nil, nil	),
	ROLLERTROL = Category(	"RollerTrol", false, false, false, false, false, true, false,
		Limit(1, 0xFFFF),
		nil,
		nil,
		Limit(0, 15),
		nil,
		nil,
	"B0/", "%s%06X/%02d", nil, nil, nil, nil	),
	RSL2 = Category(	"Conrad RSL2", true, false, false, false, false, false, false,
		Limit(1, 0xFFFFFF),
		nil,
		nil,
		Limit(1, 16),
		nil,
		nil,
	"L5.4/", "%s%06X/%02d", "REMOTE", "%s%06X", nil, nil	),
	SEAV = Category(	"SEAV TXS4 Fan", false, false, false, false, false, true, false,
		Limit(1, 0x0FFFFF),
		nil,
		nil,
		nil,
		nil,
		nil,
	"F3/", "%s%06X", nil, nil, nil, nil	),
	SIEMENS_WAVE = Category(	"Siemens/Wave Design Fan", false, false, false, false, false, false, true,
		Limit(1, 0x00FFFF),
		nil,
		nil,
		nil,
		nil,
		nil,
	"F0/", "%s%06X", nil, nil, nil, nil	),
	SONOFF = Category(	"Sonoff Smart Switch", true, false, false, false, false, false, false,
		Limit(1, 0xFFFFFF),
		nil,
		nil,
		nil,
		nil,
		nil,
	"L4.0/", "%s%06X/00", nil, nil, nil, nil	),
	WAVEMAN = Category(	"Waveman", true, false, false, false, false, false, false,
		nil,
		Limit(0x41, 0x50),
		nil,
		Limit(1, 16),
		nil,
		nil,
	"L1.3/", "%s%s%02d", nil, nil, nil, nil	),
	WESTINGHOUSE_FAN = Category(	"Westinghouse Fan", false, false, false, false, false, false, true,
		Limit(0, 0x0F),
		nil,
		nil,
		nil,
		nil,
		nil,
	"F4/", "%s%06X", nil, nil, nil, nil	),
	X10 = Category(	"X10 lighting", true, false, true, false, true, false, false,
		nil,
		Limit(0x41, 0x50),
		nil,
		Limit(1, 16),
		nil,
		nil,
	"L1.0/", "%s%s%02d", "REMOTE", "%s%s", nil, nil	)
}

-- This table is initialized in deferredStartup and is used to select a category
-- from the above table
-- tableCategoryBySubAltid is used to selected a category by its subAltid
local tableCategoryBySubAltid = {}

-- J_RFXtrx.js depends on the text of these table items
local tableHardwareType = {
	[0x50] = "RFXtrx315 at 310 MHz",
	[0x51] = "RFXtrx315 at 315 MHz",
	[0x52] = "RFXrec433 at 433.92 MHz",
	[0x53] = "RFXtrx433 at 433.92 MHz",
	[0x54] = "RFXtrx433 at 433.42 MHz",
	[0x55] = "RFXtrx868X operating at 868 MHz",
	[0x56] = "RFXtrx868X operating at 868.00 MHz FSK",
	[0x57] = "RFXtrx868X operating at 868.30 MHz",
	[0x58] = "RFXtrx868X operating at 868.30 MHz FSK",
	[0x59] = "RFXtrx868X operating at 868.35 MHz",
	[0x5A] = "RFXtrx868X operating at 868.35 MHz FSK",
	[0x5B] = "RFXtrx868X operating at 868.95 MHz",
	[0x5C] = "RFXtrx433IOT at 433.92 MHz",
	[0x5D] = "RFXtrx433IOT at 868 MHz",
	[0x5E] = "RFXtrx433IOT at 868 MHz",
	[0x5F] = "RFXtrx433 at 434.50 MHz"
	}

local tableFirmwareType = {
	"Type1 receive only",
	"Type1",
	"Type2",
	"Ext",
	"Ext2",
	"Pro1",
	"Pro2",
	"unknown",
	"unknown",
	"unknown",
	"unknown",
	"unknown",
	"unknown",
	"unknown",
	"unknown",
	"unknown",
	"ProXL1"
	}

-- The following functions are used to create a string of bytes to be transmitted
-- to a device. The functions are given a character string representing the device altid
-- and a command action. The altid contains the ID of the device which may include an
-- ordinary id number or any of a housecode, a groupcode, a unitcode, a systemcode
-- or a channel. Each function is particular to the device type intended to receive
-- the message. It should work properly for all subtypes of that device type.  These
-- functions are designed to handle all possible actions for a device type and
-- subtype - even if the user interface does not yet provide a way of triggering all actions.
local function createL1MsgData(altid, action)
	local cmdCode, subType, data, housecode, unitCode
	cmdCode = tableActions2CmdCodes.L1Action2CmdCode[action]
	subType = tonumber(string.match(altid, '[^%.]+%.([^/]+)/'), 16)
	debug("L1Msg-> altid: "..altid.." action: "..action.." subType: "..(string.format("0x%02X", subType) or 'nil').." cmdCode: "..(string.format("0x%02X", cmdCode) or 'nil'))
	if not (cmdCode) then
		warning("createL1MsgData - no cmdCode for given action "..action)
		return
	end
	housecode = string.sub(altid, 9, 9)
	unitCode = tonumber(string.sub(altid, 10, 11))
	-- If this command is from an RC device the unitCode will be nil
	if not (unitCode) then unitCode = 1 end
	data = housecode..string.char(unitCode, cmdCode, 0)
	return data, 1
end

local function createL2MsgData(altid, action, level)
	local cmdCode, subType, data, remoteId, unitCode
	cmdCode = tableActions2CmdCodes.L2Action2CmdCode[action]
	subType = tonumber(string.match(altid, '[^%.]+%.([^/]+)/'), 16)
	debug("L2Msg-> altid: "..altid.." action: "..action.." subType: "..(string.format("0x%02X", subType) or 'nil').." cmdCode: "..(string.format("0x%02X", cmdCode) or 'nil').." level: "..(level or 'nil'))
	if not (cmdCode) then
		warning("createL2MsgData - no cmdCode for given action "..action)
		return
	end
	-- Level may need to be converted to the proper range
	if ((action == 'SetLevel') or (action == 'Dim') and level) then
		level = math.floor(level * 0x0F / 100 + 0.5)
	else
		level = 0
	end
	remoteId = string.sub(altid, 9, 18)
	unitCode = tonumber(string.sub(remoteId, 9, 10))
	-- If this command is from an RC device the unitCode will be nil
	if not (unitCode) then unitCode = 1 end
	data = string.char(tonumber(string.sub(remoteId, 1, 1), 16),
		tonumber(string.sub(remoteId, 2, 3), 16),
		tonumber(string.sub(remoteId, 4, 5), 16),
		tonumber(string.sub(remoteId, 6, 7), 16),
		unitCode, cmdCode, level, 0)
	return data, 1
end

local function createL3MsgData(altid, action, level)
	local cmdCode, subType, data, remoteId, unitcode, channel1, channel2
	cmdCode = tableActions2CmdCodes.L3Action2CmdCode[action]
	subType = tonumber(string.match(altid, '[^%.]+%.([^/]+)/'), 16)
	debug("L3Msg-> altid: "..altid.." action: "..action.." subType: "..(string.format("0x%02X", subType) or 'nil').." cmdCode: "..(string.format("0x%02X", cmdCode) or 'nil').." level: "..(level or 'nil'))
	if not (cmdCode) then
		warning("createL3MsgData - no cmdCode for given action "..action)
		return
	end
	level = tonumber(level)
	if (level) then
		if (level == 0) then cmdCode = tableActions2CmdCodes.L3Action2CmdCode['Off']
		elseif (level == 100) then cmdCode = tableActions2CmdCodes.L3Action2CmdCode['On']
		else -- level must be >= 1 and <= 9
			level = math.min(math.max(math.floor(level / 10 + 0.5),1),9)
			cmdCode = level + 0x10
		end
	end
	remoteId = tonumber(string.sub(altid, 9, 9), 16)
	unitcode = tonumber(string.sub(altid, 10, 11))
	channel1 = 0
	channel2 = 0
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
	return data, 1
end

local function createL4MsgData(altid)
	local data, remoteId
	debug("L4Msg-> altid: "..altid)
	remoteId = string.sub(altid, 9, 14)
	data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16),
		tonumber(string.sub(remoteId, 5, 6), 16),
		tonumber("01", 16),
		tonumber("76", 16),
		0)
	return data, 1
end

local function createL5MsgData(altid, action, level)
	local subTypeTblSelect = {
		tableActions2CmdCodes.L5aAction2CmdCode,	-- subtype 0
		tableActions2CmdCodes.L5aAction2CmdCode,	-- subtype 1
		tableActions2CmdCodes.L5aAction2CmdCode,	--   .
		tableActions2CmdCodes.L5aAction2CmdCode,	--   .
		tableActions2CmdCodes.L5aAction2CmdCode,	--   .
		tableActions2CmdCodes.L5bAction2CmdCode,	-- subtype 5
		tableActions2CmdCodes.L5aAction2CmdCode,
		tableActions2CmdCodes.L5aAction2CmdCode,
		tableActions2CmdCodes.L5aAction2CmdCode,
		tableActions2CmdCodes.L5aAction2CmdCode,
		tableActions2CmdCodes.L5bAction2CmdCode,	-- subtype 0x0A
		tableActions2CmdCodes.L5aAction2CmdCode,
		tableActions2CmdCodes.L5cAction2CmdCode,	-- subtype 0x0C
		tableActions2CmdCodes.L5aAction2CmdCode,
		tableActions2CmdCodes.L5aAction2CmdCode,
		tableActions2CmdCodes.L5aAction2CmdCode,
		tableActions2CmdCodes.L5aAction2CmdCode,
		tableActions2CmdCodes.L5aAction2CmdCode
	}
	local subType, cmdCode, remoteId, unitCode, data
	local nbTimes = 1
	subType = tonumber(string.match(altid, '[^%.]+%.([^/]+)/'), 16)
	remoteId = string.match(altid, '/[^/]+/(.+)')
	unitCode = tonumber(string.sub(remoteId, 8, 9))
	-- If this command is from an RC device the unitCode will be nil
	if not (unitCode) then unitCode = 1 end
	cmdCode = subTypeTblSelect[subType+1][action]
	-- ?? cmdCode = tonumber(string.sub(remoteId, 8, 8))
	debug("L5Msg-> altid: "..altid.." action: "..action.." subType: "..(string.format("0x%02X", subType) or 'nil').." cmdCode: "..(string.format("0x%02X", cmdCode) or 'nil').." level: "..(level or 'nil'))
	if not (cmdCode) then
		warning("createL5MsgData - no cmdCode for given action "..action)
		return
	end
	-- Level may need to be converted to the proper range
	if ((action == 'SetLevel') or (action == 'Dim') and level) then
		if (subType == 0) then
			level = math.max(math.floor(level * 0x1F / 100 + 0.5), 1)
		elseif (subType == 0x0F) then
			level = math.max(math.floor(level * 0x0F / 100 + 0.5), 1)
		end
	else
		level = 0
	end
	data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16),
		tonumber(string.sub(remoteId, 5, 6), 16),
		unitCode,
		cmdCode,
		level, 0)
	-- Special case to allow Livolo dimmer to respond to On and Off commands
	if ((subType == tableMsgTypes.LIGHTING_LIVOLO.subType) and (string.sub(altid, 1,2) == "DL")
		and ((action == 'On') or (action == 'Off'))) then nbTimes = 6 end
	return data, nbTimes
end

-- TODO L6 is for Blyss devices. We'll need global cmd seq numbers that are
-- incremented when we send commands AND when we see commands from a remote
local function createL6MsgData(altid, action)
	local cmdCode, subType, data, remoteId, unitCode, groupCode, cmdSeqNmbr
	cmdCode = tableActions2CmdCodes.L6Action2CmdCode[action]
	subType = tonumber(string.match(altid, '[^%.]+%.([^/]+)/'), 16)
	debug("L6Msg-> altid: "..altid.." action: "..action.." subType: "..(string.format("0x%02X", subType) or 'nil').." cmdCode: "..(string.format("0x%02X", cmdCode) or 'nil'))
	if not (cmdCode) then
		warning("createL6MsgData - no cmdCode for given action "..action)
		return
	end
	remoteId = string.sub(altid, 9, 12)
	groupCode = string.sub(altid, 14, 14)
	unitCode = tonumber(string.sub(altid, 15, 15))
	-- If this command is from an RC device the unitCode will be nil
	if not (unitCode) then unitCode = 1 end
	cmdSeqNmbr = 1	-- May need to fix this
	data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16))
		..groupCode
		..string.char(unitCode, cmdCode, cmdSeqNmbr, 0, 0)
	return data, 1
end

local function createBMsgData(altid, action, level)
	local subTypeTblSelect = {
		tableActions2CmdCodes.BaAction2CmdCode,	-- subtype 0
		tableActions2CmdCodes.BaAction2CmdCode,	-- subtype 1
		tableActions2CmdCodes.BaAction2CmdCode,	--   .
		tableActions2CmdCodes.BaAction2CmdCode,	--   .
		tableActions2CmdCodes.BaAction2CmdCode,	--   .
		tableActions2CmdCodes.BaAction2CmdCode,
		tableActions2CmdCodes.BaAction2CmdCode,
		tableActions2CmdCodes.BaAction2CmdCode,
		tableActions2CmdCodes.BaAction2CmdCode,
		tableActions2CmdCodes.BbAction2CmdCode,	-- subtype 9
		tableActions2CmdCodes.BcAction2CmdCode,	-- subtype 0x0A
		tableActions2CmdCodes.BaAction2CmdCode,
		tableActions2CmdCodes.BdAction2CmdCode,	-- subtype 0x0C
		tableActions2CmdCodes.BaAction2CmdCode,
		tableActions2CmdCodes.BaAction2CmdCode,
		tableActions2CmdCodes.BaAction2CmdCode,
		tableActions2CmdCodes.BaAction2CmdCode
	}
	local subType, cmdCode, remoteId, unitCode, id4, data
	subType = tonumber(string.match(altid, 'WC/B([^/]+)/'), 16)
	cmdCode = subTypeTblSelect[subType+1][action]
	debug("BMsg-> altid: "..altid.." action: "..action.." subType: "..(string.format("0x%02X", subType) or 'nil').." cmdCode: "..(string.format("0x%02X", cmdCode) or 'nil').." level: "..(level or 'nil'))
	if not (cmdCode) then
		warning("createBMsgData - no cmdCode for given action "..action)
		return
	end
	remoteId = string.sub(altid, 7, 12)
	if (subType == 6 or subType == 7)
		then
		id4 = tonumber(string.sub(altid, 13, 13), 16)
		unitCode = tonumber(string.sub(altid, 15, 16)) % 16
	else
		id4 = 0
		unitCode = tonumber(string.sub(altid, 14, 15)) % 16
	end
	data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
	tonumber(string.sub(remoteId, 3, 4), 16),
	tonumber(string.sub(remoteId, 5, 6), 16),
	id4 * 16 + unitCode, cmdCode, 0)
	return data
end

local function createCMsgData(altid, action)
	local cmdCode, subType, houseCode, unitCode, data
	cmdCode = tableActions2CmdCodes.CAction2CmdCode[action]
	subType = tonumber(string.match(altid, 'WC/C([^/]+)/'), 16)
	debug("CMsg-> altid: "..altid.." action: "..action.." subType: "..(string.format("0x%02X", subType) or 'nil').." cmdCode: "..(string.format("0x%02X", cmdCode) or 'nil'))
	if not (cmdCode) then
		warning("createCMsgData - no cmdCode for given action "..action)
		return
	end
	houseCode = string.sub(altid, 7, 7)
	unitCode = tonumber(string.sub(altid, 8, 9))
	data = houseCode..string.char(unitCode, cmdCode, 0)
	return data
end

local function createSMsgData(altid, action)
	local cmdCode, remoteId, light_num
	local data = ""
	light_num = string.sub(altid, 9, 9)
	cmdCode = tableActions2CmdCodes.SAction2CmdCode[action..light_num]
	debug("SMsg-> altid: "..altid.." action: "..action.." cmdCode: "..(string.format("0x%02X", cmdCode) or 'nil'))
	if not (cmdCode) then
		warning("createSMsgData - no cmdCode for given action "..action)
		return
	end
	remoteId = string.sub(altid, 11, 16)
	data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16),
		tonumber(string.sub(remoteId, 5, 6), 16),
		cmdCode, 0)
	return data, 1
end

local function createRFYMsgData(altid, action)
	local deviceNum, cmdCode, subType, RFYType, remoteId, unitCode, data
	local subTypeTblSelect = {
		['STANDARD'] = tableActions2CmdCodes.VenetianUSAction2CmdCode,
		['EUROPEAN'] = tableActions2CmdCodes.VenetianEUAction2CmdCode,
		['CENTRALIS'] = tableActions2CmdCodes.CentralisAction2CmdCode,
		['MOTOR'] = tableActions2CmdCodes.MotorAction2CmdCode,
		['AWNING'] = tableActions2CmdCodes.AwningAction2CmdCode
	}
	subType = tonumber(string.match(altid, '[^%.]+%.([^/]+)/'), 16)
	-- Find the device so we can determine exactly what kind of RFY device this is
	deviceNum = findChild(THIS_DEVICE, string.sub(altid,4), tableDeviceTypes.COVER.deviceType)
	RFYType = getVariable(deviceNum, tabVars.VAR_RFY_MODE)
	cmdCode = subTypeTblSelect[RFYType][action]
	debug("RFYMsg-> altid: "..altid.." subType: "..(string.format("0x%02X", subType) or 'nil').." deviceNum: "..(deviceNum or 'nil').." RFYType: "..(RFYType or 'nil').." action: "..action.." cmdCode: "..(string.format("0x%02X", cmdCode) or 'nil'))
	if not (cmdCode) then
		warning("createRFYMsgData - no cmdCode for given action "..action)
		return
	end
	remoteId = string.match(altid, '/[^/]+/(.+)')
	unitCode = tonumber(string.sub(remoteId, 7, 8))
	data = string.char(tonumber(string.sub(remoteId, 1, 1), 16),
		tonumber(string.sub(remoteId, 2, 3), 16),
		tonumber(string.sub(remoteId, 4, 5), 16),
		unitCode, cmdCode, 0, 0, 0, 0)
	return data
end

local function createFMsgData(altid, action)
	local subTypeTblSelect = {
		tableActions2CmdCodes.FaAction2CmdCode,	-- subtype 0
		tableActions2CmdCodes.FhAction2CmdCode,	-- subtype 1
		tableActions2CmdCodes.FbAction2CmdCode,	--   .
		tableActions2CmdCodes.FeAction2CmdCode,	--   .
		tableActions2CmdCodes.FbAction2CmdCode,	--   .
		tableActions2CmdCodes.FcAction2CmdCode,	-- subtype 5
		tableActions2CmdCodes.FbAction2CmdCode,
		tableActions2CmdCodes.FfAction2CmdCode,
		tableActions2CmdCodes.FdAction2CmdCode,
		tableActions2CmdCodes.FgAction2CmdCode
	}
	local subType, thisCmdData, remoteId, data
	local cmdName = "nil cmd"
	subType = tonumber(string.match(altid, '/F([0-9])/'), 16)
	remoteId = string.match(altid, '/F[0-9]/(.+)')
	thisCmdData = subTypeTblSelect[subType+1][action]
	debug("FMsg-> altid: "..altid.." action: "..action.." subType: "..(string.format("0x%02X", subType) or 'nil'))
	if not (thisCmdData) then
		warning("createFMsgData - no thisCmdData for given action "..action)
		return
	end
	if (thisCmdData.cmd) then cmdName = thisCmdData.cmd.name end
	debug("FMsg-> cmd: "..cmdName.." cmdCode: "..(string.format("0x%02X", thisCmdData.cmdCode) or 'nil'))
	data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16),
		tonumber(string.sub(remoteId, 5, 6), 16),
		thisCmdData.cmdCode,
		0)
	return data, thisCmdData.cmd
end

-- Define a class for our message types
-- The subaltid is used to look up the message type to send in response to a UI input
--  since not all message types are transmitted the subAltID will not be used
-- The key is used to look up a message decode function in response to a received message
--  since some messages are transmit only, there is no need for a decode function
local Message = class(function(a, pktType, subType, length, subAltID, createMsgDataFunction)
	a.pktType = pktType					-- the packet type
	a.subType = subType					-- the subtype
	a.length = length					-- the length in bytes
	a.subAltID = subAltID				-- the second part of the device altid e.g. "L1.0" in LS/L1.0/B02
	a.key = string.format('%06X',(bitw.lshift((bitw.lshift(length,8) + pktType), 8)) + subType)
	a.decodeMsgFunction = decodeUnkMsg	-- the function used to decode a received message of this type
	a.createMsgDataFunction = createMsgDataFunction -- create data for a msg of this type to be transmitted
end)

-- A class method to print a message class object
function Message:__tostring()
	local part1 = "Message length: "..string.format("0x%02X", self.length).." pktType: "..string.format("0x%02X", self.pktType)
	local part2 = ' subType: '..self.subtype..' key: '..self.key or 'nil' --..' decode function: '..self.decodeMsgFunction or 'nil'
	return (part1..part2)
end

tableMsgTypes = {
	MODE_COMMAND =				Message( 0x00, 0x00, 13, 'M0.0/', createUnkMsg ),
	RESPONSE_MODE_COMMAND =		Message( 0x01, 0x00, 20, 'R1.0/', createUnkMsg ),
	UNKNOWN_RTS_REMOTE =		Message( 0x01, 0x01, 20, 'R1.1/', createUnkMsg ),
	INVALID_COMMAND =			Message( 0x01, 0xFF, 20, 'R1.FF/', createUnkMsg ),
	RECEIVER_LOCK_ERROR =		Message( 0x02, 0x00, 4, 'R2.0/', createUnkMsg ),
	TRANSMITTER_RESPONSE =		Message( 0x02, 0x01, 4, 'R2.1/', createUnkMsg ),
	UNDECODED =					Message( 0x03, 0x00, 36, 'U0.0/', createUnkMsg ),
	LIGHTING_X10 =				Message( 0x10, 0x0, 7, 'L1.0/', createL1MsgData ),
	LIGHTING_ARC =				Message( 0x10, 0x1, 7, 'L1.1/', createL1MsgData ),
	LIGHTING_AB400D =			Message( 0x10, 0x2, 7, 'L1.2/', createL1MsgData ),
	LIGHTING_WAVEMAN =			Message( 0x10, 0x3, 7, 'L1.3/', createL1MsgData ),
	LIGHTING_EMW200 =			Message( 0x10, 0x4, 7, 'L1.4/', createL1MsgData ),
	LIGHTING_IMPULS =			Message( 0x10, 0x5, 7, 'L1.5/', createL1MsgData ),
	LIGHTING_RISINGSUN =		Message( 0x10, 0x6, 7, 'L1.6/', createL1MsgData ),
	LIGHTING_PHILIPS =			Message( 0x10, 0x7, 7, 'L1.7/', createL1MsgData ),
	LIGHTING_ENERGENIE_ENER010 =Message( 0x10, 0x8, 7, 'L1.8/', createL1MsgData ),
	LIGHTING_ENERGENIE_5GANG =	Message( 0x10, 0x9, 7, 'L1.9/', createL1MsgData ),
	LIGHTING_COCO =				Message( 0x10, 0xa, 7, 'L1.A/', createL1MsgData ),
	LIGHTING_AC =				Message( 0x11, 0x0, 11, 'L2.0/', createL2MsgData ),
	LIGHTING_HEU =				Message( 0x11, 0x1, 11, 'L2.1/', createL2MsgData ),
	LIGHTING_ANSLUT =			Message( 0x11, 0x2, 11, 'L2.2/', createL2MsgData ),
	LIGHTING_KOPPLA =			Message( 0x12, 0x0, 8, 'L3.0/', createL3MsgData ),
	SECURITY_DOOR =				Message( 0x13, 0x0, 9, 'L4.0/', createL4MsgData ),
	LIGHTING_LIGHTWARERF =		Message( 0x14, 0x0, 10, 'L5.0/', createL5MsgData ),
	LIGHTING_EMW100 =			Message( 0x14, 0x1, 10, 'L5.1/', createL5MsgData ),
	LIGHTING_BBSB =				Message( 0x14, 0x2, 10, 'L5.2/', createL5MsgData ),
	LIGHTING_RSL2 =				Message( 0x14, 0x4, 10, 'L5.4/', createL5MsgData ),
	LIGHTING_LIVOLO =			Message( 0x14, 0x5, 10, 'L5.5/', createL5MsgData ),
	LIGHTING_KANGTAI =			Message( 0x14, 0x11, 10, 'L5.11/', createL5MsgData ),
	LIGHTING_BLYSS =			Message( 0x15, 0x0, 11, 'L6.0/', createL6MsgData ),
	FAN_T0 =					Message( 0x17, 0x0, 8, 'F0/', createFMsgData ),
	FAN_T1 =					Message( 0x17, 0x1, 8, 'F1/', createFMsgData ),
	FAN_T2 =					Message( 0x17, 0x2, 8, 'F2/', createFMsgData ),
	FAN_T3 =					Message( 0x17, 0x3, 8, 'F3/', createFMsgData ),
	FAN_T4 =					Message( 0x17, 0x4, 8, 'F4/', createFMsgData ),
	FAN_T5 =					Message( 0x17, 0x5, 8, 'F5/', createFMsgData ),
	FAN_T6 =					Message( 0x17, 0x6, 8, 'F6/', createFMsgData ),
	FAN_T7 =					Message( 0x17, 0x7, 8, 'F7/', createFMsgData ),
	FAN_T8 =					Message( 0x17, 0x8, 8, 'F8/', createFMsgData ),
	FAN_T9 =					Message( 0x17, 0x9, 8, 'F9/', createFMsgData ),
	CURTAIN_HARRISON =			Message( 0x18, 0x0, 7, 'C0/', createCMsgData ),
	BLIND_T0 =					Message( 0x19, 0x0, 9, 'B0/', createBMsgData ),
	BLIND_T1 =					Message( 0x19, 0x1, 9, 'B1/', createBMsgData ),
	BLIND_T2 =					Message( 0x19, 0x2, 9, 'B2/', createBMsgData ),
	BLIND_T3 =					Message( 0x19, 0x3, 9, 'B3/', createBMsgData ),
	BLIND_T4 =					Message( 0x19, 0x4, 9, 'B4/', createBMsgData ),
	BLIND_T5 =					Message( 0x19, 0x5, 9, 'B5/', createBMsgData ),
	BLIND_T6 =					Message( 0x19, 0x6, 9, 'B6/', createBMsgData ),
	BLIND_T7 =					Message( 0x19, 0x7, 9, 'B7/', createBMsgData ),
	RFY0 =						Message( 0x1A, 0x0, 12, 'RFY.0/', createRFYMsgData ),
	RFY1 =						Message( 0x1A, 0x1, 12, 'RFY.1/', createRFYMsgData ),
	ASA =						Message( 0x1A, 0x3, 12, 'RFY.3/', createRFYMsgData ),
	SECURITY_X10DS =			Message( 0x20, 0x0, 8, 'S1.0/', createUnkMsg ),
	SECURITY_X10MS =			Message( 0x20, 0x1, 8, 'S1.1/', createUnkMsg ),
	SECURITY_X10SR =			Message( 0x20, 0x2, 8, 'S1.2/', createUnkMsg ),
	KD101 =						Message( 0x20, 0x3, 8, 'S1.3/', createUnkMsg ),
	POWERCODE_PRIMDS =			Message( 0x20, 0x4, 8, 'S1.4/', createUnkMsg ),
	POWERCODE_MS =				Message( 0x20, 0x5, 8, 'S1.5/', createUnkMsg ),
	POWERCODE_AUXDS =			Message( 0x20, 0x7, 8, 'S1.7/', createUnkMsg ),
	SECURITY_MEISR =			Message( 0x20, 0x8, 8, 'S1.8/', createUnkMsg ),
	SA30 =						Message( 0x20, 0x9, 8, 'S1.9/', createUnkMsg ),
	ATI_REMOTE_WONDER =			Message( 0x30, 0x0, 6, 'RC.0/', createUnkMsg ),
	ATI_REMOTE_WONDER_PLUS =	Message( 0x30, 0x1, 6, 'RC.1/', createUnkMsg ),
	MEDION_REMOTE =				Message( 0x30, 0x2, 6, 'RC.2/', createUnkMsg ),
	X10_PC_REMOTE =				Message( 0x30, 0x3, 6, 'RC.3/', createUnkMsg ),
	ATI_REMOTE_WONDER_II =		Message( 0x30, 0x4, 6, 'RC.4/', createUnkMsg ),
	HEATER3_MERTIK1 =			Message( 0x42, 0x0, 8, 'HT3.0/', createUnkMsg ),
	HEATER3_MERTIK2 =			Message( 0x42, 0x1, 8, 'HT3.1/', createUnkMsg ),
	TR1 =						Message( 0x4F, 0x1, 10, 'TR.0/', createUnkMsg ),
	TEMP1 =						Message( 0x50, 0x1, 8, 'TS.1/', createUnkMsg ),
	TEMP2 =						Message( 0x50, 0x2, 8, 'TS.2/', createUnkMsg ),
	TEMP3 =						Message( 0x50, 0x3, 8, 'TS.3/', createUnkMsg ),
	TEMP4 =						Message( 0x50, 0x4, 8, 'TS.4/', createUnkMsg ),
	TEMP5 =						Message( 0x50, 0x5, 8, 'TS.5/', createUnkMsg ),
	TEMP6 =						Message( 0x50, 0x6, 8, 'TS.6/', createUnkMsg ),
	TEMP7 =						Message( 0x50, 0x7, 8, 'TS.7/', createUnkMsg ),
	TEMP8 =						Message( 0x50, 0x8, 8, 'TS.8/', createUnkMsg ),
	TEMP9 =						Message( 0x50, 0x9, 8, 'TS.9/', createUnkMsg ),
	TEMP10 =					Message( 0x50, 0xA, 8, 'TS.A/', createUnkMsg ),
	TEMP11 =					Message( 0x50, 0xB, 8, 'TS.B/', createUnkMsg ),
	HUM1 =						Message( 0x51, 0x1, 8, 'HS.1/', createUnkMsg ),
	HUM2 =						Message( 0x51, 0x2, 8, 'HS.2/', createUnkMsg ),
	TEMP_HUM1 =					Message( 0x52, 0x1, 10, 'TH.1/', createUnkMsg ),
	TEMP_HUM2 =					Message( 0x52, 0x2, 10, 'TH.2/', createUnkMsg ),
	TEMP_HUM3 =					Message( 0x52, 0x3, 10, 'TH.3/', createUnkMsg ),
	TEMP_HUM4 =					Message( 0x52, 0x4, 10, 'TH.4/', createUnkMsg ),
	TEMP_HUM5 =					Message( 0x52, 0x5, 10, 'TH.5/', createUnkMsg ),
	TEMP_HUM6 =					Message( 0x52, 0x6, 10, 'TH.6/', createUnkMsg ),
	TEMP_HUM7 =					Message( 0x52, 0x7, 10, 'TH.7/', createUnkMsg ),
	TEMP_HUM8 =					Message( 0x52, 0x8, 10, 'TH.8/', createUnkMsg ),
	TEMP_HUM9 =					Message( 0x52, 0x9, 10, 'TH.9/', createUnkMsg ),
	TEMP_HUM10 =				Message( 0x52, 0xa, 10, 'TH.A/', createUnkMsg ),
	TEMP_HUM11 =				Message( 0x52, 0xb, 10, 'TH.B/', createUnkMsg ),
	TEMP_HUM12 =				Message( 0x52, 0xc, 10, 'TH.C/', createUnkMsg ),
	TEMP_HUM13 =				Message( 0x52, 0xd, 10, 'TH.D/', createUnkMsg ),
	TEMP_HUM14 =				Message( 0x52, 0xe, 10, 'TH.E/', createUnkMsg ),
	BARO1 =						Message( 0x53, 0x1, 9, 'PS.1/', createUnkMsg ),
	TEMP_HUM_BARO1 =			Message( 0x54, 0x1, 13, 'THP.1/', createUnkMsg ),
	TEMP_HUM_BARO2 =			Message( 0x54, 0x2, 13, 'THP.2/', createUnkMsg ),
	RAIN1 =						Message( 0x55, 0x1, 11, 'RS.1/', createUnkMsg ),
	RAIN2 =						Message( 0x55, 0x2, 11, 'RS.2/', createUnkMsg ),
	RAIN3 =						Message( 0x55, 0x3, 11, 'RS.3/', createUnkMsg ),
	RAIN4 =						Message( 0x55, 0x4, 11, 'RS.4/', createUnkMsg ),
	RAIN5 =						Message( 0x55, 0x5, 11, 'RS.5/', createUnkMsg ),
	RAIN6 =						Message( 0x55, 0x6, 11, 'RS.6/', createUnkMsg ),
	RAIN7 =						Message( 0x55, 0x7, 11, 'RS.7/', createUnkMsg ),
	WIND1 =						Message( 0x56, 0x1, 16, 'WS.1/', createUnkMsg ),
	WIND2 =						Message( 0x56, 0x2, 16, 'WS.2/', createUnkMsg ),
	WIND3 =						Message( 0x56, 0x3, 16, 'WS.3/', createUnkMsg ),
	WIND4 =						Message( 0x56, 0x4, 16, 'WS.4/', createUnkMsg ),
	WIND5 =						Message( 0x56, 0x5, 16, 'WS.5/', createUnkMsg ),
	WIND6 =						Message( 0x56, 0x6, 16, 'WS.6/', createUnkMsg ),
	WIND7 =						Message( 0x56, 0x7, 16, 'WS.7/', createUnkMsg ),
	UV1 =						Message( 0x57, 0x1, 9, 'US.1/', createUnkMsg ),
	UV2 =						Message( 0x57, 0x2, 9, 'US.2/', createUnkMsg ),
	UV3 =						Message( 0x57, 0x3, 9, 'US.3/', createUnkMsg ),
	ELEC1 =						Message( 0x59, 0x1, 13, 'E1.1/', createUnkMsg ),
	ELEC2 =						Message( 0x5A, 0x1, 17, 'E2.1/', createUnkMsg ),
	ELEC3 =						Message( 0x5A, 0x2, 17, 'E3.2/', createUnkMsg ),
	ELEC4 =						Message( 0x5B, 0x1, 19, 'E4.1/', createUnkMsg ),
	WEIGHT1 =					Message( 0x5D, 0x1, 8, 'SS.1/', createUnkMsg ),
	WEIGHT2 =					Message( 0x5D, 0x2, 8, 'SS.2/', createUnkMsg ),
	RFXSENSOR_T =				Message( 0x70, 0x0, 7, 'RFX.0/', createUnkMsg ),
	RFXMETER =					Message( 0x71, 0x0, 10, 'RFXM.0/', createUnkMsg )
}

-- These two tables are initialized in deferredStartup and are used to select a message
-- type from the above table
-- tableMsgByKey is used decode a received message. The type to decode is selected
-- based on the length, type, and subtype found in the received message.
local tableMsgByKey = {}
-- tableMsgBySubID is used to select the message type to be created and sent in response to
-- input from the Vera user interface.
local tableMsgBySubID = {}

-- A table to speed up searching for a command
-- Used by searchCommandsTable(cmd)
--local tableCommandByCmd = {}

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

-- Category name = {Displayed name, is a LIGHT, is a DIMMIBLE_LIGHT, is a MOTION, is a DOOR, is a LIGHT_LEVEL, is a COVER
-- ID limits (nil if this doesn't apply), ID min, ID max
-- HouseCode limits
-- GroupCode limits
-- UnitCode limits
-- SystemCode limits
-- Channel limits
-- start of altid string, default altid string format, 2nd type, 2nd altid string format, third device type, third altid string format }

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

local function tableSize(theTable)
	local count = 0
	for _, _ in ipairs(theTable) do
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

	if ( psString  )
		then
		local liStringLength = 1 + #psString
		for teller = piStart, (piStart + piLen - 1)
			do
			-- if not beyond string length
			if ( liStringLength > teller )
				then
				lsResult = lsResult..string.sub(psString, teller, teller)
			end
		end
	end

	return lsResult
end

local function formattohex(dataBuf)

	local resultstr = ""
	if (dataBuf )
		then
		for idx = 1, string.len(dataBuf)
			do
			resultstr = resultstr..string.format("%02X ", string.byte(dataBuf, idx) )
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

function getVariable(deviceNum, variable)
	local value = nil
	if (variable)
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
	if (variable and value ~= nil)
		then
		local currentValue = luup.variable_get(variable.serviceId, variable.name, deviceNum)
		if(currentValue == nil) then
			debug("SET "..variable.name.." with default value "..value)
			luup.variable_set(variable.serviceId, variable.name, value, deviceNum)
		end
	end
end

local function setVariable(deviceNum, variable, value)
	if (variable and value ~= nil)
		then
		debug("setVariable - deviceNum: "..deviceNum.." variable: "..(variable.name or "nil").." value: "..tostring(value))
		if (type(value) == "number") then
			value = tostring(value)
		elseif (type(value) == 'boolean') then
			if (value) then
				value = '1'
			else
				value = '0'
			end
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
			luup.variable_set(variable.serviceId, variable.name, value, deviceNum)
		end

		if (variable == tabVars.VAR_TRIPPED and value == "1")
			then
			setVariable(deviceNum, tabVars.VAR_LAST_TRIP, os.time())
		elseif (variable == tabVars.VAR_BATTERY_LEVEL)
			then
			setVariable(deviceNum, tabVars.VAR_BATTERY_DATE, os.time())
		end
	else
		debug("setVariable - deviceNum: "..deviceNum.." variable: no variable given none set")
	end
end

local function initIDLookup()

	devicedIdNumByAltId = {}
	-- Build a table for selecting the device ID based on the altid
	for deviceNum, veraDevice in pairs(luup.devices) do
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

end

local function encodeCommandsInString(tableCmds)

	local str = ""
	if (tableCmds and (#tableCmds > 0))
		then
		for _, command in ipairs(tableCmds)
			do
			str = str..command.altid.."#"..command.cmd.."#"..(command.value or "nil").."\n"
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
		--debug("cmd="..cmd)
		for id, cmd, value in string.gmatch(cmdstr, "([%u%d/.]+)#([%a%d]+)#([%a%d/. ]+)")
			do
			if (value == "nil")
				then
				value = nil
			end
			--debug("id="..(id or "nil").." cmd="..(cmd or "nil").." value="..(value or "nil"))
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
	local countFN = 0
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
		elseif (key == "FAN")
			then
			countFN = countFN + 1
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
		end
	end
	log("Tree with number child devices: "..#tableDevices)
	log("       door sensors: "..countDS)
	log("     motion sensors: "..countMS)
	log("      light sensors: "..countLL)
	log("     light switches: "..countLS)
	log(" dim light switches: "..countDL)
	log("    window covering: "..countWC)
	log("               fans: "..countFN)
	log("temperature sensors: "..countTS)
	log("   humidity sensors: "..countHS)
	log(" barometric sensors: "..countBS)
	log("       wind sensors: "..countWS)
	log("       rain sensors: "..countRS)
	log("         UV sensors: "..countUV)
	log("     weight sensors: "..countWT)
	log("      power sensors: "..countPM)
	log("   security remotes: "..countSR)
	log("    remote controls: "..countRC)
	log("    heating devices: "..countHT)
	log("          RFXMeters: "..countRM)

end

local function logCmds(title, tableCmds)

	local str = title..": "
	if (tableCmds and #tableCmds > 0)
		then
		for _, command in ipairs(tableCmds)
			do
			str = str..(command.altid or "nil altid").." "
			if(command.cmd) then
				str = str..(command.cmd.name or "nil cmd.name")
			else
				str = str.."nil cmd"
			end
			str = str.." "..(command.value or "nil value").." "
			if (command.delay and tonumber(command.delay) > 0)
				then
				str = str.." delayed "..command.delay.."s"
			end
		end
	end
	debug(str)

end

local function findStrInStringList(list, str)

	if (list)
		then
		for value in string.gmatch(list, "[%u%d/.]+")
			do
			--debug("value = "..value)
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

function findChild(parentDevice, altid, deviceType)
	debug("findChild-> parentDevice: "..parentDevice.." altid: "..altid.." deviceType: "..(deviceType or 'nil'))
	local key = altid..(deviceType or "")
	local searchResult = tableDeviceNumByAltidAndType[key]
	if(searchResult) then
		if (searchResult[2]) then
			debug("devicenum found in table - key: "..key.." devicenum: "..searchResult[1].." myDevice: true")
			return searchResult[1]
		else
			debug("devicenum found in table - key: "..key.." devicenum: "..searchResult[1].." myDevice: false")
			return
		end
	end
	--debug("searching for devicenum "..key)
	for k, veraDevice in pairs(luup.devices)
		do
		if ((deviceType == nil) or (veraDevice.device_type == deviceType))
			then
			--debug("veraDevice.id: "..veraDevice.id.." parent: "..veraDevice.device_num_parent.." stringfind: "..(string.find(veraDevice.id, altid.."$", 4)or 'nil'))
--			if (veraDevice.device_num_parent == parentDevice and string.find(veraDevice.id, altid.."$", 4) == 4)
			if (veraDevice.device_num_parent == parentDevice and string.find(veraDevice.id, altid, 4, true) == 4)
				then
				tableDeviceNumByAltidAndType[key] = {k, true}
				debug("findChild succeeded->deviceNum: "..k)
				return k
			elseif (findAssociation(k, altid) == true)
				then
				tableDeviceNumByAltidAndType[key] = {k, true}
				debug("findAssociation succeeded->deviceNum: "..k)
				return k
			end
		end
	end
	debug("findChild failed for altid: "..altid)
	tableDeviceNumByAltidAndType[key] = {0, false}
	return nil
end

local function findChildren(parentDevice, deviceType)

	local children = {}

	for _, v in pairs(luup.devices)
		do
		if (v.device_num_parent == parentDevice and v.device_type == deviceType)
			then
			children[#children+1] = v.id
		end
	end
	return children

end

-- Function to send a message to RFXtrx
local function sendCommand(packetType, packetSubType, packetData, tableCmds)

	if (tableCmds and #tableCmds > 0)
		then
		table.insert(tableMsgSent, { sequenceNum, tableCmds })
	end

	local cmd = string.char(string.len(packetData) + 3, packetType, packetSubType, sequenceNum)..packetData

	debug("Sending command: "..formattohex(cmd))

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
			disabledDevices = disabledDevices..","..id
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

-- Extract the signal strength from the data string sent by the device
-- byte1 is the location of the byte containing the battery level in the data string
-- Signal strength is always the upper 4 bits of the byte
local function decodeSignalStrength( dataString, byte1 )
	-- it's always the upper 4 bits
	local strength = bitw.rshift(string.byte(dataString, byte1), 4)
	return strength
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
			debug("Dubious temperature reading: "..temp.."C".." altid="..altid)
		end
		else if (temp > 65.56)
			then
			debug("Dubious temperature reading: "..temp.."C".." altid="..altid)
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
	debug("Resetting rain data from "..first.." to "..last.." in "..#rainTable)
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
	debug("Resetting rain table "..#rainTable)
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
		if(#rainTable ~= size) then
			resetRainTable(rainTable, size)
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
	if (deviceNum)
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
	if (deviceNum)
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
	local restartNeeded = false

	-- Check all devices if they are children. If so, register in
	-- the correct array based on the device type
	for k, v in pairs(luup.devices)
		do
		local altIdPrefix = string.match(v.id, '/([^/]+)/')
		-- Look for devices with this device as parent
		if (v.device_num_parent == lul_device)
			then
			debug( "Found child device id "..tostring(v.id).." of type "..tostring(v.device_type))
			nbr = nbr + 1

			local key = searchInKeyTable(tableDeviceTypes, tostring(v.device_type), string.sub(v.id, 1, 3))
			if (key)
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
		if (altIdPrefix and tableDevice2Json[altIdPrefix]) then
			local requiredJSONFile = tableDevice2Json[altIdPrefix]
			local currentJSONFile = luup.attr_get("device_json", k)
			if (currentJSONFile ~= requiredJSONFile) then
				debug("Setting JSON file for device "..v.id.." to "..requiredJSONFile)
				restartNeeded = true
				luup.attr_set("device_json", requiredJSONFile, k)
			end
		end
	end
	if (restartNeeded) then
		luup.reload()
	end
	setVariable(lul_device, tabVars.VAR_NBR_DEVICES, nbr)

	logDevices()

end

local function addParameter(paramString, variable, value)
	if not (paramString or variable or value) then
		warning("a nil passed to addParameter")
		return
	end
	if (paramString ~= "")
		then
		paramString = paramString.."\n"
	end
	paramString = paramString..variable.serviceId..","..variable.name.."="..(value or "")
	return paramString
end

local function addParameters(paramString, paramTable)
	if not (paramString or paramTable) then
		warning("a nil passed to addParameters")
		return
	end
	if (type(paramTable) ~= "table") then
		warning("paramTable passed to addParameters is not a table")
		return
	end
	for _, v in pairs(paramTable) do
		paramString = addParameter(paramString, v.variable, v.value)
	end
	return paramString
end

local function updateManagedDevices(tableNewDevices, tableConversions, tableDeletedDevices)

	if ((tableNewDevices and (#tableNewDevices > 0) )
		or ( tableConversions and (#tableConversions > 0) )
		or ( tableDeletedDevices and (#tableDeletedDevices > 0) ))
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

			if (tableDeletedDevices and (#tableDeletedDevices > 0))
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
			local altId = nil
			local devType = nil

			if (tableConversions and (#tableConversions > 0))
				then
				for _, v2 in ipairs(tableConversions)
					do
					if ((subId == v2[3]) or (findStrInStringList(associations, v2[3]) == true))
						then
						name = v2[1]
						room = v2[2]
						altId = v2[3]
						devType = v2[4]
						break
					end
				end
			end

			if (altId and devType)
				then
				debug("Converting "..name.."...")

				local newDeviceType = tableDeviceTypes[devType]

				if (newDeviceType ~= existingDevice)
					then
					local parameters = ""
					if (newDeviceType.hasAssociation) then
						parameters = addParameter(parameters, tabVars.VAR_ASSOCIATION, "")
						if (associations)
							then
							parameters = parameters..associations
							else
							parameters = parameters..""
						end
					end
					if (newDeviceType.parameters) then
						parameters = addParameters(parameters, newDeviceType.parameters)
					end
					luup.chdev.append(THIS_DEVICE, child_devices, newDeviceType.prefix..subId, name,
					newDeviceType.deviceType, newDeviceType.deviceFile, "", parameters, false)
					tableDevices[i] = { newDeviceType.prefix..subId, devType, associations, name }
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
		-- Synch the new tree with the old tree
		debug("Start sync")
		luup.chdev.sync(THIS_DEVICE, child_devices)
		debug("End sync")

		------------------------------------------------------------------------------------
		-- Now add the new device(s) to the tree
		------------------------------------------------------------------------------------

		if (tableNewDevices and (#tableNewDevices > 0))
			then
			for _, device in ipairs(tableNewDevices)
				do
				local name = device[1]
				local room = device[2]
				local altId = device[3]
				local devType = device[4]
				local newDevice = tableDeviceTypes[devType]
				local newDevId
				debug("new device->name: "..(name or 'nil').." room: "..(room or 'nil').." altId: "..(altId or 'nil').." device type: "..(devType or 'nil'))
				if not(newDevice) then
					warning("updateManagedDevices: no device found for device type "..(devType or 'nil'))
				else
					name = name or (newDevice.name..altId)
					debug("Creating child device id "..newDevice.prefix..altId.." of type "..newDevice.deviceType)
					local parameters = ""
					if (newDevice.hasAssociation) then
						parameters = addParameter(parameters, tabVars.VAR_ASSOCIATION, "")
					end
					if (newDevice.hasMode) then
						parameters = addParameter(parameters, tabVars.VAR_RFY_MODE, "STANDARD")
					end
					if (newDevice.parameters) then
						parameters = addParameters(parameters, newDevice.parameters)
					end
					newDevId = luup.create_device("", newDevice.prefix..altId, name, newDevice.deviceFile, "", "", "",
						false, false, THIS_DEVICE, 0, 0, parameters, 0, "", "", true, false)
					debug("New device ID: "..(newDevId or 'nil'))
--					luup.chdev.append(THIS_DEVICE, child_devices, newDevice.prefix..altId, name,
--						newDevice.deviceType, newDevice.deviceFile, "", parameters, false)
					table.insert(tableDevices, { newDevice.prefix..altId, devType, nil, name })
				end
			end
		end

		logDevices()
		-- Synch the new tree with the old tree
--		debug("Start sync")
--		luup.chdev.sync(THIS_DEVICE, child_devices)
--		debug("End sync")

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
			and (cmdDeviceType)
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
				if (dev)
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
				and (isDisabledDevice(tableDeviceTypes[cmdDeviceType].prefix..altID) == false))
				then
				table.insert(tableNewDevices, { nil, nil, altID, cmdDeviceType })
				debug("New device: altID: "..altID.." deviceType: "..cmdDeviceType)
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
		--logCmds("delayed cmds "..delay.."s", tableDelayedCmds)
		luup.call_delay("handleDelayedCmds", delay, encodeCommandsInString(tableDelayedCmds))
	end

	-- Exit if there are no immediate commands
	if (tableImmediateCmds == nil or #tableImmediateCmds == 0)
		then
		return
	end

	------------------------------------------------------------------------------
	-- Deliver commands to devices - actually just set a device variable
	--  TODO: This whole section needs review. The variable and value should be
	--  determined by the code processing the message or UI command.
	------------------------------------------------------------------------------
	for deviceNum, luupDevice in pairs(luup.devices) do
		-- Check if we have a device with the correct parent (THIS_DEVICE)
		if (luupDevice.device_num_parent == THIS_DEVICE)
			then
--			debug("Device Number: "..deviceNum..
--					 " luupDevice.device_type: "..tostring(luupDevice.device_type)..
--					 " luupDevice.device_num_parent: "..tostring(luupDevice.device_num_parent)..
--					 " luupDevice.id: "..tostring(luupDevice.id)
--			)
			for _, v2 in ipairs(tableImmediateCmds)
				do
				altID = v2.altid
				cmd = v2.cmd
				value = v2.value
				if ((#altID > 0)
					and ((string.find(luupDevice.id, altID.."$", 4) == 4)
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
					if (cmd.deviceType)
						then
						cmdDeviceType = tableDeviceTypes[cmd.deviceType]
					end
					if (cmd.variable)
						then
						variable = tabVars[cmd.variable]
					end
					if ((cmdDeviceType == nil or luupDevice.device_type == cmdDeviceType.deviceType) and variable and value ~= nil)
						then
						if (cmdDeviceType and cmdDeviceType.hasAdjustments and variable.isAdjustable)
							then
							value = tonumber(value)
							local adjust = getVariable(deviceNum, tabVars.VAR_ADJUST_CONSTANT2)
							if (adjust and adjust ~= "")
								then
								value = value + tonumber(adjust)
							end
							adjust = getVariable(deviceNum, tabVars.VAR_ADJUST_MULTIPLIER)
							if (adjust and adjust ~= "")
								then
								value = value * tonumber(adjust)
							end
							adjust = getVariable(deviceNum, tabVars.VAR_ADJUST_CONSTANT)
							if (adjust and adjust ~= "")
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
								and last and (os.time() - last) >= 25)
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
	--debug("Msg select key: "..key)
	local seqNum = string.byte(message, 4)
	local data = getStringPart(message, 5, #message)
	local msgType = tableMsgByKey[key]
	if (msgType) then
		local decodeMsgFunction = msgType.decodeMsgFunction
		-- If there is a method to decode this message
		if(decodeMsgFunction) then
	--		debug("Msg decoded: "..tableMsgTypes[tableMsgByKey[key]].key)
			tableCmds = decodeMsgFunction(tableMsgByKey[key].subType, data, seqNum)
			actOnCommands(tableCmds)
			return
		end
	end
	warning("No decode method for message: "..formattohex(message))
end

local function decodeResponse(subType, data, seqNum)

	local tableCmds = {}

	if (subType == tableMsgTypes.TRANSMITTER_RESPONSE.subType)
		then
		debug("Response to a command")
		local idx = searchInTable(tableMsgSent, 1, seqNum)
		if (idx > 0)
			then
			debug("Found sent command "..seqNum.." at index "..idx)
			local msg = string.byte(data, 1)
			if (msg == 0x0 or msg == 0x1)
				then
				debug("Transmitter response "..msg.." ACK")
				tableCmds = tableMsgSent[idx][2]
			elseif (msg == 0x2 or msg == 0x3) then
				error("Transmitter response "..msg.." NAK for message number "..seqNum)
			else
				error("Transmitter response "..msg.." ??? for message number "..seqNum)
			end
			table.remove(tableMsgSent, idx)
		else
			error("Transmitter response for an unexpected message number "..seqNum)
		end
	end

	return tableCmds

end

local function decodeResponseMode(subType, data)
	local tableCmds = {}

	if (subType == tableMsgTypes.RESPONSE_MODE_COMMAND.subType)
		then
		log("Plugin version: "..PLUGIN_VERSION)
		setVariable(THIS_DEVICE, tabVars.VAR_PLUGIN_VERSION, PLUGIN_VERSION)
		local cmd = string.byte(data, 1)
		-- if result of Get Status or Set Mode commands
		if (cmd == 0x2 or cmd == 0x3)
			then
			debug("Response to a Get Status command or Set Mode command")
			typeRFX = string.byte(data, 2)
			local hdwType = tableHardwareType[typeRFX]
			if(hdwType == nil) then
				hdwType = "Unknown"
			end
			log("Hardware type: "..hdwType)
			luup.attr_set("model", hdwType, THIS_DEVICE, 0)

			-- Add 1000 to the byte indicating the firmware version
			--  so that the displayed version matches that of the firmware version
			firmware = 1000 + string.byte(data, 3)
			log("Firmware version: "..firmware)
			setVariable(THIS_DEVICE, tabVars.VAR_FIRMWARE_VERSION, firmware)

			-- Get the firmware type
			local typeFirmware = string.byte(data, 11)
			firmtype = tableFirmwareType[typeFirmware + 1]
			if(firmtype == nil) then
				firmtype = "Unknown"
			end
			log("Firmware type: "..firmtype)
			setVariable(THIS_DEVICE, tabVars.VAR_FIRMWARE_TYPE, firmtype)
			-- Get the hardware version ;
			--  the major and minor versions
			hardware = string.byte(data, 8).."."..string.byte(data, 9)
			log("Hardware version: "..hardware)
			setVariable(THIS_DEVICE, tabVars.VAR_HARDWARE_VERSION, hardware)

			log("Output power: "..string.byte(data, 10))

			local noise = string.byte(data, 12)
			log("Receiver noise level: "..noise)
			setVariable(THIS_DEVICE, tabVars.VAR_NOISE, noise)

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
				log("   - Legrand CAD")
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
			isEnabled = (bitw.band(msg6, 0x80) == 0x80)
			setVariable(THIS_DEVICE, tabVars.VAR_FUNKBUS_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - Funkbus")
			end
			isEnabled = (bitw.band(msg6, 0x40) == 0x40)
			setVariable(THIS_DEVICE, tabVars.VAR_MCZ_RECEIVING, isEnabled)
			if(isEnabled)
				then
				log("   - MCZ")
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
			error("Response to an unexpected mode command: "..cmd)
		end
	elseif (subType == tableMsgTypes.UNKNOWN_RTS_REMOTE.subType)
		then
		warning("Unknown RTS remote")
		--tableCmds = { { "", "", nil, 0 } }
	elseif (subType == tableMsgTypes.INVALID_COMMAND.subType)
		then
		warning("Invalid command received")
		--tableCmds = { { "", "", nil, 0 } }
	else
		error("Unexpected subtype for response on a command: "..subType)
	end

	return tableCmds

end

local function decodeLighting1(subType, data)

	local altid2 = string.format("L1.%X/%s", subType, string.sub(data, 1, 1))
	local altid = altid2..string.format("%02d", string.byte(data, 2))

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
		warning("Lighting1 unexpected command: "..cmdCode)
	end

	return tableCmds

end

local function decodeLighting2(subType, data)

	local altid2 = "L2."..subType.."/"
	..string.format("%X", bitw.band(string.byte(data, 1), 0x03))
	..string.format("%02X", string.byte(data, 2))
	..string.format("%02X", string.byte(data, 3))
	..string.format("%02X", string.byte(data, 4))
	local altid = altid2.."/"..string.format("%02d", string.byte(data, 5))

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
		warning("Lighting2 unexpected command: "..cmdCode)
	end

	return tableCmds

end

local function decodeLighting3(subType, data)

	local ids = {}
	local altid = "L3."..subType.."/"
	..string.format("%X", bitw.band(string.byte(data, 1), 0x0F))
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
	--debug("Koppla message received with command code: "..cmdCode)
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
		warning("Lighting3 command not yet implemented: "..cmdCode)
	end

	if (ids and #ids > 0)
		then
		for _, id in ipairs(ids)
			do
			if (cmd)
				then
				table.insert(tableCmds, DeviceCmd( altid..string.format("%02d", id), cmd, cmdValue, 0 ) )
			end
		end
	end

	return tableCmds

end

local function decodeLighting5(subType, data)

	local altid2 = "L5."..subType.."/"
	..string.format("%02X", string.byte(data, 1))
	..string.format("%02X", string.byte(data, 2))
	..string.format("%02X", string.byte(data, 3))
	local altid = altid2.."/"..string.format("%02d", string.byte(data, 4))

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
		warning("Lighting5 unexpected command: "..cmdCode)
	end

	return tableCmds

end

local function decodeLighting6(subType, data)

	local altid2 = "L6."..subType.."/"
	..string.format("%02X", string.byte(data, 1))
	..string.format("%02X", string.byte(data, 2))
	.."/"..string.sub(data, 3, 3)
	local altid = altid2..string.byte(data, 4)

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
		warning("Lighting6 unexpected command: "..cmdCode)
	end

	return tableCmds

end

local function decodeCurtain(subType, data)

	local altid = "C"..subType.."/"	..string.sub(data, 1, 1)..string.format("%02d", string.byte(data, 2))
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
		warning("Curtain command not yet implemented: "..cmdCode)
	end
	if (cmd)
		then
		table.insert(tableCmds, DeviceCmd( altid, cmd, nil, 0 ) )
	end

	return tableCmds

end

local function decodeBlind(subType, data)

	local altid = "B"..subType.."/"
	..string.format("%02X", string.byte(data, 1))
	..string.format("%02X", string.byte(data, 2))
	..string.format("%02X", string.byte(data, 3))
	if (subType == tableMsgTypes.BLIND_T6.subType or subType == tableMsgTypes.BLIND_T7.subType)
		then
		altid = altid..string.format("%X", bitw.rshift(string.byte(data, 4), 4))
	end
	altid = altid.."/"..string.format("%02d", bitw.band(string.byte(data, 4), 0x0F))

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
		warning("Blind command not yet implemented: "..cmdCode)
	end
	if (cmd)
		then
		table.insert(tableCmds, DeviceCmd( altid, cmd, nil, 0 ) )
	end

	return tableCmds

end

local function decodeThermostat3(subType, data)

	local altid = "HT3."..subType.."/"
	..string.format("%02X", string.byte(data, 1))
	..string.format("%02X", string.byte(data, 2))
	..string.format("%02X", string.byte(data, 3))

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
		warning("Thermostat3 command not yet implemented: "..cmdCode)
	end

	return tableCmds

end

local function decodeTemp(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "T"..subType.."/"..id

	local tableCmds = {}
	local temp = decodeTemperature( altid, data, 3 )
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_TEMP, temp, 0 ) )

	-- Update if necessary the max and min temperatures detected by this device
	checkMaxMinTemp( altid, tableCmds, temp )

	local strength = decodeSignalStrength(data, 5)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	local battery = decodeBatteryLevel(data, 5)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeHum(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "H"..subType.."/"..id

	local tableCmds = {}

	local hum = string.byte(data, 3)
	-- Ignore humidity greater than 100 - must be an error
	if(hum < 100)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_HUM, hum, 0 ) )

		-- Update if necessary the max and min humidity detected by this device
		checkMaxMinHum( altid, tableCmds, hum )
	else
		debug("Dubious humidity reading: "..hum.."%".." altid="..altid.." status=")
	end

	local strength = decodeSignalStrength(data, 5)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	local battery = decodeBatteryLevel(data, 5)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeTempHum(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "TH"..subType.."/"..id

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
		debug("Dubious humidity reading: "..hum.." altid="..altid.." status=")
	end

	local strength = decodeSignalStrength(data, 7)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	local battery = decodeBatteryLevel(data, 7)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeBaro(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "B"..subType.."/"..id

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
	if (strForecast)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_FORECAST, strForecast, 0 ) )
	end

	local strength = decodeSignalStrength(data, 6)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	local battery = decodeBatteryLevel(data, 6)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeTempHumBaro(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "THB"..subType.."/"..id

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
		debug("Dubious humidity reading: "..hum.." altid="..altid.." status=")
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
	if (strForecast)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_FORECAST, strForecast, 0 ) )
	end

	local strength = decodeSignalStrength(data, 10)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	local battery = decodeBatteryLevel(data, 10)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeRain(subType, data)
	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "R"..subType.."/"..id

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
	-- If this is not a LaCrosse rain sensor
	if (subType ~= tableMsgTypes.RAIN6.subType)
		then
		rainReading = (string.byte(data, 5) * 65536 + string.byte(data, 6) * 256 + string.byte(data, 7)) / 10
	else
		rainReading = string.byte(data, 7)
	end
	debug("rainReading: "..rainReading)
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
		if(previousRain) then
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
			else -- If the new reading is less than the old, assume the sensor has been reset
				if(rainDiff < 0) then
					rainDiff = 0.0
					rainReading = 0
					table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAIN, rainReading, 0 ) )
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
			--				debug("previous time: "..previousTime["year"].." "..previousTime["yday"].." "..previousWeek.." "..previousTime["month"].." "..previousTime["day"].." "..previousTime["hour"].." "..previousTime["min"].." "..previousTime["sec"].." "..previousTime["wday"])
			--				debug("current time:  "..currentTime["year"].." "..currentTime["yday"].." "..currentWeek.." "..currentTime["month"].." "..currentTime["day"].." "..currentTime["hour"].." "..currentTime["min"].." "..currentTime["sec"].." "..currentTime["wday"])
			--				debug("Rain this minute: "..currentTime["min"].." "..rainByMinute[currentTime["min"]+1])
			--				debug("Rain by Minute: "..recursiveConcat(rainByMinute))
			--				debug("Rain this hour: "..currentTime["hour"].." "..rainByHour[currentTime["hour"]+1])
			--				debug("Rain by Hour: "..recursiveConcat(rainByHour))
			--				debug("Rain this day: "..currentTime["wday"].." "..rainByWkDay[currentTime["wday"]])
			--				debug("Rain by Day: "..recursiveConcat(rainByWkDay))
			--				debug("Rain this week: "..currentWeek.." "..rainByWeek[currentWeek])
			--				debug("Rain by Week: "..recursiveConcat(rainByWeek))
			--				debug("Rain this month: "..currentTime["month"].." "..rainByMonth[currentTime["month"]])
			--				debug("Rain by Month: "..recursiveConcat(rainByMonth))
			--			end

			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAINBYMONTH, recursiveConcat(rainByMonth), 0 ) )
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAINBYWEEK, recursiveConcat(rainByWeek), 0 ) )
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAINBYDAY, recursiveConcat(rainByWkDay), 0 ) )
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAINBYHOUR, recursiveConcat(rainByHour), 0 ) )
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAINBYMINUTE, recursiveConcat(rainByMinute), 0 ) )
			local rate = nil
			local calculatedRate = 0.0
			-- Calculate the rain rate based on the last two readings in case the sensor doesn't provide it
			local elapsedSeconds = currentSeconds - previousSeconds
			if(elapsedSeconds > 0)
				then
				local periodsPerHour = 3600 / elapsedSeconds
				calculatedRate = periodsPerHour * rainDiff
				debug("Calculated rain rate: "..calculatedRate.." mm/hr")
			end
			if (subType == tableMsgTypes.RAIN1.subType)
				then
				rate = string.byte(data, 3) * 256 + string.byte(data, 4)
			elseif (subType == tableMsgTypes.RAIN2.subType)
				then
				rate = (string.byte(data, 3) * 256 + string.byte(data, 4)) / 100
			end
			if (rate)
				then
				debug("rain rate from the sensor: "..rate.." mm/hr")
				table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAINRATE, rate, 0 ) )
			else
				-- use the calculated rate
				table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAINRATE, calculatedRate, 0 ) )
			end
		end
	end

	local strength = decodeSignalStrength(data, 8)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	local battery = decodeBatteryLevel(data, 8)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeTempRain(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "TR"..subType.."/"..id

	local tableCmds = {}

	local temp = decodeTemperature( altid, data, 3 )
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_TEMP, temp, 0 ) )

	-- Update if necessary the max and min temperatures detected by this device
	checkMaxMinTemp( altid, tableCmds, temp )

	local total = (string.byte(data, 5) * 256 + string.byte(data, 6)) / 10
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_RAIN, total, 0 ) )

	local strength = decodeSignalStrength(data, 7)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	local battery = decodeBatteryLevel(data, 7)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeWind(subType, data)

	local unitKmh = (getVariable(THIS_DEVICE, tabVars.VAR_SPEED_UNIT))

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "W"..subType.."/"..id

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

	local strength = decodeSignalStrength(data, 13)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	local battery = decodeBatteryLevel(data, 13)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeUV(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "U"..subType.."/"..id

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

	local strength = decodeSignalStrength(data, 6)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )

	local battery = decodeBatteryLevel(data, 6)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeWeight(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local altid = "WT"..subType.."/"..id

	local tableCmds = {}

	local weight = (string.byte(data, 3) * 256 + string.byte(data, 4)) / 10
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_WEIGHT, weight, 0 ) )

	local impedance = nil

	-- Impedance is not supported by the current RFXtrx firmware (v50)

	if (impedance ~= nil)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_IMPEDANCE, impedance, 0 ) )
	end

	-- local strength = decodeSignalStrength(data, 5)

	local battery = decodeBatteryLevel(data, 5)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

-- This function is for door sensors that only transmit when tripped
--  they do not transmit when the door is again closed.
local function decodeSecurity(subType, data)

	-- For a PT2262 type device the first 20 bits are fixed
	-- the last 4 bits could be a status
	local altid = "D/"..string.format("%02X", string.byte(data, 1))
	..string.format("%02X", string.byte(data, 2))
	..string.format("%1X", bitw.rshift(string.byte(data, 3), 4))
	--	..string.format("%02X", string.byte(data, 3))

	local tableCmds = {}
	-- Since many devices only transmit 'door opened', default the command value to 1
	local cmdValue = 1
	local cmd = tableCommandTypes.CMD_DOOR
	local cmdCode = bitw.band(string.byte(data, 3), 0x0F)

	debug("decodeSecurity: "..subType.." altid="..altid.." status="..string.format("%02X", cmdCode))

	table.insert(tableCmds, DeviceCmd( altid, cmd, cmdValue, 0 ) )

	local strength = decodeSignalStrength(data, 6)
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
	if(deviceNum and (tampered ~= nil)) then
		-- Get current state of tampered
		local wasTampered = getVariable(deviceNum, tabVars.VAR_TAMPERED)
		-- Get current state of armed
		local armed = getVariable(deviceNum, tabVars.VAR_ARMED)
		debug("handleTamper - armed: "..(armed or 'nil').." wasTampered: "..(wasTampered or 'nil').." tamperedNow: "..(tampered or 'nil'))
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
		elseif(wasTampered and (wasTampered == 1) and (tampered == 0)) then
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

	local altid = "M/"..string.format("%02X", string.byte(data, 1))
	..string.format("%02X", string.byte(data, 2))
	..string.format("%02X", string.byte(data, 3))

	debug("decodeSecurityMS: "..subType.." altid="..altid.." status="..string.byte(data, 4))

	local tableCmds = {}
	local cmd = nil
	local cmdValue = nil
	local cmdCode = bitw.band(string.byte(data, 4), 0x7F)
	--local tampered = (bitw.band(string.byte(data, 4), 0x80))/128

	if (cmdCode == 0x04)
		then
		cmd = tableCommandTypes.CMD_MOTION
		cmdValue = "1"
	elseif (cmdCode == 0x05)
		then
		cmd = tableCommandTypes.CMD_MOTION
		cmdValue = "0"
	else
		if (cmdCode)
			then
			warning("decodeSecurityMS command not yet implemented: "..cmdCode.."hex="..formattohex(cmdCode))
		else
			warning("decodeSecurityMS command not yet implemented")
		end
	end
	if (cmd)
		then
		table.insert(tableCmds, DeviceCmd( altid, cmd, cmdValue, 0 ) )
		--tableCmds = handleTamperSwitch(altid, tableDeviceTypes.MOTION.deviceType, tampered, tableCmds)
	end

	local strength = decodeSignalStrength(data, 5)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )
	local battery = decodeBatteryLevel(data, 5)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeSecurityDS(subType, data)

	local altid = "D/"..string.format("%02X", string.byte(data, 1))
	..string.format("%02X", string.byte(data, 2))
	..string.format("%02X", string.byte(data, 3))

	debug("decodeSecurityDS: "..subType.." altid="..altid.." status="..string.byte(data, 4))

	local tableCmds = {}
	local cmd = nil
	local cmdValue = nil
	local cmdCode = bitw.band(string.byte(data, 4), 0x7F)
	--local tampered = (bitw.band(string.byte(data, 4), 0x80))/128
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
			if (cmdCode)
				then
				warning("decodeSecurityDS command not yet implemented: "..cmdCode.." hex: "..formattohex(cmdCode))
			else
				warning("decodeSecurityDS command not yet implemented")
			end
		end
		if (cmd)
			then
			table.insert(tableCmds, DeviceCmd( altid, cmd, cmdValue, 0 ) )
			--tableCmds = handleTamperSwitch(altid, tableDeviceTypes.DOOR.deviceType, tampered, tableCmds)
		end

		local strength = decodeSignalStrength(data, 5)
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )
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
		altid = "X10/SR/"..string.format("%02X", string.byte(data, 1))
		..string.format("%02X", string.byte(data, 2))
		..string.format("%02X", string.byte(data, 3))

		local deviceNum = findChild(THIS_DEVICE, altid, tableDeviceTypes.ALARM.deviceType)
		if (deviceNum)
			then
			exitDelay = tonumber(getVariable(deviceNum, tabVars.VAR_EXIT_DELAY) or "0")
		end
	elseif (subType == tableMsgTypes.SECURITY_MEISR.subType)
		then
		altid = "MEI/SR/"..string.format("%02X", string.byte(data, 1))
		..string.format("%02X", string.byte(data, 2))
		..string.format("%02X", string.byte(data, 3))
	elseif (subType == tableMsgTypes.KD101.subType)
		then
		altid = "KD1/SR/"..string.format("%02X", string.byte(data, 1))
		..string.format("%02X", string.byte(data, 2))
		..string.format("%02X", string.byte(data, 3))

		battery = -1
	elseif (subType == tableMsgTypes.SA30.subType)
		then
		altid = "S30/SR/"..string.format("%02X", string.byte(data, 1))
		..string.format("%02X", string.byte(data, 2))
		..string.format("%02X", string.byte(data, 3))

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
				altid = "KD1/SS/"..string.format("%02X", string.byte(data, 1))
				..string.format("%02X", string.byte(data, 2))
				..string.format("%02X", string.byte(data, 3))
			else
				altid = "S30/SS/"..string.format("%02X", string.byte(data, 1))
				..string.format("%02X", string.byte(data, 2))
				..string.format("%02X", string.byte(data, 3))
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
				altid = "KD1/SS/"..string.format("%02X", string.byte(data, 1))
				..string.format("%02X", string.byte(data, 2))
				..string.format("%02X", string.byte(data, 3))
			else
				altid = "S30/SS/"..string.format("%02X", string.byte(data, 1))
				..string.format("%02X", string.byte(data, 2))
				..string.format("%02X", string.byte(data, 3))
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
		altid = "X10/L1/"..string.format("%02X", string.byte(data, 1))
		..string.format("%02X", string.byte(data, 2))
		..string.format("%02X", string.byte(data, 3))
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_OFF, nil, 0 ) )
	elseif (cmd == 0x11)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ALARM_SCENE_ON, 1, 0 ) )
		if (battery >= 0 and battery <= 100)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )
		end
		altid = "X10/L1/"..string.format("%02X", string.byte(data, 1))
		..string.format("%02X", string.byte(data, 2))
		..string.format("%02X", string.byte(data, 3))
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ON, nil, 0 ) )
	elseif (cmd == 0x12)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ALARM_SCENE_OFF, 2, 0 ) )
		if (battery >= 0 and battery <= 100)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )
		end
		altid = "X10/L2/"..string.format("%02X", string.byte(data, 1))
		..string.format("%02X", string.byte(data, 2))
		..string.format("%02X", string.byte(data, 3))
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_OFF, nil, 0 ) )
	elseif (cmd == 0x13)
		then
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ALARM_SCENE_ON, 2, 0 ) )
		if (battery >= 0 and battery <= 100)
			then
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )
		end
		altid = "X10/L2/"..string.format("%02X", string.byte(data, 1))
		..string.format("%02X", string.byte(data, 2))
		..string.format("%02X", string.byte(data, 3))
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
				altid = "KD1/SS/"..string.format("%02X", string.byte(data, 1))
				..string.format("%02X", string.byte(data, 2))
				..string.format("%02X", string.byte(data, 3))
			else
				altid = "S30/SS/"..string.format("%02X", string.byte(data, 1))
				..string.format("%02X", string.byte(data, 2))
				..string.format("%02X", string.byte(data, 3))
			end
			table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_SMOKE, "0", 0 ) )
		end
	else
		warning("x10securityRemote command not yet implemented: "..cmd.."hex="..formattohex(cmd))
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

	local altid = "RC"..subType.."/"..string.format("%02X", string.byte(data, 1))
	local cmd = string.byte(data, 2)
	local tableCmds = {}
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_ATI_SCENE_ON, cmd, 0 ) )

	return tableCmds

end

local function decodeElec1(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local num = tonumber(subType)
	local altid = "ELEC"..num.."/"..id
	local altid1 = "ELEC"..num.."/"..id.."/1"
	local altid2 = "ELEC"..num.."/"..id.."/2"
	local altid3 = "ELEC"..num.."/"..id.."/3"
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

	-- local strength = decodeSignalStrength(data, 10)

	local battery = decodeBatteryLevel(data, 10)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeElec2Elec3(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local num = tonumber(subType) + 1
	local altid = "ELEC"..num.."/"..id

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

	-- local strength = decodeSignalStrength(data, 14)

	local battery = decodeBatteryLevel(data, 14)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeElec4(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local num = tonumber(subType) + 3
	local altid = "ELEC"..num.."/"..id
	local altid1 = "ELEC"..num.."/"..id.."/1"
	local altid2 = "ELEC"..num.."/"..id.."/2"
	local altid3 = "ELEC"..num.."/"..id.."/3"
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

	-- local strength = decodeSignalStrength(data, 16)

	local battery = decodeBatteryLevel(data, 16)
	table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_BATTERY, battery, 0 ) )

	return tableCmds

end

local function decodeRFXSensor(subType, data)

	local id = string.byte(data, 1)
	local altid = "RFXSENSOR"..subType.."/"..id
	local tableCmds = {}

	if (subType == tableMsgTypes.RFXSENSOR_T.subType)
		then
		local temp = decodeTemperature( altid, data, 2 )
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_TEMP, temp, 0 ) )
		-- Update if necessary the max and min temperatures detected by this device
		checkMaxMinTemp( altid, tableCmds, temp )
		local strength = decodeSignalStrength(data, 4)
		table.insert(tableCmds, DeviceCmd( altid, tableCommandTypes.CMD_STRENGTH, strength, 0 ) )
	else
		warning("RFXSensor subtype not yet implemented: "..subType)
	end

	return tableCmds

end

local function decodeRFXMeter(subType, data)

	local id = string.byte(data, 1) * 256 + string.byte(data, 2)
	local num = tonumber(subType) + 1
	local altid = "RFXMETER"..num.."/"..id
	local instant = 0.1
	local waarde = 0
	local multiplier = 1
	local tableCmds = {}

	local deviceNum = findChild(THIS_DEVICE, altid, tableDeviceTypes.RFXMETER.deviceType)
	if (deviceNum)
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

local function decodeFan(subType, data)
	local subTypeTblSelect = {
		tableCmdCodes2Commands.FaCmdCode2Command,	-- subtype 0
		tableCmdCodes2Commands.FhCmdCode2Command,	-- subtype 1
		tableCmdCodes2Commands.FbCmdCode2Command,	--   .
		tableCmdCodes2Commands.FeCmdCode2Command,	--   .
		tableCmdCodes2Commands.FbCmdCode2Command,	--   .
		tableCmdCodes2Commands.FcCmdCode2Command,	-- subtype 5
		tableCmdCodes2Commands.FbCmdCode2Command,
		tableCmdCodes2Commands.FfCmdCode2Command,
		tableCmdCodes2Commands.FdCmdCode2Command,
		tableCmdCodes2Commands.FgCmdCode2Command
	}
	local altid = "FN/F"..subType.."/"
	..string.format("%02X", string.byte(data, 1))
	..string.format("%02X", string.byte(data, 2))
	..string.format("%02X", string.byte(data, 3))

	local tableCmds = {}
	local cmdCode = string.byte(data, 4)
	local thisCmdAction = subTypeTblSelect[subType+1][cmdCode]
	local action = thisCmdAction.action
	local cmd = thisCmdAction.cmd
	local value
	debug("decodeFan->altid: "..altid.."subType: "..subType.." cmdCode: "..cmdCode.." action: "..(action or 'nil').." cmd: "..(cmd.Name or 'nil'))
	local deviceNum = findChild(THIS_DEVICE, altid, tableDeviceTypes.FAN.deviceType)
	if (action and cmd and deviceNum) then
		if (cmd == tableCommandTypes.CMD_FANLIGHT) then
			if (action == 'LightOn') then
				value = 1
			elseif (action == 'LightOff') then
				value = 0
			else
				local curStat = getVariable(deviceNum, tabVars.VAR_STATE) or "0"
				if (curStat == "0") then
					value = "1"
				else
					value = "0"
				end
			end
		elseif (cmd == tableCommandTypes.CMD_REVERSE) then
			local curStat = getVariable(deviceNum, tabVars.VAR_REVERSE) or "0"
			if (curStat == "0") then
				value = "1"
			else
				value = "0"
			end
		else
			value = action
		end
		table.insert(tableCmds, DeviceCmd( string.sub(altid, 4), cmd, value, 0 ))
	else
		warning("decodeFan undecoded message")
	end

	return tableCmds

end

local function initDecodingFunctions()

	tableMsgTypes.RESPONSE_MODE_COMMAND.decodeMsgFunction = decodeResponseMode
	tableMsgTypes.UNKNOWN_RTS_REMOTE.decodeMsgFunction = decodeResponseMode
	tableMsgTypes.INVALID_COMMAND.decodeMsgFunction = decodeResponseMode
	tableMsgTypes.RECEIVER_LOCK_ERROR.decodeMsgFunction = decodeResponse
	tableMsgTypes.TRANSMITTER_RESPONSE.decodeMsgFunction = decodeResponse
	tableMsgTypes.LIGHTING_X10.decodeMsgFunction = decodeLighting1
	tableMsgTypes.LIGHTING_ARC.decodeMsgFunction = decodeLighting1
	tableMsgTypes.LIGHTING_AB400D.decodeMsgFunction = decodeLighting1
	tableMsgTypes.LIGHTING_WAVEMAN.decodeMsgFunction = decodeLighting1
	tableMsgTypes.LIGHTING_EMW200.decodeMsgFunction = decodeLighting1
	tableMsgTypes.LIGHTING_IMPULS.decodeMsgFunction = decodeLighting1
	tableMsgTypes.LIGHTING_RISINGSUN.decodeMsgFunction = decodeLighting1
	tableMsgTypes.LIGHTING_PHILIPS.decodeMsgFunction = decodeLighting1
	tableMsgTypes.LIGHTING_ENERGENIE_ENER010.decodeMsgFunction = decodeLighting1
	tableMsgTypes.LIGHTING_ENERGENIE_5GANG.decodeMsgFunction = decodeLighting1
	tableMsgTypes.LIGHTING_COCO.decodeMsgFunction = decodeLighting1
	tableMsgTypes.LIGHTING_AC.decodeMsgFunction = decodeLighting2
	tableMsgTypes.LIGHTING_HEU.decodeMsgFunction = decodeLighting2
	tableMsgTypes.LIGHTING_ANSLUT.decodeMsgFunction = decodeLighting2
	tableMsgTypes.LIGHTING_KOPPLA.decodeMsgFunction = decodeLighting3
	tableMsgTypes.SECURITY_DOOR.decodeMsgFunction = decodeSecurity
	tableMsgTypes.LIGHTING_LIGHTWARERF.decodeMsgFunction = decodeLighting5
	tableMsgTypes.LIGHTING_EMW100.decodeMsgFunction = decodeLighting5
	tableMsgTypes.LIGHTING_BBSB.decodeMsgFunction = decodeLighting5
	tableMsgTypes.LIGHTING_RSL2.decodeMsgFunction = decodeLighting5
	tableMsgTypes.LIGHTING_KANGTAI.decodeMsgFunction = decodeLighting5
	tableMsgTypes.LIGHTING_BLYSS.decodeMsgFunction = decodeLighting6
	tableMsgTypes.FAN_T0.decodeMsgFunction = decodeFan
	tableMsgTypes.FAN_T1.decodeMsgFunction = decodeFan
	tableMsgTypes.FAN_T2.decodeMsgFunction = decodeFan
	tableMsgTypes.FAN_T3.decodeMsgFunction = decodeFan
	tableMsgTypes.FAN_T4.decodeMsgFunction = decodeFan
	tableMsgTypes.FAN_T5.decodeMsgFunction = decodeFan
	tableMsgTypes.FAN_T6.decodeMsgFunction = decodeFan
	tableMsgTypes.FAN_T7.decodeMsgFunction = decodeFan
	tableMsgTypes.FAN_T8.decodeMsgFunction = decodeFan
	tableMsgTypes.FAN_T9.decodeMsgFunction = decodeFan
	tableMsgTypes.CURTAIN_HARRISON.decodeMsgFunction = decodeCurtain
	tableMsgTypes.BLIND_T0.decodeMsgFunction = decodeBlind
	tableMsgTypes.BLIND_T1.decodeMsgFunction = decodeBlind
	tableMsgTypes.BLIND_T2.decodeMsgFunction = decodeBlind
	tableMsgTypes.BLIND_T3.decodeMsgFunction = decodeBlind
	tableMsgTypes.BLIND_T4.decodeMsgFunction = decodeBlind
	tableMsgTypes.BLIND_T5.decodeMsgFunction = decodeBlind
	tableMsgTypes.BLIND_T6.decodeMsgFunction = decodeBlind
	tableMsgTypes.BLIND_T7.decodeMsgFunction = decodeBlind
	tableMsgTypes.SECURITY_X10DS.decodeMsgFunction = decodeSecurityDS
	tableMsgTypes.SECURITY_X10MS.decodeMsgFunction = decodeSecurityMS
	tableMsgTypes.SECURITY_X10SR.decodeMsgFunction = decodeSecurityRemote
	tableMsgTypes.SECURITY_MEISR.decodeMsgFunction = decodeSecurityMeiantech
	tableMsgTypes.KD101.decodeMsgFunction = decodeSecurityRemote
	tableMsgTypes.POWERCODE_PRIMDS.decodeMsgFunction = decodeSecurityDS
	tableMsgTypes.POWERCODE_AUXDS.decodeMsgFunction = decodeSecurityDS
	tableMsgTypes.POWERCODE_MS.decodeMsgFunction = decodeSecurityMS
	tableMsgTypes.SA30.decodeMsgFunction = decodeSecurityRemote
	tableMsgTypes.ATI_REMOTE_WONDER.decodeMsgFunction = decodeRemote
	tableMsgTypes.ATI_REMOTE_WONDER_PLUS.decodeMsgFunction = decodeRemote
	tableMsgTypes.MEDION_REMOTE.decodeMsgFunction = decodeRemote
	tableMsgTypes.X10_PC_REMOTE.decodeMsgFunction = decodeRemote
	tableMsgTypes.ATI_REMOTE_WONDER_II.decodeMsgFunction = decodeRemote
	tableMsgTypes.HEATER3_MERTIK1.decodeMsgFunction = decodeThermostat3
	tableMsgTypes.HEATER3_MERTIK2.decodeMsgFunction = decodeThermostat3
	tableMsgTypes.TR1.decodeMsgFunction = decodeTempRain
	tableMsgTypes.TEMP1.decodeMsgFunction = decodeTemp
	tableMsgTypes.TEMP2.decodeMsgFunction = decodeTemp
	tableMsgTypes.TEMP3.decodeMsgFunction = decodeTemp
	tableMsgTypes.TEMP4.decodeMsgFunction = decodeTemp
	tableMsgTypes.TEMP5.decodeMsgFunction = decodeTemp
	tableMsgTypes.TEMP6.decodeMsgFunction = decodeTemp
	tableMsgTypes.TEMP7.decodeMsgFunction = decodeTemp
	tableMsgTypes.TEMP8.decodeMsgFunction = decodeTemp
	tableMsgTypes.TEMP9.decodeMsgFunction = decodeTemp
	tableMsgTypes.TEMP10.decodeMsgFunction = decodeTemp
	tableMsgTypes.TEMP11.decodeMsgFunction = decodeTemp
	tableMsgTypes.HUM1.decodeMsgFunction = decodeHum
	tableMsgTypes.HUM2.decodeMsgFunction = decodeHum
	tableMsgTypes.TEMP_HUM1.decodeMsgFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM2.decodeMsgFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM3.decodeMsgFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM4.decodeMsgFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM5.decodeMsgFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM6.decodeMsgFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM7.decodeMsgFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM8.decodeMsgFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM9.decodeMsgFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM10.decodeMsgFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM11.decodeMsgFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM12.decodeMsgFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM13.decodeMsgFunction = decodeTempHum
	tableMsgTypes.TEMP_HUM14.decodeMsgFunction = decodeTempHum
	tableMsgTypes.BARO1.decodeMsgFunction = decodeBaro
	tableMsgTypes.TEMP_HUM_BARO1.decodeMsgFunction = decodeTempHumBaro
	tableMsgTypes.TEMP_HUM_BARO2.decodeMsgFunction = decodeTempHumBaro
	tableMsgTypes.RAIN1.decodeMsgFunction = decodeRain
	tableMsgTypes.RAIN2.decodeMsgFunction = decodeRain
	tableMsgTypes.RAIN3.decodeMsgFunction = decodeRain
	tableMsgTypes.RAIN4.decodeMsgFunction = decodeRain
	tableMsgTypes.RAIN5.decodeMsgFunction = decodeRain
	tableMsgTypes.RAIN6.decodeMsgFunction = decodeRain
	tableMsgTypes.RAIN7.decodeMsgFunction = decodeRain
	tableMsgTypes.WIND1.decodeMsgFunction = decodeWind
	tableMsgTypes.WIND2.decodeMsgFunction = decodeWind
	tableMsgTypes.WIND3.decodeMsgFunction = decodeWind
	tableMsgTypes.WIND4.decodeMsgFunction = decodeWind
	tableMsgTypes.WIND5.decodeMsgFunction = decodeWind
	tableMsgTypes.WIND6.decodeMsgFunction = decodeWind
	tableMsgTypes.WIND7.decodeMsgFunction = decodeWind
	tableMsgTypes.UV1.decodeMsgFunction = decodeUV
	tableMsgTypes.UV2.decodeMsgFunction = decodeUV
	tableMsgTypes.UV3.decodeMsgFunction = decodeUV
	tableMsgTypes.ELEC1.decodeMsgFunction = decodeElec1
	tableMsgTypes.ELEC2.decodeMsgFunction = decodeElec2Elec3
	tableMsgTypes.ELEC3.decodeMsgFunction = decodeElec2Elec3
	tableMsgTypes.ELEC4.decodeMsgFunction = decodeElec4
	tableMsgTypes.WEIGHT1.decodeMsgFunction = decodeWeight
	tableMsgTypes.WEIGHT2.decodeMsgFunction = decodeWeight
	tableMsgTypes.RFXSENSOR_T.decodeMsgFunction = decodeRFXSensor
	tableMsgTypes.RFXMETER.decodeMsgFunction = decodeRFXMeter
end

-- Function called at plugin startup
function startup(lul_device)
--require('mobdebug').start('<PC IP address>')

	THIS_DEVICE = lul_device

	task("Starting RFXtrx device: "..tostring(lul_device), TASK_SUCCESS)
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
		tableMsgByKey[msgType.key] = msgType
	end
	-- Build a table for selecting the message type based on the device altid
	for _, msgType in pairs(tableMsgTypes) do
		tableMsgBySubID[msgType.subAltID] = msgType
	end
	-- Build a table for selecting the category based on the subAltid
	for _, category in pairs(tableCategories) do
		tableCategoryBySubAltid[category.subAltid] = category
	end
	-- Build a table for selecting a command using a command code in a received message
	for action, cmdCodeCmd in pairs(tableActions2CmdCodes.FaAction2CmdCode) do
		tableCmdCodes2Commands.FaCmdCode2Command[cmdCodeCmd.cmdCode] = CmdAction(cmdCodeCmd.cmd, action)
	end
	for action, cmdCodeCmd in pairs(tableActions2CmdCodes.FbAction2CmdCode) do
		tableCmdCodes2Commands.FbCmdCode2Command[cmdCodeCmd.cmdCode] = CmdAction(cmdCodeCmd.cmd, action)
	end
	for action, cmdCodeCmd in pairs(tableActions2CmdCodes.FcAction2CmdCode) do
		tableCmdCodes2Commands.FcCmdCode2Command[cmdCodeCmd.cmdCode] = CmdAction(cmdCodeCmd.cmd, action)
	end
	for action, cmdCodeCmd in pairs(tableActions2CmdCodes.FdAction2CmdCode) do
		tableCmdCodes2Commands.FdCmdCode2Command[cmdCodeCmd.cmdCode] = CmdAction(cmdCodeCmd.cmd, action)
	end
	for action, cmdCodeCmd in pairs(tableActions2CmdCodes.FeAction2CmdCode) do
		tableCmdCodes2Commands.FeCmdCode2Command[cmdCodeCmd.cmdCode] = CmdAction(cmdCodeCmd.cmd, action)
	end
	for action, cmdCodeCmd in pairs(tableActions2CmdCodes.FfAction2CmdCode) do
		tableCmdCodes2Commands.FfCmdCode2Command[cmdCodeCmd.cmdCode] = CmdAction(cmdCodeCmd.cmd, action)
	end
	for action, cmdCodeCmd in pairs(tableActions2CmdCodes.FgAction2CmdCode) do
		tableCmdCodes2Commands.FgCmdCode2Command[cmdCodeCmd.cmdCode] = CmdAction(cmdCodeCmd.cmd, action)
	end
	for action, cmdCodeCmd in pairs(tableActions2CmdCodes.FhAction2CmdCode) do
		tableCmdCodes2Commands.FhCmdCode2Command[cmdCodeCmd.cmdCode] = CmdAction(cmdCodeCmd.cmd, action)
	end

	initIDLookup()

	initDecodingFunctions()

	initStateVariables()

	checkExistingDevices(THIS_DEVICE)

	-- Disable buffering
	buffering = false

	-- Send a reset command
	debug("reset...")
	debug("MODE_COMMAND.packetType: "..tableMsgTypes.MODE_COMMAND.pktType or 'nil')
	sendCommand(tableMsgTypes.MODE_COMMAND.pktType, tableMsgTypes.MODE_COMMAND.subType, DATA_MSG_RESET, nil)

	-- Wait at least 50 ms and max 9 s
	luup.sleep(2000)

	-- Send a get status command
	sendCommand(tableMsgTypes.MODE_COMMAND.pktType, tableMsgTypes.MODE_COMMAND.subType, DATA_MSG_GET_STATUS, nil)

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
		warning("Bad starting message; ignore byte "..string.format("%02X", val))
		return
	end

	buffer = buffer..data

	local length = string.byte(buffer, 1)
	if (#buffer > length)
		then
		local message = getStringPart(buffer, 1, length + 1)
		buffer = getStringPart(buffer, length + 2, #buffer)

		debug("Received message: "..formattohex(message))
		setVariable(THIS_DEVICE, tabVars.VAR_LAST_RECEIVED_MSG, formattohex(message))
		setVariable(THIS_DEVICE, tabVars.VAR_VERATIME, os.time())
		if (getVariable(THIS_DEVICE, tabVars.VAR_COMM_FAILURE) ~= "0")
			then
			luup.set_failure(false)
		end

		local success, error = pcall(decodeMessage,message)
		if(not success)then
			warning("No decode message for message: "..formattohex(message).."Error: "..error)
		end
	end

end

function saveSettings()

	log("Saving receiving modes in non-volatile memory...")
	sendCommand(tableMsgTypes.MODE_COMMAND.pktType, tableMsgTypes.MODE_COMMAND.subType, DATA_MSG_SAVE, nil)

end

-- switchPower only receives the device number and a 0 or 1 as input. It will select a command
-- based on the device type (LS, DL, or WC) and the desired state (0 or 1)
function switchPower(deviceNum, newTargetValue)
	local cmd, msgType, altid, subAltid, devType
	altid = luup.devices[deviceNum].id
	subAltid = string.match(altid, '/([^/]+/)')
	devType = string.match(altid, '([^/]+)')
	debug("switchPower-> altid: "..altid.." subAltid: "..(subAltid or 'nil').." devType: "..(devType or 'nil').." newTargetValue: "..(newTargetValue or 'nil'))
	if not( subAltid ) then
		warning("switchPower: invalid altid: "..altid)
		return
	end
	msgType = tableMsgBySubID[subAltid]
	if not ( msgType ) then
		warning("switchPower: no msgType found for altid: "..altid)
		return
	end
	newTargetValue = newTargetValue or "0"
	if (newTargetValue == "0") then
		cmd = tableCommandTypes.CMD_OFF
	elseif (newTargetValue == "1") then
		cmd = tableCommandTypes.CMD_ON
	else
		warning("Invalid newTargetValue "..(newTargetValue or 'nil').." altid: "..altid)
		return
	end
	local data, nbTimes = msgType.createMsgDataFunction(altid, cmd.name)
	if ( data )
		then
		if not (nbTimes) then nbTimes = 1 end
		local tableCmds = {}
		table.insert(tableCmds, DeviceCmd( string.sub(altid, 4), cmd, nil, 0 ))
		sendRepeatCommand(msgType.pktType, msgType.subType, data, nbTimes, tableCmds)
	else
		warning('switchPower: createMsgDataFunction failed for altid '..altid)
	end
end

function setDimLevel(deviceNum, newLoadlevelTarget)
	local altid, subAltid, level, msgType, nbTimes, data, cmd
	altid = luup.devices[deviceNum].id
	subAltid = string.match(altid, '/([^/]+/)')
	level = tonumber(newLoadlevelTarget) or 0
	debug("setDimLevel-> altid: "..altid.." subAltid: "..(subAltid or 'nil').." target: "..(newLoadlevelTarget or 'nil'))
	if not( subAltid ) then
		warning("setDimLevel: invalid altid: "..altid)
		return
	end
	data = nil
	cmd = tableCommandTypes.CMD_DIM
	-- window covers can't accept levels other than 0 or 100
	if (string.sub(altid,1,3) == "WC/") then
		if (level == 0) then
			windowCovering(deviceNum, "Close")
			return
		elseif (level == 100) then
			windowCovering(deviceNum, "Open")
			return
		elseif (level) then
			warning("setDimLevel: invalid newLoadlevelTarget value given for window cover: "..level)
			return
		end
	end
	msgType = tableMsgBySubID[subAltid]
	if not (msgType) then
		warning("setDimLevel: no msgType found for altid: "..altid)
		return
	end
	level = tonumber(newLoadlevelTarget) -- if newLoadlevelTarget is nil - so be it
	data, nbTimes = msgType.createMsgDataFunction(altid, cmd.name, level)
	if not (nbTimes) then nbTimes = 1 end

	if (data)
		then
		local tableCmds = {}
		table.insert(tableCmds, DeviceCmd( string.sub(altid, 4), cmd, newLoadlevelTarget, 0 ))
		-- Set the last dim level to 100. Do this to deal with Vera's using last dim level for some reason
		--  when we try to send a switchPower ON command.
		--table.insert(tableCmds, DeviceCmd( string.sub(altid, 4), tableCommandTypes.CMD_DIMLAST, 100, 0 ))
		sendRepeatCommand(msgType.pktType, msgType.subType, data, nbTimes, tableCmds)
	else
		warning('setDimLevel: createMsgDataFunction failed for altid '..altid)
	end
end

function windowCovering(deviceNum, action)
	local cmd, msgType, altid, subAltid
	local action2cmd = {
		['Up'] = tableCommandTypes.CMD_OPEN,
		['Open'] = tableCommandTypes.CMD_OPEN,
		['Down'] = tableCommandTypes.CMD_CLOSE,
		['Close'] = tableCommandTypes.CMD_CLOSE,
		['Stop'] = tableCommandTypes.CMD_STOP,
		['Program'] = tableCommandTypes.CMD_PROGRAM
	}
	altid = luup.devices[deviceNum].id
	subAltid = string.match(altid, '/([^/]+/)')
	cmd = action2cmd[action]
	debug("windowCovering-> altid: "..altid.." subAltid: "..(subAltid or 'nil').." action: "..action)
	if not( cmd ) then
		warning("windowCovering: unusual action: "..action)
		--return
	end
	if not( subAltid ) then
		warning("windowCovering: invalid altid: "..altid)
		return
	end
	msgType = tableMsgBySubID[subAltid]
	if not ( msgType ) then
		warning("windowCovering: no msgType found for altid: "..altid)
		return
	end
	local data = msgType.createMsgDataFunction(altid, action)
	if (data)
		then
		local tableCmds = {}
		table.insert(tableCmds, DeviceCmd( string.sub(altid, 4), cmd, nil, 0 ))
		sendCommand(msgType.pktType, msgType.subType, data, tableCmds)
	else
		warning('windowCovering: createMsgDataFunction failed for altid '..altid)
	end
end

function controlFan(deviceNum, action)
	local msgType, altid, subAltid, currentState, value
	altid = luup.devices[deviceNum].id
	subAltid = string.match(altid, '/([^/]+/)')
	debug("controlFan-> altid: "..altid.." subAltid: "..(subAltid or 'nil').." action: "..action)
	if not( subAltid ) then
		warning("controlFan: invalid altid: "..altid)
		return
	end
	msgType = tableMsgBySubID[subAltid]
	if not ( msgType ) then
		warning("controlFan: no msgType found for altid: "..altid)
		return
	end
	local data, cmd = msgType.createMsgDataFunction(altid, action)
	if not( cmd ) then
		warning("controlFan: no cmd for action "..action.." on "..altid)
	end
	if (cmd == tableCommandTypes.CMD_FANLIGHT) then
		if (action == 'LightOn') then
			value = 1
		elseif (action == 'LightOff') then
			value = 0
		else
			currentState = getVariable(deviceNum, tabVars.VAR_LIGHT) or "0"
			if (currentState == "0") then
				value = "1"
			else
				value = "0"
			end
		end
	elseif (cmd == tableCommandTypes.CMD_REVERSE) then
		currentState = getVariable(deviceNum, tabVars.VAR_REVERSE) or "0"
		if (currentState == "0") then
			value = "1"
		else
			value = "0"
		end
	elseif (action == 'SpeedUp') then
		currentState = tonumber(getVariable(deviceNum, tabVars.VAR_SPEED))
		if not(currentState) then currentState = 0 end
		-- increment the speed but don't go above 6
		value =tostring(math.min(currentState+1, 6))
	elseif (action == 'SpeedDown') then
		currentState = tonumber(getVariable(deviceNum, tabVars.VAR_SPEED))
		if not(currentState) then currentState = 1 end
		-- decrement the speed but don't go below 0
		value = tostring(math.max(currentState-1, 0))
		if (value == '0') then value = 'Off' end
	elseif (action == 'Flow') then
		currentState = tonumber(getVariable(deviceNum, tabVars.VAR_SPEED))
		if not(currentState) then currentState = 0 end
		local currentSpeed = math.min(currentState,6)
		if (currentSpeed < 4) then
			value = tostring(math.max(currentSpeed-1, 1))
		else
			value = tostring(math.min(currentSpeed+1, 6))
		end
	else
		value = action
	end
	if (data)
		then
		local tableCmds = {}
		table.insert(tableCmds, DeviceCmd( string.sub(altid, 4), cmd, value, 0 ))
		sendCommand(msgType.pktType, msgType.subType, data, tableCmds)
	else
		warning('controlFan: createMsgDataFunction failed for altid '..altid)
	end
end

function setArmed(deviceNum, newArmedValue)

	local id = luup.devices[deviceNum].id
	debug("setArmed "..id.." target "..(newArmedValue or "nil"))
	if(newArmedValue == "1") then
		newArmedValue = true
	else
		newArmedValue = false
	end

	setVariable(deviceNum, tabVars.VAR_ARMED, newArmedValue)

end

function requestArmMode(deviceNum, state, PINcode)

	local id = luup.devices[deviceNum].id
	debug("requestArmMode "..id.." state "..state.." PIN code "..PINcode)
	requestQuickArmMode(deviceNum, state)

end

function requestQuickArmMode(deviceNum, state)

	local id = luup.devices[deviceNum].id
	debug("requestQuickArmMode "..id.." state "..state)

	if ((string.len(id) ~= 16) or (string.sub(id, 1, 10) ~= "SR/X10/SR/" and string.sub(id, 1, 10) ~= "SR/MEI/SR/"))
		then
		warning("Unexpected device id "..id..". Quick Arm Mode command not sent")
		return
	end

	local type = nil
	local subType = nil
	local exitDelay = 0
	if (string.sub(id, 1, 9) == "SR/X10/SR")
		then
		type = tableMsgTypes.SECURITY_X10SR.pktType
		subType = tableMsgTypes.SECURITY_X10SR.subType
		exitDelay = tonumber(getVariable(deviceNum, tabVars.VAR_EXIT_DELAY) or "0")
	elseif (string.sub(id, 1, 9) == "SR/MEI/SR")
		then
		type = tableMsgTypes.SECURITY_MEISR.pktType
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
		warning("Unimplemented state "..state..". Quick Arm Mode command not sent")
	end
	if (cmdCode)
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
	debug("requestPanicMode "..id.." state "..state)

	if ((string.len(id) ~= 16) or (string.sub(id, 1, 10) ~= "SR/X10/SR/"
		and string.sub(id, 1, 10) ~= "SR/MEI/SR/"
		and string.sub(id, 1, 10) ~= "SR/KD1/SR/"
		and string.sub(id, 1, 10) ~= "SR/S30/SR/"))
		then
		warning("Unexpected device id "..id..". Panic Mode command not sent")
		return
	end

	local type = nil
	local subType = nil
	if (string.sub(id, 1, 9) == "SR/X10/SR")
		then
		type = tableMsgTypes.SECURITY_X10SR.pktType
		subType = tableMsgTypes.SECURITY_X10SR.subType
	elseif (string.sub(id, 1, 9) == "SR/MEI/SR")
		then
		type = tableMsgTypes.SECURITY_MEISR.pktType
		subType = tableMsgTypes.SECURITY_MEISR.subType
	elseif (string.sub(id, 1, 9) == "SR/KD1/SR")
		then
		type = tableMsgTypes.KD101.pktType
		subType = tableMsgTypes.KD101.subType
	elseif (string.sub(id, 1, 9) == "SR/S30/SR")
		then
		type = tableMsgTypes.SA30.pktType
		subType = tableMsgTypes.SA30.subType
	end

	local remoteId = string.sub(id, 11, 16)
	local data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
	tonumber(string.sub(remoteId, 3, 4), 16),
	tonumber(string.sub(remoteId, 5, 6), 16),
	0x06, 0)
	local tableCmds = {}
	table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ALARM_SCENE_ON, 120, 0 ))
	if (type == tableMsgTypes.KD101.pktType)
		then
		id = "KD1/SS/"..string.sub(remoteId, 1, 2)
		..string.sub(remoteId, 3, 4)
		..string.sub(remoteId, 5, 6)
		table.insert(tableCmds, DeviceCmd( id, tableCommandTypes.CMD_SMOKE, "1", 0 ) )
		table.insert(tableCmds, DeviceCmd( id, tableCommandTypes.CMD_SMOKE_OFF, nil, 30 ) )
	elseif (type == tableMsgTypes.SA30.pktType)
		then
		id = "S30/SS/"..string.sub(remoteId, 1, 2)
		..string.sub(remoteId, 3, 4)
		..string.sub(remoteId, 5, 6)
		table.insert(tableCmds, DeviceCmd( id, tableCommandTypes.CMD_SMOKE, "1", 0 ) )
		table.insert(tableCmds, DeviceCmd( id, tableCommandTypes.CMD_SMOKE_OFF, nil, 30 ) )
	end
	sendCommand(type, subType, data, tableCmds)

end

function setExitDelay(deviceNum, newValue)

	local id = luup.devices[deviceNum].id
	debug("setExitDelay "..id.." new value "..(newValue or ""))

	if ((string.len(id) ~= 16) or string.sub(id, 1, 10) ~= "SR/X10/SR/")
		then
		task("Exit delay is not relevant for device id "..id, TASK_ERROR)
		return
	end

	setVariable(deviceNum, tabVars.VAR_EXIT_DELAY, newValue or "0")

end

function dim(deviceNum)
	local cmd, msgType, altid, subAltid
	altid = luup.devices[deviceNum].id
	subAltid = string.match(altid, '/([^/]+/)')
	debug("dim-> altid: "..altid.." subAltid: "..(subAltid or 'nil'))
	if not (string.find(subAltid, 'L[1235]')) then
		warning("dim: Dim command not valid for altid: "..altid)
		return
	end
	if not( subAltid ) then
		warning("Dim: invalid altid: "..altid)
		return
	end
	msgType = tableMsgBySubID[subAltid]
	if not ( msgType ) then
		warning("dim: no msgType found for altid: "..altid)
		return
	end

	cmd = tableCommandTypes.CMD_SCENE_ON
	--local data = string.sub(id, 9, 9)..string.char(0, 0x02, 0)
	local data = msgType.createMsgDataFunction(altid, 'Dim')
	if (data)
		then
		local tableCmds = {}
		--table.insert(tableCmds, DeviceCmd( string.sub(altid, 4), cmd, nil, 0 ))
		table.insert(tableCmds, DeviceCmd( string.sub(altid, 4), cmd, 102, 0 ))
		sendCommand(msgType.pktType, msgType.subType, data, tableCmds)
	else
		warning('dim: createMsgDataFunction failed for altid '..altid)
	end
end

function bright(deviceNum)
	local cmd, msgType, altid, subAltid
	altid = luup.devices[deviceNum].id
	subAltid = string.match(altid, '/([^/]+/)')
	debug("bright-> altid: "..altid.." subAltid: "..(subAltid or 'nil'))
	if not (string.find(subAltid, 'L[135]')) then
		warning("bright: Bright command not valid for altid: "..altid)
		return
	end
	if not( subAltid ) then
		warning("bright: invalid altid: "..altid)
		return
	end
	msgType = tableMsgBySubID[subAltid]
	if not ( msgType ) then
		warning("bright: no msgType found for altid: "..altid)
		return
	end

	cmd = tableCommandTypes.CMD_SCENE_ON
	--local data = string.sub(id, 9, 9)..string.char(0, 0x03, 0)
	local data = msgType.createMsgDataFunction(altid, 'Bright')
	if (data)
		then
		local tableCmds = {}
		--table.insert(tableCmds, DeviceCmd( string.sub(altid, 4), cmd, nil, 0 ))
		table.insert(tableCmds, DeviceCmd( string.sub(altid, 4), cmd, 103, 0 ))
		sendCommand(msgType.pktType, msgType.subType, data, tableCmds)
	else
		warning('bright: createMsgDataFunction failed for altid '..altid)
	end
end

function groupOff(deviceNum)
	-- Currently this function is only called as a result of a UI remote button press
	-- The remotes associated with actual devices omit the unit code in the altid
	local altid, subAltid, devType
	altid = luup.devices[deviceNum].id
	subAltid = string.match(altid, '/([^/]+/)')
	if not( subAltid ) then
		warning("groupOff: invalid altid: "..altid)
		task("GroupOff: invalid altid: "..altid, TASK_ERROR)
		return
	end
	debug("groupOff-> altid: "..altid.." subAltid: "..(subAltid or 'nil'))
	if not (string.find(subAltid, 'L[1256]')) then
		warning("groupOff: groupOff command not valid for altid: "..altid)
		task("Group Off command is not relevant for device "..altid, TASK_ERROR)
		return
	end
	devType = string.match(altid, '([^/]+)')

	local msgType, category, cmd, formatAltid, device
	local unitCodeMin = nil
	local unitCodeMax = nil
	local data = nil
	local tableCmds = {}

	msgType = tableMsgBySubID[subAltid]
	if not (msgType) then
		warning("groupOff: no msgType found for altid: "..altid)
		task("GroupOff: no msgType found for altid: "..altid, TASK_ERROR)
		return
	end
	category = tableCategoryBySubAltid[subAltid]
	if not (category) then
		warning("groupOff: no category found for altid: "..altid)
		task("GroupOff: no category found for altid: "..altid, TASK_ERROR)
		return
	end
	data = msgType.createMsgDataFunction(altid, 'GroupOff')
	if (msgType == tableMsgTypes.LIGHTING_LIGHTWARERF) then
		cmd = tableCommandTypes.CMD_LWRF_SCENE_OFF
	else
		cmd = tableCommandTypes.CMD_SCENE_OFF
	end
	if (msgType == tableMsgTypes.LIGHTING_LIVOLO) then
		unitCodeMin = 1
		unitCodeMax = 3
		formatAltid = "%s/%d"
	else
		if (category.unitCodeLimits and category.unitCodeLimits.minimum and category.unitCodeLimits.maximum) then
			unitCodeMin = category.unitCodeLimits.minimum
			unitCodeMax = category.unitCodeLimits.maximum
		else
			warning("groupOff: no unitCodeLimits found for altid: "..altid)
		end
		if (string.find(subAltid, 'L6')) then
			formatAltid = "%s%d"
		elseif (string.find(subAltid, 'L1')) then
			formatAltid = "%s%02d"
		else
			formatAltid = "%s/%02d"
		end
	end
	-- This will update the remote UI device
	table.insert(tableCmds, DeviceCmd( string.sub(altid, 4), cmd, 100, 0 ))

	if (data)
		then
		if (unitCodeMin and unitCodeMax)
			then
			local searchId
			for i = unitCodeMin, unitCodeMax
				do
				searchId = string.format(formatAltid, string.sub(altid, 4), i)
				device = findChild(THIS_DEVICE, searchId, nil)
				if (device)
					then
					table.insert(tableCmds, DeviceCmd( searchId, tableCommandTypes.CMD_OFF, nil, 0 ))
				end
			end
		end
		sendCommand(msgType.pktType, msgType.subType, data, tableCmds)
	end

end

function groupOn(deviceNum)
	-- Currently this function is only called as a result of a UI remote button press
	-- The remotes associated with actual devices omit the unit code in the altid
	local altid, subAltid, devType
	altid = luup.devices[deviceNum].id
	subAltid = string.match(altid, '/([^/]+/)')
	debug("groupOn-> altid: "..altid.." subAltid: "..(subAltid or 'nil'))
	if not( subAltid ) then
		warning("groupOn: invalid altid: "..altid)
		task("groupOn: invalid altid: "..altid, TASK_ERROR)
		return
	end
	if not (string.find(subAltid, 'L[1256]')) then
		warning("groupOn: groupOff command not valid for altid: "..altid)
		task("Group On command is not relevant for device "..altid, TASK_ERROR)
		return
	end
	devType = string.match(altid, '([^/]+)')

	local msgType, category, cmd, formatAltid, device
	local unitCodeMin = nil
	local unitCodeMax = nil
	local data = nil
	local tableCmds = {}

	msgType = tableMsgBySubID[subAltid]
	if not (msgType) then
		warning("groupOn: no msgType found for altid: "..altid)
		task("groupOn: no msgType found for altid: "..altid, TASK_ERROR)
		return
	end
	category = tableCategoryBySubAltid[subAltid]
	if not (category) then
		warning("groupOn: no category found for altid: "..altid)
		task("groupOn: no category found for altid: "..altid, TASK_ERROR)
		return
	end
	data = msgType.createMsgDataFunction(altid, 'GroupOn')
	cmd = tableCommandTypes.CMD_SCENE_ON
	if (category.unitCodeLimits and category.unitCodeLimits.minimum and category.unitCodeLimits.maximum) then
		unitCodeMin = category.unitCodeLimits.minimum
		unitCodeMax = category.unitCodeLimits.maximum
	else
		warning("groupOn: no unitCodeLimits found for altid: "..altid)
	end
	if (string.find(subAltid, 'L6')) then
		formatAltid = "%s%d"
	elseif (string.find(subAltid, 'L1')) then
		formatAltid = "%s%02d"
	else
		formatAltid = "%s/%02d"
	end
	-- This will update the remote UI device
	table.insert(tableCmds, DeviceCmd( string.sub(altid, 4), cmd, 100, 0 ))

	if (data)
		then
		if (unitCodeMin and unitCodeMax)
			then
			local searchId
			for i = unitCodeMin, unitCodeMax
				do
				searchId = string.format(formatAltid, string.sub(altid, 4), i)
				device = findChild(THIS_DEVICE, searchId, nil)
				if (device)
					then
					table.insert(tableCmds, DeviceCmd( searchId, tableCommandTypes.CMD_ON, nil, 0 ))
				end
			end
		end
		sendCommand(msgType.pktType, msgType.subType, data, tableCmds)
	end

end

function mood(deviceNum, param)
	local altid, subAltid, devType, msgType
	altid = luup.devices[deviceNum].id
	subAltid = string.match(altid, '/([^/]+/)')
	debug("mood-> altid: "..altid.." subAltid: "..(subAltid or 'nil'))
	if not( subAltid ) then
		warning("mood: invalid altid: "..altid)
		task("mood: invalid altid: "..altid, TASK_ERROR)
		return
	end
	devType = string.match(altid, '([^/]+)')
	msgType = tableMsgBySubID[subAltid]
	if not (msgType) then
		warning("mood: no msgType found for altid: "..altid)
		task("mood: no msgType found for altid: "..altid, TASK_ERROR)
		return
	end
	if (msgType ~= tableMsgTypes.LIGHTING_LIGHTWARERF)
		then
		warning("Mood command is not relevant for device: "..altid)
		task("Mood command is not relevant for device "..altid, TASK_ERROR)
		return
	end
	local mood2cmdCode = {
		0x03,
		0x04,
		0x05,
		0x06,
	}

	local value = tonumber(param)
	local cmdCode = mood2cmdCode[value]
	if not (cmdCode) then
		warning("action Mood: unexpected value for argument: "..(param or 'nil'))
		task("action Mood: unexpected value for argument: "..(param or 'nil'), TASK_ERROR)
		return
	else
		local tableCmds = {}
		table.insert(tableCmds, DeviceCmd( string.sub(altid, 4), tableCommandTypes.CMD_LWRF_SCENE_ON, 110+value, 0 ))

		local remoteId = string.sub(altid, 9, 14)
		local data = string.char(tonumber(string.sub(remoteId, 1, 2), 16),
		tonumber(string.sub(remoteId, 3, 4), 16),
		tonumber(string.sub(remoteId, 5, 6), 16),
		0, cmdCode, 0, 0)
		sendCommand(tableMsgTypes.LIGHTING_LIGHTWARERF.pktType, tableMsgTypes.LIGHTING_LIGHTWARERF.subType, data, tableCmds)
	end

end

function sendATICode(deviceNum, code)

	local id = luup.devices[deviceNum].id
	debug("sendATICode "..id.." code "..code)

	if ((string.len(id) ~= 9) or (string.sub(id, 1, 5) ~= "RC/RC") or (string.sub(id, 7, 7) ~= "/"))
		then
		task("Send code is not relevant for device "..id, TASK_ERROR)
		return
	end
	local subType = tonumber(string.sub(id, 6, 6))
	if (subType >= 0x4)
		then
		task("Send code is not relevant for device "..id, TASK_ERROR)
		return
	end

	local tableCmds = {}
	table.insert(tableCmds, DeviceCmd( string.sub(id, 4), tableCommandTypes.CMD_ATI_SCENE_ON, tonumber(code), 0 ))

	local data = string.char(tonumber(string.sub(id, 8, 9), 16), tonumber(code), 0)
	-- TODO toggle
	sendCommand(tableMsgTypes.ATI_REMOTE_WONDER.pktType, subType, data, tableCmds)

end

function setModeTarget(deviceNum, NewModeTarget)
	local id = luup.devices[deviceNum].id
	debug("setModeTarget "..id.." target "..NewModeTarget)

	local category
	if ((string.len(id) == 15) and (string.sub(id, 1, 5) == "HT/HT") and (string.sub(id, 7, 7) == ".")  and (string.sub(id, 9, 9) == "/"))
		then
		category = 3
	else
		warning("Unexpected device id "..id..". Set Mode command not sent")
		return
	end

	local type = nil
	local subType = nil
	local tableCmds = {}
	local data = nil

	if (category == 3) -- Mertik
		then
		type = tableMsgTypes.HEATER3_MERTIK1.pktType
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

	if (data)
		then
		sendCommand(type, subType, data, tableCmds)
	end

end

function toggleState(deviceNum)
	debug("toggleState: "..deviceNum)
	local altId = luup.devices[deviceNum].id
	local devType = string.sub(altId, 1, 2)
	local subAltid = string.match(altId, '/([^/.]+)')
 	local currentState, newTargetState

	debug("Device type: "..devType.." subType: "..(subAltid or 'nil'))

	-- Only implemented for Sonoff switches, Light Switches and Heaters so far
	if (devType == "LS") then
		currentState = getVariable(deviceNum, tabVars.VAR_LIGHT) or "0"
		if (currentState == "0") then
			newTargetState = "1"
		else
			newTargetState = "0"
		end
		switchPower(deviceNum, newTargetState)
	elseif (devType == "HT") then
		currentState = getVariable(deviceNum, tabVars.VAR_HEATER) or "Off"
		if (currentState == "Off") then
			newTargetState = "HeatOn"
		else
			newTargetState = "Off"
		end
		setModeTarget(deviceNum, newTargetState)
	elseif (devType == "FN") then
		controlFan(deviceNum, "Light")
	end
end

function createNewDevice(category, deviceType, name, id, houseCode, groupCode, unitCode, systemCode, channel)
	debug("createNewDevice->category: "..(category or "nil").." device type: "..(deviceType or "nil"))

	if (category == nil or tableCategories[category] == nil)
		then
		warning("action CreateNewDevice: invalid value for the Category argument: "..(category or 'nil'))
		task("CreateNewDevice: invalid arguments", TASK_ERROR)
		return
	end

	local valid = true
	local params = {}

	if (deviceType == nil)
		then
		warning("action CreateNewDevice: missing value for the DeviceType argument")
		valid = false
	elseif (deviceType ~= "LIGHT" and deviceType ~= "DIMMER"
		and deviceType ~= "MOTION" and deviceType ~= "DOOR"
		and deviceType ~= "LIGHT_LEVEL" and deviceType ~= "COVER"
		and deviceType ~= "FAN")
		then
		warning("action CreateNewDevice: invalid value for the DeviceType argument")
		valid = false
	elseif ((deviceType == "LIGHT" and not tableCategories[category].isaLIGHT)
		or (deviceType == "DIMMER" and not tableCategories[category].isaDIMMER)
		or (deviceType == "MOTION" and not tableCategories[category].isaMOTION)
		or (deviceType == "DOOR" and not tableCategories[category].isaDOOR)
		or (deviceType == "LIGHT_LEVEL" and not tableCategories[category].isaLIGHT_LEVEL)
		or (deviceType == "COVER" and not tableCategories[category].isaCOVER)
		or (deviceType == "FAN" and not tableCategories[category].isaFAN))
		then
		warning("action CreateNewDevice: DeviceType value not accepted for this category")
		valid = false
	end

	if (tableCategories[category].idLimits)
		then
		if (id == nil)
			then
			warning("action CreateNewDevice: missing value for the Id argument")
			valid = false
		elseif (tonumber(id) == nil)
			then
			warning("action CreateNewDevice: invalid value for the Id argument")
			valid = false
		elseif (tableCategories[category].idLimits.minimum and tableCategories[category].idLimits.maximum
			and (tonumber(id) < tableCategories[category].idLimits.minimum
			or tonumber(id) > tableCategories[category].idLimits.maximum))
			then
			warning(string.format("action CreateNewDevice: value for the Id argument must be in range %d - %d",
			tableCategories[category].idLimits.minimum,
			tableCategories[category].idLimits.maximum))
			valid = false
		else
			table.insert(params, tonumber(id))
		end
	end
	if (tableCategories[category].houseCodeLimits)
		then
		if (houseCode == nil)
			then
			warning("action CreateNewDevice: missing value for the HouseCode argument")
			valid = false
		elseif (#houseCode ~= 1)
			then
			warning("action CreateNewDevice: invalid value for the HouseCode argument")
			valid = false
		elseif (tableCategories[category].houseCodeLimits.minimum and tableCategories[category].houseCodeLimits.maximum
			and (string.byte(houseCode) < tableCategories[category].houseCodeLimits.minimum
			or string.byte(houseCode) > tableCategories[category].houseCodeLimits.maximum))
			then
			warning(string.format("action CreateNewDevice: value for the HouseCode argument must be in range %s - %s",
			string.char(tableCategories[category].houseCodeLimits.minimum),
			string.char(tableCategories[category].houseCodeLimits.maximum)))
			valid = false
		else
			table.insert(params, houseCode)
		end
	end
	if (tableCategories[category].groupCodeLimits)
		then
		if (groupCode == nil)
			then
			warning("action CreateNewDevice: missing value for the GroupCode argument")
			valid = false
		elseif (#groupCode ~= 1)
			then
			warning("action CreateNewDevice: invalid value for the GroupCode argument")
			valid = false
		elseif (tableCategories[category].groupCodeLimits.minimum and tableCategories[category].groupCodeLimits.maximum
			and (string.byte(groupCode) < tableCategories[category].groupCodeLimits.minimum
			or string.byte(groupCode) > tableCategories[category].groupCodeLimits.maximum))
			then
			warning(string.format("action CreateNewDevice: value for the GroupCode argument must be in range %s - %s",
			string.char(tableCategories[category].groupCodeLimits.minimum),
			string.char(tableCategories[category].groupCodeLimits.maximum)))
			valid = false
		else
			table.insert(params, groupCode)
		end
	end
	if (tableCategories[category].unitCodeLimits)
		then
		if (unitCode == nil)
			then
			warning("action CreateNewDevice: missing value for the UnitCode argument")
			valid = false
		elseif (tonumber(unitCode) == nil)
			then
			warning("action CreateNewDevice: invalid value for the UnitCode argument")
			valid = false
		elseif (tableCategories[category].unitCodeLimits.minimum and tableCategories[category].unitCodeLimits.maximum
			and (tonumber(unitCode) < tableCategories[category].unitCodeLimits.minimum
			or tonumber(unitCode) > tableCategories[category].unitCodeLimits.maximum))
			then
			warning(string.format("action CreateNewDevice: value for the UnitCode argument must be in range %d - %d",
			tableCategories[category].unitCodeLimits.minimum,
			tableCategories[category].unitCodeLimits.maximum))
			valid = false
		else
			table.insert(params, unitCode)
		end
	end
	if (tableCategories[category].systemCodeLimits)
		then
		if (systemCode == nil)
			then
			warning("action CreateNewDevice: missing value for the SystemCode argument")
			valid = false
		elseif (tonumber(systemCode) == nil)
			then
			warning("action CreateNewDevice: invalid value for the SystemCode argument")
			valid = false
		elseif (tableCategories[category].systemCodeLimits.minimum and tableCategories[category].systemCodeLimits.maximum
			and (tonumber(systemCode) < tableCategories[category].systemCodeLimits.minimum
			or tonumber(systemCode) > tableCategories[category].systemCodeLimits.maximum))
			then
			warning(string.format("action CreateNewDevice: value for the SystemCode argument must be in range %d - %d",
			tableCategories[category].systemCodeLimits.minimum,
			tableCategories[category].systemCodeLimits.maximum))
			valid = false
		else
			table.insert(params, tonumber(systemCode-1))
		end
	end
	if (tableCategories[category].channelLimits)
		then
		if (channel == nil)
			then
			warning("action CreateNewDevice: missing value for the Channel argument")
			valid = false
		elseif (tonumber(channel) == nil)
			then
			warning("action CreateNewDevice: invalid value for the Channel argument")
			valid = false
		elseif (tableCategories[category].channelLimits.minimum and tableCategories[category].channelLimits.maximum
			and (tonumber(channel) < tableCategories[category].channelLimits.minimum
			or tonumber(channel) > tableCategories[category].channelLimits.maximum))
			then
			warning(string.format("action CreateNewDevice: value for the Channel argument must be in range %d - %d",
			tableCategories[category].channelLimits.minimum,
			tableCategories[category].channelLimits.maximum))
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

	local devices = {}
	local altid = string.format(tableCategories[category].altidFmt, tableCategories[category].subAltid,
	params[1], params[2], params[3])
	if (findChild(THIS_DEVICE, altid, nil) == nil)
		then
		table.insert(devices, { name, nil, altid, deviceType })
	end
	if (tableCategories[category].type2 and tableCategories[category].altid2Fmt)
		then
		altid = string.format(tableCategories[category].altid2Fmt, tableCategories[category].subAltid,
		params[1], params[2], params[3])
		if (findChild(THIS_DEVICE, altid, nil) == nil)
			then
			table.insert(devices, { name, nil, altid, tableCategories[category].type2 })
		end
	end
	if (tableCategories[category].type3 and tableCategories[category].altid3Fmt)
		then
		altid = string.format(tableCategories[category].altid3Fmt, tableCategories[category].subAltid,
		params[1], params[2], params[3])
		if (findChild(THIS_DEVICE, altid, nil) == nil)
			then
			table.insert(devices, { name, nil, altid, tableCategories[category].type3 })
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

	debug("changeDeviceType "..(deviceId or "nil").." "..(deviceType or "nil"))

	if (deviceId)
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
		warning("action ChangeDeviceType: the device "..deviceId.." does not exist")
		task("ChangeDeviceType: invalid arguments", TASK_ERROR)
		return
	end

	local altid = string.sub(luup.devices[deviceId].id, 4)

	local category = nil
	for k, v in pairs(tableCategories)
		do
		if (string.find(altid, v.subAltid) == 1)
			then
			category = k
			break
		end
	end
	if (category == nil)
		then
		warning("action ChangeDeviceType: invalid altid for the device "..deviceId)
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
		warning("action ChangeDeviceType: the device type cannot be changed for the device "..deviceId)
		task("ChangeDeviceType: forbidden for this device", TASK_ERROR)
		return
	elseif (deviceType == currentType.jsDeviceType and luup.devices[deviceId].device_type == currentType.deviceType)
		then
		warning("action ChangeDeviceType: the device "..deviceId.." has already the requested type")
		task("ChangeDeviceType: type is ok", TASK_ERROR)
		return
	end

	if (deviceType == nil)
		then
		warning("action ChangeDeviceType: missing value for the DeviceType argument")
		task("ChangeDeviceType: invalid arguments", TASK_ERROR)
		return
	elseif (deviceType ~= "LIGHT" and deviceType ~= "DIMMER"
		and deviceType ~= "MOTION" and deviceType ~= "DOOR"
		and deviceType ~= "LIGHT_LEVEL" and deviceType ~= "COVER")
		then
		warning("action ChangeDeviceType: invalid value for the DeviceType argument")
		task("ChangeDeviceType: invalid arguments", TASK_ERROR)
		return
	elseif ((deviceType == "LIGHT" and not tableCategories[category].isaLIGHT)
		or (deviceType == "DIMMER" and not tableCategories[category].isaDIMMER)
		or (deviceType == "MOTION" and not tableCategories[category].isaMOTION)
		or (deviceType == "DOOR" and not tableCategories[category].isaDOOR)
		or (deviceType == "LIGHT_LEVEL" and not tableCategories[category].isaLIGHT_LEVEL)
		or (deviceType == "COVER" and not tableCategories[category].isaCOVER))
		then
		warning("action ChangeDeviceType: DeviceType value not accepted for the device "..deviceId)
		task("ChangeDeviceType: new type forbidden for this device", TASK_ERROR)
		return
	end

	local devType = deviceType
	local newName = luup.devices[deviceId].description
	if (name and name ~= "")
		then
		newName = name
	end
	debug("changeDeviceType "..altid.." "..devType.." "..newName)
	updateManagedDevices(nil,
		{ { newName,
			luup.devices[deviceId].room_num,
			altid,
	devType } },
	nil)

end

function deleteDevices(listDevices, disableCreation)

	debug("deleteDevices "..(listDevices or "nil").." "..(disableCreation or "nil"))

	local tableDeletion = {}
	if (listDevices)
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

function sendUnusualCommand(deviceId, commandName)

	debug("sendUnusualCommand->Device number: "..(deviceId or "nil").." Command: "..(commandName or "nil"))

	if (deviceId)
		then
		deviceId = tonumber(deviceId)
	end
	if not (deviceId)
		then
		warning("sendUnusualCommand: missing value for the DeviceId argument")
		task("sendUnusualCommand: invalid arguments", TASK_ERROR)
		return
	elseif not (luup.devices[deviceId])
		then
		warning("sendUnusualCommand: the device "..deviceId.." does not exist")
		task("sendUnusualCommand: invalid arguments", TASK_ERROR)
		return
	elseif not (commandName)
		then
		warning("sendUnusualCommand: missing value for the commandName argument")
		task("sendUnusualCommand: missing value for the commandName argument", TASK_ERROR)
		return
	end

	local altid, subAltid, msgType, data
	altid = luup.devices[deviceId].id
	subAltid = string.match(altid, '/([^/]+/)')
	debug("sendUnusualCommand-> altid: "..altid.." subAltid: "..(subAltid or 'nil').." command: "..(commandName or 'nil'))
	if not( subAltid ) then
		warning("sendUnusualCommand: invalid altid: "..altid)
		return
	end
	data = nil
	msgType = tableMsgBySubID[subAltid]
	if not (msgType) then
		warning("sendUnusualCommand: no msgType found for altid: "..altid)
		return
	end
	data = msgType.createMsgDataFunction(altid, commandName)

	if (data)
		then
		local tableCmds = {}
		table.insert(tableCmds, DeviceCmd( string.sub(altid, 4), "", nil, 0 ))
		sendCommand(msgType.pktType, msgType.subType, data, tableCmds)
	else
		warning('sendUnusualCommand: createMsgDataFunction failed for altid '..altid)
	end
end

function receiveMessage(message)

	if (#message < 10)
		then
		warning("Action ReceiveMessage: invalid message")
		return
	end

	debug("Action ReceiveMessage: message received: "..message)

	local msg = ""
	for i = 1, #message / 2
		do
		msg = msg..string.char(tonumber(string.sub(message, i*2-1, i*2), 16))
	end

	decodeMessage(msg)

end

function sendMessage(message)

	if (#message < 10)
		then
		warning("Action SendMessage: invalid message - too short")
		return
	end

	debug("Action SendMessage: message to send: "..message)

	local msg = ""
	for i = 1, #message / 2
		do
		msg = msg..string.char(tonumber(string.sub(message, i*2-1, i*2), 16))
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

	debug("setTemperatureUnit "..(unit or "nil"))

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

	debug("setLengthUnit "..(newUnit or "nil"))
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

	debug("setSpeedUnit "..(unit or "nil"))
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

	debug("setVoltage "..(value or "nil"))
	setVariable(THIS_DEVICE, tabVars.VAR_VOLTAGE, value or 230)
end

function setAutoCreate(enable)

	debug("setAutoCreate "..(enable or "nil"))
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

	debug("setDebugLogs "..(enable or "nil"))
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
	if (getVariable(THIS_DEVICE, tabVars.VAR_FUNKBUS_RECEIVING))
		then
		msg6 = msg6 + 0x80
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_MCZ_RECEIVING))
		then
		msg6 = msg6 + 0x40
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_HOMECONFORT_RECEIVING))
		then
		msg6 = msg6 + 0x02
	end
	if (getVariable(THIS_DEVICE, tabVars.VAR_KEELOQ_RECEIVING))
		then
		msg6 = msg6 + 0x01
	end

	local data = string.char(3, typeRFX, 0, msg3, msg4, msg5, msg6, 0, 0, 0)
	sendCommand(tableMsgTypes.MODE_COMMAND.pktType, tableMsgTypes.MODE_COMMAND.subType, data, nil)

end

function setupReceiving(protocol, enable)

	debug("setupReceiving "..(protocol or "nil").." "..(enable or "nil"))
	local tabProtocols = {
		UndecodedReceiving = "VAR_UNDECODED_RECEIVING",
		ImagintronixReceiving = "VAR_IMAGINTRONIX_RECEIVING",
		ByronSXReceiving = "VAR_BYRONSX_RECEIVING",
		RSLReceiving = "VAR_RSL_RECEIVING",
		Lighting4Receiving = "VAR_LIGHTING4_RECEIVING",
		FineOffsetReceiving = "VAR_FINEOFFSET_RECEIVING",
		RubicsonReceiving = "VAR_RUBICSON_RECEIVING",
		AEReceiving = "VAR_AE_RECEIVING",
		BlindsT1Receiving = "VAR_BLINDST1_RECEIVING",
		BlindsT0Receiving = "VAR_BLINDST0_RECEIVING",
		ProGuardReceiving = "VAR_PROGUARD_RECEIVING",
		FS20Receiving = "VAR_FS20_RECEIVING",
		LaCrosseReceiving = "VAR_LACROSSE_RECEIVING",
		HidekiReceiving = "VAR_HIDEKI_RECEIVING",
		ADReceiving = "VAR_AD_RECEIVING",
		MertikReceiving = "VAR_MERTIK_RECEIVING",
		VisonicReceiving = "VAR_VISONIC_RECEIVING",
		ATIReceiving = "VAR_ATI_RECEIVING",
		OregonReceiving = "VAR_OREGON_RECEIVING",
		MeiantechReceiving = "VAR_MEIANTECH_RECEIVING",
		HEUReceiving = "VAR_HEU_RECEIVING",
		ACReceiving = "VAR_AC_RECEIVING",
		ARCReceiving = "VAR_ARC_RECEIVING",
		X10Receiving = "VAR_X10_RECEIVING",
		FunkbusReceiving = "VAR_FUNKBUS_RECEIVING",
		MCZReceiving = "VAR_MCZ_RECEIVING",
		HomeConfortReceiving = "VAR_HOMECONFORT_RECEIVING",
		KeelogReceiving = "VAR_KEELOQ_RECEIVING"
	}

	local valid = true

	if (protocol == "freqsel") then
		-- If switching away from 433.42 or 434.50 make sure protocols used
		-- at those frequencies are disabled.
		if (typeRFX == 0x54) then
			setVariable(THIS_DEVICE, tabVars[tabProtocols["FunkbusReceiving"]], "0")
		elseif (typeRFX == 0x5F) then
			setVariable(THIS_DEVICE, tabVars[tabProtocols["MCZReceiving"]], "0")
		end
		typeRFX = enable
	else
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
	end
	setMode()

end
