var RFX = {
	browserIE : undefined,
	sensorDataSortColumn: 0,
	deviceID: undefined,
	buttonBgColor : '#3295F8',
	tableTitleBgColor : '#025CB6',
	idTitleBgColor: 'white',
	idTextColor: 'black',
	nameTitleBgColor: undefined,
	nameTextColor: 'white',
	roomTitleBgColor: undefined,
	roomTextColor: 'white',
	typeTitleBgColor: undefined,
	typeTextColor: 'white',
	userData : undefined,

	SID : 'urn:upnp-rfxcom-com:serviceId:rfxtrx1',
	SID2 : 'upnp-rfxcom-com:serviceId:rfxtrx1',

	sensorDataSortFunction: [],

	categories : [
		[	"X10", "X10 lighting", true, false, true, false, true, false,
			false, undefined, undefined,
			true, 'A', 'P',
			false, undefined, undefined,
			true, 1, 16,
			false, undefined, undefined,
			false, undefined, undefined,
			"L1.0/"
		],
		[	"ARC", "ARC", true, false, true, true, false, false,
			false, undefined, undefined,
			true, 'A', 'P',
			false, undefined, undefined,
			true, 1, 16,
			false, undefined, undefined,
			false, undefined, undefined,
			"L1.1/"
		],
		[	"ELRO_AB400D", "ELRO AB400D, Flamingo, Sartano", true, false, false, false, false, false,
			false, undefined, undefined,
			true, 'A', 'P',
			false, undefined, undefined,
			true, 1, 64,
			false, undefined, undefined,
			false, undefined, undefined,
			"L1.2/"
		],
		[	"PHENIX", "Phenix", true, false, false, false, false, false,
			false, undefined, undefined,
			true, 'A', 'P',
			false, undefined, undefined,
			true, 1, 32,
			false, undefined, undefined,
			false, undefined, undefined,
			"L1.2/"
		],
		[	"WAVEMAN", "Waveman", true, false, false, false, false, false,
			false, undefined, undefined,
			true, 'A', 'P',
			false, undefined, undefined,
			true, 1, 16,
			false, undefined, undefined,
			false, undefined, undefined,
			"L1.3/"
		],
		[	"EMW200", "Chacon EMW200", true, false, false, false, false, false,
			false, undefined, undefined,
			true, 'A', 'C',
			false, undefined, undefined,
			true, 1, 4,
			false, undefined, undefined,
			false, undefined, undefined,
			"L1.4/"
		],
		[	"IMPULS", "Impuls", true, false, false, false, false, false,
			false, undefined, undefined,
			true, 'A', 'P',
			false, undefined, undefined,
			true, 1, 64,
			false, undefined, undefined,
			false, undefined, undefined,
			"L1.5/"
		],
		[	"RISINGSUN", "RisingSun", true, false, false, false, false, false,
			false, undefined, undefined,
			true, 'A', 'D',
			false, undefined, undefined,
			true, 1, 4,
			false, undefined, undefined,
			false, undefined, undefined,
			"L1.6/"
		],
		[	"PHILIPS_SBC", "Philips SBC", true, false, false, false, false, false,
			false, undefined, undefined,
			true, 'A', 'P',
			false, undefined, undefined,
			true, 1, 8,
			false, undefined, undefined,
			false, undefined, undefined,
			"L1.7/"
		],
		[	"ENERGENIE_ENER010", "Energenie ENER010", true, false, false, false, false, false,
			false, undefined, undefined,
			true, 'A', 'P',
			false, undefined, undefined,
			true, 1, 4,
			false, undefined, undefined,
			false, undefined, undefined,
			"L1.8/"
		],
		[	"ENERGENIE_5GANG", "Energenie 5 gang", true, false, false, false, false, false,
			false, undefined, undefined,
			true, 'A', 'P',
			false, undefined, undefined,
			true, 1, 10,
			false, undefined, undefined,
			false, undefined, undefined,
			"L1.9/"
		],
		[	"COCO", "COCO GDR2-2000R", true, false, false, false, false, false,
			false, undefined, undefined,
			true, 'A', 'D',
			false, undefined, undefined,
			true, 1, 4,
			false, undefined, undefined,
			false, undefined, undefined,
			"L1.A/"
		],
		[	"AC", "AC", true, true, true, true, true, true,
			true, 1, 0x3FFFFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			true, 1, 16,
			false, undefined, undefined,
			false, undefined, undefined,
			"L2.0/"
		],
		[	"HOMEEASY_EU", "HomeEasy EU", true, true, false, false, false, false,
			true, 1, 0x3FFFFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			true, 1, 16,
			false, undefined, undefined,
			false, undefined, undefined,
			"L2.1/"
		],
		[	"ANSLUT", "ANSLUT", true, true, false, false, false, false,
			true, 1, 0x3FFFFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			true, 1, 16,
			false, undefined, undefined,
			false, undefined, undefined,
			"L2.2/"
		],
		[	"IKEA_KOPPLA", "Ikea Koppla", true, false, false, false, false, false,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			true, 1, 16,
			true, 1, 10,
			"L3.0/"
		],
		[	"LIGHTWAVERF_SIEMENS", "LightwaveRF, Siemens", true, true, true, true, false, true,
			true, 1, 0xFFFFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			true, 1, 16,
			false, undefined, undefined,
			false, undefined, undefined,
			"L5.0/"
		],
		[	"EMW100", "GAO/Everflourish EMW100", true, false, false, false, false, false,
			true, 1, 0x3FFF,
			false, undefined, undefined,
			false, undefined, undefined,
			true, 1, 4,
			false, undefined, undefined,
			false, undefined, undefined,
			"L5.1/"
		],
		[	"BBSB", "Bye Bye Standby (new)", true, false, false, false, false, false,
			true, 1, 0x7FFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			true, 1, 6,
			false, undefined, undefined,
			false, undefined, undefined,
			"L5.2/"
		],
		[	"RSL2", "Conrad RSL2", true, false, false, false, false, false,
			true, 1, 0xFFFFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			true, 1, 16,
			false, undefined, undefined,
			false, undefined, undefined,
			"L5.4/"
		],
		[	"LIVOLO_1GANG", "Livolo (1 gang)", true, true, false, false, false, false,
			true, 1, 0xFFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			"L5.5/"
		],
		[	"LIVOLO_2GANG", "Livolo (2 gang)", true, false, false, false, false, false,
			true, 1, 0xFFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			"L5.5/"
		],
		[	"LIVOLO_3GANG", "Livolo (3 gang)", true, false, false, false, false, false,
			true, 1, 0xFFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			"L5.5/"
		],
		[	"BLYSS", "Blyss", true, false, true, true, false, false,
			true, 0, 0xFFFF,
			false, undefined, undefined,
			true, 'A', 'P',
			true, 1, 5,
			false, undefined, undefined,
			false, undefined, undefined,
			"L6.0/"
		],
		[	"HARRISON_CURTAIN", "Harrison Curtain", false, false, false, false, false, true,
			false, undefined, undefined,
			true, 'A', 'P',
			false, undefined, undefined,
			true, 1, 16,
			false, undefined, undefined,
			false, undefined, undefined,
			"C0/"
		],
		[	"ROLLERTROL", "RollerTrol", false, false, false, false, false, true,
			true, 1, 0xFFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			true, 0, 15,
			false, undefined, undefined,
			false, undefined, undefined,
			"B0/"
		],
		[	"HASTA_NEW", "Hasta (new)", false, false, false, false, false, true,
			true, 1, 0xFFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			true, 0, 15,
			false, undefined, undefined,
			false, undefined, undefined,
			"B0/"
		],
		[	"HASTA_OLD", "Hasta (old)", false, false, false, false, false, true,
			true, 1, 0xFFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			true, 0, 15,
			false, undefined, undefined,
			false, undefined, undefined,
			"B1/"
		],
		[	"A_OK_RF01", "A-OK RF01", false, false, false, false, false, true,
			true, 1, 0xFFFFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			"B2/"
		],
		[	"A_OK_AC114", "A-OK AC114", false, false, false, false, false, true,
			true, 1, 0xFFFFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			"B3/"
		],
		[	"RAEX", "Raex YR1326 T16 motor", false, false, false, false, false, true,
			true, 1, 0xFFFFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			"B4/"
		],
		[	"MEDIA_MOUNT", "Media Mount projector screen", false, false, false, false, false, true,
			true, 1, 0xFFFFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			false, undefined, undefined,
			"B5/"
		],
		[	"DC_RMF_YOODA", "DC106, YOODA, Rohrmotor24 RMF", false, false, false, false, false, true,
			true, 1, 0x0FFFFFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			true, 0, 15,
			false, undefined, undefined,
			false, undefined, undefined,
			"B6/"
		],
		[	"FOREST", "Forest", false, false, false, false, false, true,
			true, 1, 0x0FFFFFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			true, 0, 15,
			false, undefined, undefined,
			false, undefined, undefined,
			"B7/"
		],
		[	"RFY", "RFY", false, false, false, false, false, true,
			true, 1, 0x0FFFFF,
			false, undefined, undefined,
			false, undefined, undefined,
			true, 0, 4,
			false, undefined, undefined,
			false, undefined, undefined,
			"RFY0/"
		],
		[	"TEMP1", "Oregon THR128/138, THC138", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"T1/"	],
		[	"TEMP2", "Oregon THC238/268, ...", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"T2/"	],
		[	"TEMP3", "Oregon THWR800", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"T3/"	],
		[	"TEMP4", "Oregon RTHN318", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"T4/"	],
		[	"TEMP5", "La Crosse temp", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"T5/"	],
		[	"TEMP6", "Honeywell TS15C", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"T6/"	],
		[	"TEMP7", "Viking 02811, Proove TSS330/311346", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"T7/"	],
		[	"TEMP8", "La Crosse WS2300 (temp)", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"T8/"	],
		[	"TEMP9", "Rubicson temp", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"T9/"	],
		[	"TEMP10", "TFA 30.3133, 30.3160", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"T10/"	],
		[	"TEMP11", "Swimming pool WT0122", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"T10/"	],
		[	"HUM1", "La Crosse hum", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"H1/"	],
		[	"HUM2", "La Crosse WS2300 (hum)", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"H2/"	],
		[	"TEMP_HUM1", "Oregon THGN122, ...", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"TH1/"	],
		[	"TEMP_HUM2", "Oregon THGR810, THGN800", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"TH2/"	],
		[	"TEMP_HUM3", "Oregon RTGR328", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"TH3/"	],
		[	"TEMP_HUM4", "Oregon THGR328", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"TH4/"	],
		[	"TEMP_HUM5", "Oregon WTGR800 (TempHum)", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"TH5/"	],
		[	"TEMP_HUM6", "Oregon THGR918, THGRN228, ...", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"TH6/"	],
		[	"TEMP_HUM7", "TFA TS34C, Cresta", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"TH7/"	],
		[	"TEMP_HUM8", "UPM WT450H", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"TH8/"	],
		[	"TEMP_HUM9", "Viking 02035/02038, Proove TSS320/311501", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"TH9/"	],
		[	"TEMP_HUM10", "Rubicson TempHum", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"TH10/"	],
		[	"TEMP_HUM11", "Oregon EW109", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"TH11/"	],
		[	"TEMP_HUM12", "Imagintronix Soil sensor", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"TH12/"	],
		[	"TEMP_HUM13", "Alecto WS1700", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"TH13/"	],
		[	"TEMP_HUM14", "Alecto WS4500", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"TH14/"	],
		[	"BARO1", "Barometer", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"B1/"	],
		[	"TEMP_HUM_BARO1", "Oregon BTHR918, BTHGN129", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"THB1/"	],
		[	"TEMP_HUM_BARO2", "Oregon BTHR918N, BTHR968", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"THB2/"	],
		[	"RAIN1", "Oregon RGR126/682/918", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"R1/"	],
		[	"RAIN2", "Oregon PCR800", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"R2/"	],
		[	"RAIN3", "TFA rain", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"R3/"	],
		[	"RAIN4", "UPM RG700", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"R4/"	],
		[	"RAIN5", "La Crosse WS2300 (rain)", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"R5/"	],
		[	"RAIN7", "Alecto WS4500", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"R7/"	],
		[	"TEMP_RAIN1", "Alecto WS1200", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"TR1/"	],
		[	"WIND1", "Oregon WTGR800 (wind)", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"W1/"	],
		[	"WIND2", "Oregon WGR800", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"W2/"	],
		[	"WIND3", "Oregon STR918, WGR918", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"W3/"	],
		[	"WIND4", "TFA wind", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"W4/"	],
		[	"WIND5", "UPM WDS500", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"W5/"	],
		[	"WIND6", "La Crosse WS2300 (wind)", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"W6/"	],
		[	"WIND7", "Alecto WS4500", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"W7/"	],
		[	"UV1", "Oregon UVN128, UV138", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"U1/"	],
		[	"UV2", "Oregon UVN800", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"U2/"	],
		[	"UV3", "TFA UV", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"U3/"	],
		[	"WEIGHT1", "Oregon BWR101, BWR102", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"WT1/"	],
		[	"WEIGHT2", "Oregon GR101", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"WT2/"	],
		[	"MERTIK_G6R_H4T1", "Mertik Maxitrol G6R-H4T1", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"HT3.0/"	],
		[	"MERTIK_G6R_H4TB", "Mertik Maxitrol G6R-H4TB", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"HT3.1/"	],
		[	"OWL_CM113", "OWL CM113, Electrisave, ...", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"ELEC1/"	],
		[	"OWL_CM119_160", "OWL CM119/160", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"ELEC2/"	],
		[	"OWL_CM180", "OWL CM180", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"ELEC3/"	],
		[	"OWL_CM180I", "OWL CM180i", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"ELEC4/"	],
		[	"RFXSENSOR", "RFXSensor", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"RFXSENSOR0/"	],
		[	"RFXMETER", "RFXMeter", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"RFXMETER1/"	],
		[	"ATI_REMOTE_WONDER", "ATI Remote Wonder", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"RC0/"	],
		[	"ATI_REMOTE_WONDER_PLUS", "ATI Remote Wonder Plus", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"RC1/"	],
		[	"MEDION_REMOTE", "Medion Remote", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"RC2/"	],
		[	"X10_PC_REMOTE", "X10 PC remote", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"RC3/"	],
		[	"ATI_REMOTE_WONDER_II", "ATI Remote Wonder II", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"RC4/"	],
		[	"X10_MEIANTECH_POWERCODE_DS", "X10/Meiantech/PowerCode door", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"D/"	],
		[	"X10_MEIANTECH_POWERCODE_MS", "X10/Meiantech/PowerCode motion", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"M/"	],
		[	"X10_SECURITY_REMOTE", "X10 security remote", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"X10/SR/"	],
		[	"MEIANTECH_SECURITY_REMOTE", "Meiantech security remote", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"MEI/SR/"	],
		[	"KD101_SMOKE", "KD101 smoke detector", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"KD1/"	],
		[	"SA30_SMOKE", "Alecto SA30 smoke detector", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"S30/"	],
		[	"X10_SECURITY_LIGHT1", "X10 security light 1", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"X10/L1/"	],
		[	"X10_SECURITY_LIGHT2", "X10 security light 2", false, false, false, false, false, false,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			false, undefined, undefined, false, undefined, undefined, false, undefined, undefined,
			"X10/L2/"	]
	],

	deviceTypes : [
		[	"SWITCH_LIGHT", "Switch light", "urn:schemas-upnp-org:device:BinaryLight:1", "LS/", "urn:upnp-org:serviceId:SwitchPower1", "Status", true, "ON", "OFF", ""	],
		[	"DIMMABLE_LIGHT", "Dimmable light", "urn:schemas-upnp-org:device:DimmableLight:1", "DL/", "urn:upnp-org:serviceId:Dimming1", "LoadLevelStatus", false, "", "", "%"	],
		[	"MOTION_SENSOR", "Motion sensor", "urn:schemas-micasaverde-com:device:MotionSensor:1", "MS/", "urn:micasaverde-com:serviceId:SecuritySensor1", "Tripped", true, "Motion", "No motion", ""	],
		[	"DOOR_SENSOR", "Door sensor", "urn:schemas-micasaverde-com:device:DoorSensor:1", "DS/", "urn:micasaverde-com:serviceId:SecuritySensor1", "Tripped", true, "Opened", "Closed", ""	],
		[	"LIGHT_SENSOR", "Light sensor", "urn:schemas-micasaverde-com:device:LightSensor:1", "LL/", "urn:micasaverde-com:serviceId:LightSensor1", "CurrentLevel", false, "", "", "%"	],
		[	"WINDOW_COVERING", "Window covering", "urn:schemas-micasaverde-com:device:WindowCovering:1", "WC/", "urn:upnp-org:serviceId:Dimming1", "LoadLevelStatus", false, "", "", "%"	],
		[	"SMOKE_SENSOR", "Smoke sensor", "urn:schemas-micasaverde-com:device:SmokeSensor:1", "SS/", "urn:micasaverde-com:serviceId:SecuritySensor1", "Tripped", true, "Smoke", "No smoke", ""	],
		[	"TEMPERATURE_SENSOR", "Temperature sensor", "urn:schemas-micasaverde-com:device:TemperatureSensor:1", "TS/", "urn:upnp-org:serviceId:TemperatureSensor1", "CurrentTemperature", false, "", "", ""	],
		[	"HUMIDITY_SENSOR", "Humidity sensor", "urn:schemas-micasaverde-com:device:HumiditySensor:1", "HS/", "urn:micasaverde-com:serviceId:HumiditySensor1", "CurrentLevel", false, "", "", "%"	],
		[	"BAROMETER_SENSOR", "Barometric sensor", "urn:schemas-micasaverde-com:device:BarometerSensor:1", "BS/", "urn:upnp-org:serviceId:BarometerSensor1", "CurrentPressure", false, "", "", "hPa"	],
		[	"WIND_SENSOR", "Wind sensor", "urn:schemas-micasaverde-com:device:WindSensor:1", "WS/", "urn:upnp-org:serviceId:WindSensor1", "AvgSpeed", false, "", "", ""	],
		[	"RAIN_SENSOR", "Rain sensor", "urn:schemas-micasaverde-com:device:RainSensor:1", "RS/", "urn:upnp-org:serviceId:RainSensor1", "CurrentTRain", false, "", "", "mm"	],
		[	"UV_SENSOR", "UV sensor", "urn:schemas-micasaverde-com:device:UvSensor:1", "UV/", "urn:upnp-org:serviceId:UvSensor1", "CurrentLevel", false, "", "", ""	],
		[	"WEIGHT_SENSOR", "Weight sensor", "urn:schemas-micasaverde-com:device:ScaleSensor:1", "WT/", "urn:micasaverde-com:serviceId:ScaleSensor1", "Weight", false, "", "", "kg"	],
		[	"POWER_SENSOR", "Power sensor", "urn:schemas-micasaverde-com:device:PowerMeter:1", "PM/", "urn:micasaverde-com:serviceId:EnergyMetering1", "KWH", false, "", "", "kWh"	],
		[	"RFXMETER", "RFXmeter", "urn:casa-delanghe-com:device:RFXMeter:1", "RM/", "urn:delanghe-com:serviceId:RFXMetering1", "Pulsen", false, "", "", ""	],
		[	"SECURITY_REMOTE", "Security remote", "urn:rfxcom-com:device:SecurityRemote:1", "SR/", "urn:micasaverde-com:serviceId:AlarmPartition2", "DetailedArmMode", false, "", "", ""	],
		[	"X10_REMOTE", "Group control", "urn:rfxcom-com:device:X10ChaconRemote:1", "RC/", "", "", false, "", "", ""	],
		[	"LWRF_REMOTE", "Group control", "urn:rfxcom-com:device:LWRFRemote:1", "RC/", "", "", false, "", "", ""	],
		[	"ATI_REMOTE", "Remote control", "urn:rfxcom-com:device:ATIRemote:1", "RC/", "", "", false, "", "", ""	],
		[	"HEATER", "Heater", "urn:schemas-upnp-org:device:Heater:1", "HT/", "urn:upnp-org:serviceId:HVAC_UserOperatingMode1", "ModeStatus", false, "", "", ""	]
	],

	sensorDeviceTypes : [
		[	"TEMPERATURE_SENSOR", "Temperature sensor", "urn:schemas-micasaverde-com:device:TemperatureSensor:1", "TS/", "urn:upnp-org:serviceId:TemperatureSensor1", "CurrentTemperature", "MaxTemp", "MinTemp", "MaxTemp24hr", "MinTemp24hr", "MaxMinTemps", ""	],
		[	"HUMIDITY_SENSOR", "Humidity sensor", "urn:schemas-micasaverde-com:device:HumiditySensor:1", "HS/", "urn:micasaverde-com:serviceId:HumiditySensor1", "CurrentLevel", "MaxHum", "MinHum", "MaxHum24hr", "MinHum24hr", "MaxMinHum", " %"	]
	],

	commands : [
		[ "L5.1/", "LEARN", "Learn" ],
		[ "L3.0/", "PROGRAM", "Program" ],
		[ "C0/", "PROGRAM", "Program" ],
		[ "B0/", "CONFIRM_PAIR", "Confirm pair" ],
		[ "B1/", "CONFIRM_PAIR", "Confirm pair" ],
		[ "B2/", "CONFIRM_PAIR", "Confirm pair" ],
		[ "B3/", "CONFIRM_PAIR", "Confirm pair" ],
		[ "B4/", "CONFIRM_PAIR", "Confirm pair" ],
		[ "B6/", "CONFIRM_PAIR", "Confirm pair" ],
		[ "B7/", "CONFIRM_PAIR", "Confirm pair" ],
		[ "RFY0/", "PROGRAM", "Program" ],
		[ "RFY0/", "LOWER_LIMIT", "Set lower limit" ],
		[ "RFY0/", "UPPER_LIMIT", "Set upper limit" ],
		[ "RFY0/", "VENETIAN_US_ANGLE_PLUS", "Change angle + (Venetian US)" ],
		[ "RFY0/", "VENETIAN_US_ANGLE_MINUS", "Change angle - (Venetian US)" ],
		[ "RFY0/", "VENETIAN_EU_ANGLE_PLUS", "Change angle + (Venetian EU)" ],
		[ "RFY0/", "VENETIAN_EU_ANGLE_MINUS", "Change angle - (Venetian EU)" ],
		[ "RFY0/", "ENABLE_DETECTOR", "Enable sun/wind detector" ],
		[ "RFY0/", "DISABLE_DETECTOR", "Disable sun detector" ]
	]

};


function RFX_showNewDevice(device)
{
	RFX_checkSettings(device);
	var html = '';

	html += '<table cellspacing="10">';
	html += '<tr>';
	html += '<td>Category:</td>';
	html += '<td>';
	html += '<select id="category" onChange="RFX_selectCategory();">';
	for (i=0; i<RFX.categories.length; i++) {
		if (RFX.categories[i][2] || RFX.categories[i][3] || RFX.categories[i][4]
			|| RFX.categories[i][5] || RFX.categories[i][6] || RFX.categories[i][7]) {
			html += '<option';
			if (i == 0) {
				html += ' selected';
			}
			html += ' value="' + RFX.categories[i][0] + '">' + RFX.categories[i][1] + '</option>';
		}
	}
	html += '</select>';
	html += '</td>';
	html += '</tr>';
	html += '<tr><td>Device type:</td><td><select id="deviceType"/></td></tr>';
	html += '<tr><td>Device name:</td><td><input id="name" type="text" style="width: 250px"/></td></tr>';
	html += '</tr><td id="labelParam1"/><td id="valueParam1"/></tr>';
	html += '</tr><td id="labelParam2"/><td id="valueParam2"/></tr>';
	html += '</tr><td id="labelParam3"/><td id="valueParam3"/></tr>';
	html += '<tr><td colspan=2>';
	html += '<button id="create" type="button" style="background-color: ' + RFX.buttonBgColor + '; color: white; height: 25px; width: 75px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="RFX_createDevice('+device+');">Create</button>';
	html += '<label id="msg" style="margin-left: 10px"/>';
	html += '</td></tr>';
	html += '</table>';

	//html += '<p id="debug">';

	set_panel_html(html);

	RFX_selectCategory();
}

function RFX_showManagedDevices(device)
{
	RFX_checkSettings(device);

	var autoCreate = get_device_state(device, RFX.SID2, "AutoCreate", 1);

	var html = '';

	html += '<style>'
	html += '#devicesTable, th, td { padding:1px 3px; text-align: center; }'
	html += '</style>'

	html += '<style>'
	html += '#otherTable, th, td { padding:1px 3px; text-align: left; }'
	html += '</style>'

	html += '<DIV id="devicesTable">'
	html += '</DIV>'

	html += '<DIV>'
	html += '<button type="button" style="margin-right: 10px; background-color: ' + RFX.buttonBgColor + '; color: white; height: 25px; width: 110px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="RFX_updateDevicesTable('+device+');">Refresh table</button>';
	html += '<select id="filterDevices" onChange="RFX_updateDevicesTable('+device+');"><option selected value="ALL">All</option></select>';
	html += '<button type="button" style="margin-left: 10px; background-color: ' + RFX.buttonBgColor + '; color: white; height: 25px; width: 90px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="RFX_selectAllDevices(true);">Select All</button>';
	html += '<button type="button" style="margin-left: 10px; background-color: ' + RFX.buttonBgColor + '; color: white; height: 25px; width: 100px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="RFX_selectAllDevices(false);">Unselect All</button>';
	html += '</DIV>'

	html += '<table id="otherTable" cellspacing="10">';
	html += '<tr><td colspan=2><label id="msg2"/></td></tr>';
	html += '<tr><td>Device ID:</td><td id="selDeviceID"/></tr>';
	html += '<tr><td>Battery level:</td><td id="battery"/></tr>';
	html += '<tr><td>Device type:</td><td id="curDeviceType"/></tr>';
	html += '<tr><td>New name:</td><td><input id="newName" type="text" style="width: 250px"/></td></tr>';
	html += '<tr><td>New device type:</td><td><select id="newDeviceType"/>';
	html += '<button id="changeType" type="button" style="margin-left: 10px; background-color: ' + RFX.buttonBgColor + '; color: white; height: 25px; width: 75px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="RFX_changeDeviceType('+device+');">Change</button>';
	html += '</td></tr>';
	html += '<tr><td>Command:</td><td><select id="commands"/>';
	html += '<button id="runCommand" type="button" style="margin-left: 10px; background-color: ' + RFX.buttonBgColor + '; color: white; height: 25px; width: 75px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="RFX_runCommand('+device+');">Run</button>';
	html += '</td></tr>';
	html += '<tr><td colspan=2>';
	html += '<button id="delete1" type="button" style="background-color: ' + RFX.buttonBgColor + '; color: white; height: 25px; width: 175px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="RFX_deleteDevices('+device+', false);">Delete selected devices</button>';
	html += '<button id="delete2" type="button" style="margin-left: 10px; background-color: ' + RFX.buttonBgColor + '; color: white; height: 25px; width: 370px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="RFX_deleteDevices('+device+', true);">Delete selected devices & prevent automatic creation</button>';
	html += '</td></tr>';
	html += '<tr>';
	html += '<td>Automatic creation:</td>';
	html += '<td>';
	html += '<input name="autoCreate" id="autoCreateOn" type="radio" onchange="RFX_setAutoCreate('+device+');"';
	if (autoCreate == '1') {
		html += ' checked';
	}
	html += '>ON';
	html += '<input name="autoCreate" id="autoCreateOff" type="radio" onchange="RFX_setAutoCreate('+device+');"';
	if (autoCreate == '0') {
		html += ' checked';
	}
	html += '>OFF';
	html += '</td>';
	html += '</tr>';
	html += '<tr><td>Discarded devices (auto-create):</td><td id="dicardedDevices"></td></tr>';
	html += '</table>';

	//html += '<p id="debug">';

	set_panel_html(html);

	RFX_updateDevicesTable(device);
}

function RFX_updateDevicesTable(device)
{
	var html = '<table border="1">';

	html += '<tr style="background-color: '+ RFX.tableTitleBgColor + '; color: white">';
	html += '<th></td>';
	html += '<th>ID</td>';
	html += '<th>Name</td>';
	html += '<th>Room</td>';
	html += '<th>Type</td>';
	html += '<th>State</td>';
	html += '<th>Battery</td>';
	html += '</tr>';

	var selectedCategory = '';
	if (jQuery('#filterDevices option:selected').index() >= 0) {
		selectedCategory = jQuery('#filterDevices').val();
	}

	var categories = new Array();
	var types = new Array();
	var rooms = new Array();

	if (typeof api !== 'undefined') {
		RFX.userData = api.getUserData();
	}
	else {
		RFX.userData = jsonp.ud;
	}

	var nb=0;
	for (i=0; i<RFX.userData.devices.length; i++) {
		if (RFX.userData.devices[i].id_parent == device) {
			var room = 'NONE';
			for (j=0; j<RFX.userData.rooms.length; j++) {
				if (RFX.userData.rooms[j].id == RFX.userData.devices[i].room) {
					room = RFX.userData.rooms[j].name;
					break;
				}
			}
			if (rooms.indexOf(room) < 0) {
				rooms.push(room);
			}
			var type = '';
			var type2 = '';
			var idxType = -1;
			for (j=0; j<RFX.deviceTypes.length; j++) {
				if (RFX.deviceTypes[j][2] == RFX.userData.devices[i].device_type) {
					idxType = j;
					type = RFX.deviceTypes[idxType][1];
					type2 = RFX.deviceTypes[idxType][0];
					if (types.indexOf(type2) < 0) {
						types.push(type2);
					}
					break;
				}
			}
			var state = '';
			if (idxType >= 0 && RFX.deviceTypes[idxType][4] != "" && RFX.deviceTypes[idxType][5] != "") {
				var value = get_device_state(RFX.userData.devices[i].id, RFX.deviceTypes[idxType][4], RFX.deviceTypes[idxType][5], 1);
				if (value != undefined) {
					if (RFX.deviceTypes[idxType][6]) {
						if (value == "1") {
							state = RFX.deviceTypes[idxType][7];
						}
						else if (value == "0") {
							state = RFX.deviceTypes[idxType][8];
						}
					}
					else {
						state = value;
					}
				}

				if (state != "" && RFX.deviceTypes[idxType][0] == 'TEMPERATURE_SENSOR') {
					var unit = '&deg;C';
					if (get_device_state(device, RFX.SID2, "CelciusTemp", 1) == '0') {
						unit = '&deg;F';
					}
					state += ' ' + unit;
				}
				else if (state != "" && RFX.deviceTypes[idxType][0] == 'WIND_SENSOR') {
					var unit = 'km/h';
					if (get_device_state(device, RFX.SID2, "KmhSpeed", 1) == '0') {
						unit = 'mph';
					}
					state += ' ' + unit;
				}
				else if (state != "" && RFX.deviceTypes[idxType][9] != "") {
					state += ' ' + RFX.deviceTypes[idxType][9];
				}
			}
			var category = '';
			var category2 = '';
			for (j=0; j<RFX.categories.length; j++) {
				if (RFX.categories[j][26] == RFX.userData.devices[i].altid.substr(3, RFX.categories[j][26].length)) {
					category = RFX.categories[j][1];
					category2 = RFX.categories[j][0];
					if (categories.indexOf(category2) < 0) {
						categories.push(category2);
					}
					break;
				}
			}
			if (category == '' && category2 == '' && categories.indexOf('UNDEFINED') < 0) {
				categories.push('UNDEFINED')
			}
			if (selectedCategory == 'ALL'
				|| (selectedCategory == 'C=UNDEFINED' &&  category2 == '')
				|| (selectedCategory == ('C='+category2))
				|| (selectedCategory == ('T='+type2))
				|| (selectedCategory == 'R=NONE' &&  room == '')
				|| (selectedCategory == ('R='+room))) {
				var batteryLevel = get_device_state(RFX.userData.devices[i].id, 'urn:micasaverde-com:serviceId:HaDevice1', "BatteryLevel", 1);
				if (batteryLevel == undefined) {
					batteryLevel = '';
				}
				else {
					batteryLevel += ' %';
				}
				html += '<tr align="center">';
				html += '<td><input id="SelectDevice' + nb + '" type="checkbox" value="' + RFX.userData.devices[i].id + '" onchange="RFX_selectDevices();"></td>';
				html += '<td onclick="RFX_selectLine(' + nb + ');">' + RFX.userData.devices[i].id + '</td>';
				html += '<td onclick="RFX_selectLine(' + nb + ');">' + RFX.userData.devices[i].name + '</td>';
				html += '<td onclick="RFX_selectLine(' + nb + ');">' + room + '</td>';
				html += '<td onclick="RFX_selectLine(' + nb + ');">' + type + '</td>';
				html += '<td onclick="RFX_selectLine(' + nb + ');">' + state + '</td>';
				html += '<td onclick="RFX_selectLine(' + nb + ');">' + batteryLevel + '</td>';
				html += '</tr>';
				nb++;
			}
		}
	}

	html += '</table>';

	jQuery('#devicesTable').html(html);

	var validSelection = false;
	var undefCategory = false;
	var undefRoom = false;
	html = '<option value="ALL"';
	if (selectedCategory == 'ALL') {
		html += ' selected';
		validSelection = true;
	}
	html += '>All</option>';
	html += '<option disabled>-------- Categories --------</option>';
	for (i=0; i<categories.length; i++) {
		if (categories[i] == 'UNDEFINED') {
			undefCategory = true;
		}
		else {
			html += '<option value="C=' + categories[i] + '"';
			if (selectedCategory == ('C='+categories[i])) {
				html += ' selected';
				validSelection = true;
			}
			var category = categories[i];
			for (j=0; j<RFX.categories.length; j++) {
				if (RFX.categories[j][0] == categories[i]) {
					category = RFX.categories[j][1];
					break;
				}
			}
			html += '>' + category + '</option>';
		}
	}
	if (undefCategory) {
		html += '<option value="C=UNDEFINED"';
		if (selectedCategory == 'C=UNDEFINED') {
			html += ' selected';
			validSelection = true;
		}
		html += '>Undefined category</option>';
	}
	html += '<option disabled>---------- Types ----------</option>';
	for (i=0; i<types.length; i++) {
		html += '<option value="T=' + types[i] + '"';
		if (selectedCategory == ('T='+types[i])) {
			html += ' selected';
			validSelection = true;
		}
		var type = types[i];
		for (j=0; j<RFX.deviceTypes.length; j++) {
			if (RFX.deviceTypes[j][0] == types[i]) {
				type = RFX.deviceTypes[j][1];
				break;
			}
		}
		html += '>' + type + '</option>';
	}
	html += '<option disabled>---------- Rooms ----------</option>';
	rooms.sort();
	for (i=0; i<rooms.length; i++) {
		if (rooms[i] == 'NONE') {
			undefRoom = true;
		}
		else {
			html += '<option value="R=' + rooms[i] + '"';
			if (selectedCategory == ('R='+rooms[i])) {
				html += ' selected';
				validSelection = true;
			}
			html += '>' + rooms[i] + '</option>';
		}
	}
	if (undefRoom) {
		html += '<option value="R=NONE"';
		if (selectedCategory == 'R=NONE') {
			html += ' selected';
			validSelection = true;
		}
		html += '>No room</option>';
	}
	jQuery('#filterDevices').html(html);
	if (!validSelection) {
		jQuery("#filterDevices option[value='ALL']").attr('selected', 'selected');
		RFX_updateDevicesTable(device);
		return;
	}

	RFX_selectDevices();

	var dicardedDevices = get_device_state(device, RFX.SID2, "DisabledDevices", 1);
	if (dicardedDevices == undefined || dicardedDevices == '') {
		dicardedDevices = 'none';
	}
	else {
		dicardedDevices = dicardedDevices.replace(/,/g, ' ');
	}
	jQuery('#dicardedDevices').html(dicardedDevices);
}

function RFX_setSortColumn(column)
{
	if((RFX.sensorDataSortColumn != column)&& (column < 4)){
		RFX.sensorDataSortColumn = column;
		RFX.idTitleBgColor = RFX.tableTitleBgColor;
		RFX.idTextColor = 'white';
		RFX.nameTitleBgColor = RFX.tableTitleBgColor;
		RFX.nameTextColor = 'white';
		RFX.roomTitleBgColor = RFX.tableTitleBgColor;
		RFX.roomTextColor = 'white';
		RFX.typeTitleBgColor = RFX.tableTitleBgColor;
		RFX.typeTextColor = 'white';
		switch(column){
			case 0:
				RFX.idTextColor = 'black';
				RFX.idTitleBgColor = 'white';
				break;
			case 1:
				RFX.nameTextColor = 'black';
				RFX.nameTitleBgColor = 'white';
				break;
			case 2:
				RFX.roomTextColor = 'black';
				RFX.roomTitleBgColor = 'white';
				break;
			case 3:
				RFX.typeTextColor = 'black';
				RFX.typeTitleBgColor = 'white';
				break;
			default:
				break;
		}
		RFX_updateSensorData(RFX.deviceID);
	}
}

function RFX_sortByName(rowSortData)
{
	rowSortData.sort (function(a,b){
		var x = a.name.toLowerCase();
		var y = b.name.toLowerCase();
		if (x < y) {return -1;}
		if (x > y) {return 1;}
		return 0;
	});
}

function RFX_sortByRoom(rowSortData)
{
	rowSortData.sort (function(a,b){
		var x = a.room.toLowerCase();
		var y = b.room.toLowerCase();
		if (x < y) {return -1;}
		if (x > y) {return 1;}
		return 0;
	});
}

function RFX_sortByType(rowSortData)
{
	rowSortData.sort (function(a,b){
		var x = a.type.toLowerCase();
		var y = b.type.toLowerCase();
		if (x < y) {return -1;}
		if (x > y) {return 1;}
		return 0;
	});
}

function RFX_showSensorData(device)
{
	RFX_checkSettings(device);
	var html = '';

	html += '<style>';
	html += '#sensorDataTable, th, td { padding:1px 3px; text-align: center; }';
	html += '</style>';

	html += 'Temperature and Humidity Sensor Data';
	html += '<p><DIV id="sensorDataTable"/></p>';

	html += '<DIV>';
	html += '<button type="button" style="margin-right: 10px; background-color: ' + RFX.buttonBgColor + '; color: white; height: 25px; width: 110px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="RFX_updateSensorData('+device+');">Refresh table</button>';
	html += '</DIV>';
	html += '<p/>';

	set_panel_html(html);

	RFX_updateSensorData(device);
}

function RFX_pad(num, size)
{
	return([1e10] + num).slice(-size);
}

function RFX_resetSensorData( idx )
{
	if(idx != undefined && idx >= 0) {
		var type = RFX.userData.devices[idx].device_type;
		var device = RFX.userData.devices[idx].id_parent;
		if(type != undefined && device != undefined) {
			var idxType = -1;
			for (j=0; j<RFX.sensorDeviceTypes.length; j++) {
				if (RFX.sensorDeviceTypes[j][2] == type) {
					idxType = j;
					break;
				}
			}
			if(idxType >= 0) {
				var currentValue = get_device_state(RFX.userData.devices[idx].id, RFX.sensorDeviceTypes[idxType][4], RFX.sensorDeviceTypes[idxType][5], 1);
				if (currentValue == undefined)
					return;
				set_device_state(RFX.userData.devices[idx].id, RFX.sensorDeviceTypes[idxType][4], RFX.sensorDeviceTypes[idxType][6], currentValue, 1);
				set_device_state(RFX.userData.devices[idx].id, RFX.sensorDeviceTypes[idxType][4], RFX.sensorDeviceTypes[idxType][7], currentValue, 1);
				set_device_state(RFX.userData.devices[idx].id, RFX.sensorDeviceTypes[idxType][4], RFX.sensorDeviceTypes[idxType][8], currentValue, 1);
				set_device_state(RFX.userData.devices[idx].id, RFX.sensorDeviceTypes[idxType][4], RFX.sensorDeviceTypes[idxType][9], currentValue, 1);
				set_device_state(RFX.userData.devices[idx].id, RFX.sensorDeviceTypes[idxType][4], RFX.sensorDeviceTypes[idxType][10], undefined, 1);
				setTimeout(function(){ RFX_updateSensorData(device); }, 2000);
			}
		}
	}
}

function RFX_updateSensorData(device)
{
	var sortingArray = [];
	var rowDataArray = [];
	var tableRowSortData = [];
	var date = new Date();
	var hours = 0;
	var min = 0;
	var sec = 0;
	var elapsedTime = 0;
	var dateValue = Math.floor(date.getTime()/1000);

	var html = '<table border="1" >';
	html += '<th onclick="RFX_setSortColumn(0);" style="background-color:'+ RFX.idTitleBgColor + '; color:'+ RFX.idTextColor + '">ID</th>';
	html += '<th onclick="RFX_setSortColumn(1);" style="background-color:'+ RFX.nameTitleBgColor + '; color:'+ RFX.nameTextColor + '">Name</th>';
	html += '<th onclick="RFX_setSortColumn(2);" style="background-color:'+ RFX.roomTitleBgColor + '; color:'+ RFX.roomTextColor + '">Room</th>';
	html += '<th onclick="RFX_setSortColumn(3);" style="background-color:'+ RFX.typeTitleBgColor + '; color:'+ RFX.typeTextColor + '">Type</th>';
	html += '<th style="background-color:'+ RFX.tableTitleBgColor + '; color:white">Now</th>';
	html += '<th style="background-color:'+ RFX.tableTitleBgColor + '; color:white">Maximum</th>';
	html += '<th style="background-color:'+ RFX.tableTitleBgColor + '; color:white">Max 24Hr</th>';
	html += '<th style="background-color:'+ RFX.tableTitleBgColor + '; color:white">Minimum</th>';
	html += '<th style="background-color:'+ RFX.tableTitleBgColor + '; color:white">Min 24hr</th>';
	html += '<th style="background-color:'+ RFX.tableTitleBgColor + '; color:white">Signal</th>';
	html += '<th style="background-color:'+ RFX.tableTitleBgColor + '; color:white">Battery</th>';
	html += '<th style="background-color:'+ RFX.tableTitleBgColor + '; color:white">Age</th>';
	html += '<th style="background-color:'+ RFX.tableTitleBgColor + '; color:white">Reset</th>';
	html += '</tr>';


	if (typeof api !== 'undefined') {
		RFX.userData = api.getUserData();
	}
	else {
		RFX.userData = jsonp.ud;
	}

	for (i=0; i<RFX.userData.devices.length; i++) {
		if (RFX.userData.devices[i].id_parent == device) {
			var type = RFX.userData.devices[i].device_type;
			var idxType = -1;
			for (j=0; j<RFX.sensorDeviceTypes.length; j++) {
				if (RFX.sensorDeviceTypes[j][2] == type) {
					idxType = j;
					break;
				}
			}
			if(idxType < 0)
				continue;

			type = RFX.sensorDeviceTypes[idxType][1];
			var room = 'NONE';
			for (j=0; j<RFX.userData.rooms.length; j++) {
				if (RFX.userData.rooms[j].id == RFX.userData.devices[i].room) {
					room = RFX.userData.rooms[j].name;
					break;
				}
			}

			var currentValue = get_device_state(RFX.userData.devices[i].id, RFX.sensorDeviceTypes[idxType][4], RFX.sensorDeviceTypes[idxType][5], 1);
			if (currentValue != undefined) {
				currentValue += RFX.sensorDeviceTypes[idxType][11];
			}
			else continue;

			var maxValue = get_device_state(RFX.userData.devices[i].id, RFX.sensorDeviceTypes[idxType][4], RFX.sensorDeviceTypes[idxType][6], 1);
			if (maxValue != undefined) {
				maxValue += RFX.sensorDeviceTypes[idxType][11];
			}

			var minValue = get_device_state(RFX.userData.devices[i].id, RFX.sensorDeviceTypes[idxType][4], RFX.sensorDeviceTypes[idxType][7], 1);
			if (minValue != undefined) {
				minValue += RFX.sensorDeviceTypes[idxType][11];
			}

			var maxValue24hr = get_device_state(RFX.userData.devices[i].id, RFX.sensorDeviceTypes[idxType][4], RFX.sensorDeviceTypes[idxType][8], 1);
			if (maxValue24hr != undefined) {
				maxValue24hr += RFX.sensorDeviceTypes[idxType][11];
			}

			var minValue24hr = get_device_state(RFX.userData.devices[i].id, RFX.sensorDeviceTypes[idxType][4], RFX.sensorDeviceTypes[idxType][9], 1);
			if (minValue24hr != undefined) {
				minValue24hr += RFX.sensorDeviceTypes[idxType][11];
			}

			var commStrength = get_device_state(RFX.userData.devices[i].id, 'urn:micasaverde-com:serviceId:HaDevice1', 'CommStrength', 1);
			if (commStrength != undefined) {
				commStrength = -(15 - commStrength)*8;
				commStrength += 'dBm';
			}

			var batteryLevel = get_device_state(RFX.userData.devices[i].id, 'urn:micasaverde-com:serviceId:HaDevice1', "BatteryLevel", 1);
			if (batteryLevel == undefined) {
				batteryLevel = '';
			}
			else {
				batteryLevel += ' %';
			}
			var lastUpdate = get_device_state(RFX.userData.devices[i].id, 'urn:micasaverde-com:serviceId:HaDevice1', "BatteryDate", 1);
			if (lastUpdate != undefined) {
				elapsedTime = dateValue - lastUpdate;
				hours = Math.floor(elapsedTime/3600);
				min = Math.floor(elapsedTime/60) - (hours * 60);
				sec = elapsedTime  - (hours * 3600) - (min * 60);
			}
			else {
				hours = 0;
				min = 0;
				sec = 0;
			}
			tableRowSortData = {index:sortingArray.length, name:RFX.userData.devices[i].name, room:room,type:type};
			sortingArray.push(tableRowSortData);
			var rowhtml = '';
			rowhtml += '<tr align="center">';
			rowhtml += '<td>' + RFX.userData.devices[i].id + '</td>';
			rowhtml += '<td>' + RFX.userData.devices[i].name + '</td>';
			rowhtml += '<td>' + room + '</td>';
			rowhtml += '<td>' + type + '</td>';
			rowhtml += '<td>' + currentValue + '</td>';
			rowhtml += '<td>' + maxValue + '</td>';
			rowhtml += '<td>' + maxValue24hr + '</td>';
			rowhtml += '<td>' + minValue + '</td>';
			rowhtml += '<td>' + minValue24hr + '</td>';
			rowhtml += '<td>' + commStrength + '</td>';
			rowhtml += '<td>' + batteryLevel + '</td>';
			rowhtml += '<td>' + RFX_pad(hours,2) + ':' + RFX_pad(min,2) + ':' + RFX_pad(sec,2) + '</td>';
			rowhtml += '<td><button type="button" style="height: 20px; width: 90%; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="RFX_resetSensorData(' + i +');"> </button></td>';
			rowhtml += '</tr>';

			rowDataArray.push(rowhtml);

			if(RFX.sensorDataSortColumn > 0) {
				RFX.sensorDataSortFunction[RFX.sensorDataSortColumn-1](sortingArray);
			}
		}
	}

	for (i=0; i<rowDataArray.length; i++) {
		html += rowDataArray[sortingArray[i].index];
	}

	html += '</table>';

	jQuery('#sensorDataTable').html(html);
}

function RFX_showSettings(device)
{
	RFX_checkSettings(device);

	var temp_unit = get_device_state(device, RFX.SID2, "CelciusTemp", 1);
	var speed_unit = get_device_state(device, RFX.SID2, "KmhSpeed", 1);
	var voltage = get_device_state(device, RFX.SID2, "Voltage", 1);
	if (voltage == undefined) {
		voltage = '';
	}
	var debugLogs = get_device_state(device, RFX.SID2, "DebugLogs", 1);

	var html = '';

	html += '<table cellspacing="10">';
	html += '<tr>';
	html += '<td>Temperature unit:</td>';
	html += '<td>';
	html += '<input name="tempUnit" id="tempUnit1" type="radio" onchange="RFX_setTempUnit('+device+');"';
	if (temp_unit == '1') {
		html += ' checked';
	}
	html += '>Celcius';
	html += '<input name="tempUnit" id="tempUnit2" type="radio" onchange="RFX_setTempUnit('+device+');"';
	if (temp_unit == '0') {
		html += ' checked';
	}
	html += '>Fahrenheit';
	html += '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>Speed unit:</td>';
	html += '<td>';
	html += '<input name="speedUnit" id="speedUnit1" type="radio" onchange="RFX_setSpeedUnit('+device+');"';
	if (speed_unit == '1') {
		html += ' checked';
	}
	html += '>km/h';
	html += '<input name="speedUnit" id="speedUnit2" type="radio" onchange="RFX_setSpeedUnit('+device+');"';
	if (speed_unit == '0') {
		html += ' checked';
	}
	html += '>mph';
	html += '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>Voltage (Power calculation):</td>';
	html += '<td>';
	html += '<input id="voltage" type="text" size="3" maxlength="3" value="' + voltage + '"/>';
	html += '<button type="button" style="margin-left: 10px; background-color: ' + RFX.buttonBgColor + '; color: white; height: 25px; width: 50px; -moz-border-radius: 6px; -webkit-border-radius: 6px; -khtml-border-radius: 6px; border-radius: 6px" onclick="RFX_setVoltage('+device+');">Set</button>';
	html += '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>Debug logs:</td>';
	html += '<td>';
	html += '<input name="debugLogs" id="debugLogsOn" type="radio" onchange="RFX_setDebugLogs('+device+');"';
	if (debugLogs == '1') {
		html += ' checked';
	}
	html += '>ON';
	html += '<input name="debugLogs" id="debugLogsOff" type="radio" onchange="RFX_setDebugLogs('+device+');"';
	if (debugLogs == '0') {
		html += ' checked';
	}
	html += '>OFF';
	html += '</td>';
	html += '</tr>';
	html += '</table>';

	//html += '<p id="debug">';

	set_panel_html(html);
}

function RFX_showHelp(device)
{
	RFX_checkSettings(device);

	var version = get_device_state(device, RFX.SID2, "PluginVersion", 1);
	if (version == undefined) {
		version = '';
	}
	var firmware = get_device_state(device, RFX.SID2, "FirmwareVersion", 1);
	if (firmware == undefined) {
		firmware = '';
	}
	var firmtype = get_device_state(device, RFX.SID2, "FirmwareType", 1);
	if (firmtype == undefined) {
		firmtype = '';
	}
	var hardware = get_device_state(device, RFX.SID2, "HardwareVersion", 1);
	if (hardware == undefined) {
		hardware = '';
	}

	var html = '';

	html += '<table cellspacing="10">';
	html += '<tr>';
	html += '<td>Plugin version:</td>';
	html += '<td>' + version + '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>RFXtrx firmware:</td>';
	html += '<td>' + firmware + '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>RFXtrx firmware type:</td>';
	html += '<td>' + firmtype + '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>RFXtrx hardware:</td>';
	html += '<td>' + hardware + '</td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>Wiki:</td>';
	html += '<td><a href="http://code.mios.com/trac/mios_rfxtrx#">link</a></td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>Micasaverde Forum:</td>';
	html += '<td><a href="http://forum.micasaverde.com/index.php/board,45.0.html">link</a></td>';
	html += '</tr>';
	html += '<tr>';
	html += '<td>Forum Toute La Domotique:</td>';
	html += '<td><a href="http://touteladomotique.com/forum/viewtopic.php?f=48&t=7218">link</a></td>';
	html += '</tr>';
	html += '</table>';

	set_panel_html(html);
}

function RFX_selectCategory()
{
    var html = '';
    var html2 = '';
	var idx = jQuery('#category option:selected').index();
	var idxParam = 1;
	if (RFX.categories[idx][2]) {
		html += '<option value="'+RFX.deviceTypes[0][0]+'">'+RFX.deviceTypes[0][1]+'</option>';
	}
	if (RFX.categories[idx][3]) {
		html += '<option value="'+RFX.deviceTypes[1][0]+'">'+RFX.deviceTypes[1][1]+'</option>';
	}
	if (RFX.categories[idx][4]) {
		html += '<option value="'+RFX.deviceTypes[2][0]+'">'+RFX.deviceTypes[2][1]+'</option>';
	}
	if (RFX.categories[idx][5]) {
		html += '<option value="'+RFX.deviceTypes[3][0]+'">'+RFX.deviceTypes[3][1]+'</option>';
	}
	if (RFX.categories[idx][6]) {
		html += '<option value="'+RFX.deviceTypes[4][0]+'">'+RFX.deviceTypes[4][1]+'</option>';
	}
	if (RFX.categories[idx][7]) {
		html += '<option value="'+RFX.deviceTypes[5][0]+'">'+RFX.deviceTypes[5][1]+'</option>';
	}
	jQuery('#deviceType').html(html);

	if (RFX.categories[idx][8]) {
		html = 'Id:';
		html2 = '<input id="id" type="text" size="9" maxlength="9"/>';
		if (RFX.categories[idx][9] != undefined && RFX.categories[idx][10] != undefined) {
			html2 += '<label style="margin-left: 10px">Decimal value in range ' + RFX.categories[idx][9]
					+ ' - ' + RFX.categories[idx][10] + '</label>';
		}
		jQuery('#labelParam'+idxParam).html(html);
		jQuery('#valueParam'+idxParam).html(html2);
		idxParam += 1;
	}
	if (RFX.categories[idx][11]) {
		html = 'House code:';
		html2 = '<select id="houseCode">';
		for (i=RFX.categories[idx][12].charCodeAt(0); i<=RFX.categories[idx][13].charCodeAt(0); i++) {
			html2 += '<option>' + String.fromCharCode(i) + '</option>';
		}
		html2 += '</select>';
		jQuery('#labelParam'+idxParam).html(html);
		jQuery('#valueParam'+idxParam).html(html2);
		idxParam += 1;
	}
	if (RFX.categories[idx][14]) {
		html = 'Group code:';
		html2 = '<select id="groupCode">';
		for (i=RFX.categories[idx][15].charCodeAt(0); i<=RFX.categories[idx][16].charCodeAt(0); i++) {
			html2 += '<option>' + String.fromCharCode(i) + '</option>';
		}
		html2 += '</select>';
		jQuery('#labelParam'+idxParam).html(html);
		jQuery('#valueParam'+idxParam).html(html2);
		idxParam += 1;
	}
	if (RFX.categories[idx][17]) {
		html = 'Unit code:';
		html2 = '<select id="unitCode">';
		for (i=RFX.categories[idx][18]; i<=RFX.categories[idx][19]; i++) {
			html2 += '<option>' + i + '</option>';
		}
		html2 += '</select>';
		jQuery('#labelParam'+idxParam).html(html);
		jQuery('#valueParam'+idxParam).html(html2);
		idxParam += 1;
	}
	if (RFX.categories[idx][20]) {
		html = 'System code:';
		html2 = '<select id="systemCode">';
		for (i=RFX.categories[idx][21]; i<=RFX.categories[idx][22]; i++) {
			html2 += '<option>' + i + '</option>';
		}
		html2 += '</select>';
		jQuery('#labelParam'+idxParam).html(html);
		jQuery('#valueParam'+idxParam).html(html2);
		idxParam += 1;
	}
	if (RFX.categories[idx][23]) {
		html = 'Channel:';
		html2 = '<select id="channel">';
		for (i=RFX.categories[idx][24]; i<=RFX.categories[idx][25]; i++) {
			html2 += '<option>' + i + '</option>';
		}
		html2 += '</select>';
		jQuery('#labelParam'+idxParam).html(html);
		jQuery('#valueParam'+idxParam).html(html2);
		idxParam += 1;
	}
	for (i=idxParam; i<=3; i++) {
		jQuery('#labelParam'+i).html('');
		jQuery('#valueParam'+i).html('');
	}
}

function RFX_selectDevices()
{
	var nbSelected = 0;
	var selectedIds = '';
	var i=0;
	while (jQuery('#SelectDevice'+i).length > 0) {
		if (jQuery('#SelectDevice'+i).is(':checked')) {
			if (selectedIds != '') {
				selectedIds = selectedIds + ',';
			}
			selectedIds = selectedIds + jQuery('#SelectDevice'+i).val();
			nbSelected++;
		}
		i++;
	}
	if (nbSelected == 1) {
		var altid;
		var id;
		var name;
		var idxDevice = -1;
		for (i=0; i<RFX.userData.devices.length; i++) {
			if (RFX.userData.devices[i].id == selectedIds) {
				idxDevice = i;
				break;
			}
		}
		if (idxDevice < 0) {
			altid = '';
			id = '';
			name = '';
		}
		else {
			altid = RFX.userData.devices[idxDevice].altid;
			id = selectedIds;
			name = RFX.userData.devices[idxDevice].name;
		}

		var idx = -1;
		for (i=0; i<RFX.categories.length; i++) {
			if (RFX.categories[i][26] == altid.substr(3, RFX.categories[i][26].length)) {
				idx = i;
				break;
			}
		}

		var idxType = -1;
		for (i=0; i<RFX.deviceTypes.length; i++) {
			if (RFX.deviceTypes[i][3] == altid.substr(0, 3)) {
				idxType = i;
				break;
			}
		}

		var html = '';
		var curType = '';
		var disabled = true;
		if (idxDevice >= 0 && idxType >= 0) {
			var devType = RFX.userData.devices[idxDevice].device_type;
			if (devType == RFX.deviceTypes[idxType][2]) {
				curType = RFX.deviceTypes[idxType][1];
			}
		}
		if (idxDevice >= 0 && idx >= 0 && idxType >= 0 && idxType <= 5) {
			var devType = RFX.userData.devices[idxDevice].device_type;
			if (RFX.categories[idx][2]
					&& (RFX.deviceTypes[idxType][0] != RFX.deviceTypes[0][0]
						|| devType != RFX.deviceTypes[0][2])) {
				html += '<option value="'+RFX.deviceTypes[0][0]+'">'+RFX.deviceTypes[0][1]+'</option>';
				disabled = false;
			}
			if (RFX.categories[idx][3]
					&& (RFX.deviceTypes[idxType][0] != RFX.deviceTypes[1][0]
						|| devType != RFX.deviceTypes[1][2])) {
				html += '<option value="'+RFX.deviceTypes[1][0]+'">'+RFX.deviceTypes[1][1]+'</option>';
				disabled = false;
			}
			if (RFX.categories[idx][4]
					&& (RFX.deviceTypes[idxType][0] != RFX.deviceTypes[2][0]
						|| devType != RFX.deviceTypes[2][2])) {
				html += '<option value="'+RFX.deviceTypes[2][0]+'">'+RFX.deviceTypes[2][1]+'</option>';
				disabled = false;
			}
			if (RFX.categories[idx][5]
					&& (RFX.deviceTypes[idxType][0] != RFX.deviceTypes[3][0]
						|| devType != RFX.deviceTypes[3][2])) {
				html += '<option value="'+RFX.deviceTypes[3][0]+'">'+RFX.deviceTypes[3][1]+'</option>';
				disabled = false;
			}
			if (RFX.categories[idx][6]
					&& (RFX.deviceTypes[idxType][0] != RFX.deviceTypes[4][0]
						|| devType != RFX.deviceTypes[4][2])) {
				html += '<option value="'+RFX.deviceTypes[4][0]+'">'+RFX.deviceTypes[4][1]+'</option>';
				disabled = false;
			}
			if (RFX.categories[idx][7]
					&& (RFX.deviceTypes[idxType][0] != RFX.deviceTypes[5][0]
						|| devType != RFX.deviceTypes[5][2])) {
				html += '<option value="'+RFX.deviceTypes[5][0]+'">'+RFX.deviceTypes[5][1]+'</option>';
				disabled = false;
			}
		}

		var html2 = '';
		var disabled2 = true;
		if (idxDevice >= 0) {
			for (i=0; i<RFX.commands.length; i++) {
				if (RFX.commands[i][0] == altid.substr(3, RFX.commands[i][0].length)) {
					html2 += '<option value="'+RFX.commands[i][1]+'">'+RFX.commands[i][2]+'</option>';
					disabled2 = false;
				}
			}
		}

		var batteryLevel = get_device_state(selectedIds, 'urn:micasaverde-com:serviceId:HaDevice1', "BatteryLevel", 1);
		if (batteryLevel == undefined) {
			batteryLevel = '';
		}
		else {
			var lastUpdate = get_device_state(selectedIds, 'urn:micasaverde-com:serviceId:HaDevice1', "BatteryDate", 1);
			var last = new Date(lastUpdate*1000);
			batteryLevel += ' % (' + last.toLocaleString().replace(/\//g, ' ') + ')';
		}

		jQuery('#selDeviceID').html(id);
		jQuery('#newName').val(name);
		jQuery('#curDeviceType').html(curType);
		jQuery('#newDeviceType').html(html);
		jQuery('#changeType').get(0).disabled = disabled;
		jQuery('#commands').html(html2);
		jQuery('#runCommand').get(0).disabled = disabled2;
		jQuery('#battery').html(batteryLevel);
	}
	else {
		jQuery('#selDeviceID').html(selectedIds);
		jQuery('#newName').val('');
		jQuery('#curDeviceType').html('');
		jQuery('#newDeviceType').html('');
		jQuery('#changeType').get(0).disabled = true;
		jQuery('#commands').html('');
		jQuery('#runCommand').get(0).disabled = true;
		jQuery('#battery').html('');
	}
	if (nbSelected == 0) {
		jQuery('#delete1').get(0).disabled = true;
		jQuery('#delete2').get(0).disabled = true;
		jQuery('#msg2').html('First select one or more devices in the table');
		jQuery('#msg2').css({'color':''});
	}
	else {
		jQuery('#delete1').get(0).disabled = false;
		jQuery('#delete2').get(0).disabled = false;
		jQuery('#msg2').html(nbSelected + ' device(s) selected');
		jQuery('#msg2').css({'color':''});
	}
}

function RFX_selectLine(idx)
{
	var version = parseFloat(jQuery().jquery.substr(0,3));
	if (version < 1.6) {
		jQuery('#SelectDevice'+idx).attr('checked', !jQuery('#SelectDevice'+idx).is(':checked'));
	}
	else {
		jQuery('#SelectDevice'+idx).prop('checked', !jQuery('#SelectDevice'+idx).is(':checked'));
	}
	RFX_selectDevices();
}

function RFX_selectAllDevices(state)
{
	var version = parseFloat(jQuery().jquery.substr(0,3));
	var i=0;
	while (jQuery('#SelectDevice'+i).length > 0) {
		if (version < 1.6) {
			jQuery('#SelectDevice'+i).attr('checked', state);
		}
		else {
			jQuery('#SelectDevice'+i).prop('checked', state);
		}
		i++;
	}
	RFX_selectDevices();
}

function RFX_checkSettings(device)
{
	if(RFX.browserIE == undefined) {
		RFX.deviceID = device;
		var temperatureUnit = ' &deg;C';
		if (get_device_state(device, RFX.SID2, "CelciusTemp", 1) == '0') {
			temperatureUnit = ' &deg;F';
		}
		for (j=0; j<RFX.sensorDeviceTypes.length; j++) {
			if (RFX.sensorDeviceTypes[j][0] == "TEMPERATURE_SENSOR") {
				RFX.sensorDeviceTypes[j][11] = temperatureUnit;
				break;
			}
		}

		if (navigator.userAgent.toLowerCase().indexOf('msie') >= 0
			|| navigator.userAgent.toLowerCase().indexOf('trident') >= 0) {
			RFX.browserIE = true;
		}
		else {
			RFX.browserIE = false;
		}
		if (typeof api !== 'undefined') {
			RFX.buttonBgColor = '#006E47';
			RFX.tableTitleBgColor = '#00A652';
		}
		else {
			RFX.buttonBgColor = '#3295F8';
			RFX.tableTitleBgColor = '#025CB6';
		}
		RFX.nameTitleBgColor = RFX.tableTitleBgColor;
		RFX.roomTitleBgColor = RFX.tableTitleBgColor;
		RFX.typeTitleBgColor = RFX.tableTitleBgColor;

		RFX.sensorDataSortFunction = [RFX_sortByName, RFX_sortByRoom, RFX_sortByType ];
	}
}

function RFX_createDevice(device)
{
	var idx = jQuery('#category option:selected').index();
	var category = RFX.categories[idx][0];
	var deviceType = jQuery('#deviceType').val();
	var name = encodeURIComponent(jQuery('#name').val());
	var id = undefined;
	var houseCode = undefined;
	var groupCode = undefined;
	var unitCode = undefined;
	var systemCode = undefined;
	var channel = undefined;
	var controlOk = true;
	var reg1;
	if (RFX.categories[idx][8]) {
		reg1 = new RegExp('^\\d+$', '');
		if (jQuery('#id').val() == undefined || jQuery('#id').val() == ''
				|| !jQuery('#id').val().match(reg1)
				|| (RFX.categories[idx][9] != undefined && jQuery('#id').val() < RFX.categories[idx][9])
				|| (RFX.categories[idx][10] != undefined && jQuery('#id').val() > RFX.categories[idx][10])) {
			controlOk = false;
		}
		else {
			id = jQuery('#id').val();
		}
	}
	if (RFX.categories[idx][11]) {
		if (jQuery('#houseCode option:selected').index() >= 0) {
			houseCode = jQuery('#houseCode').val();
		}
		else {
			controlOk = false;
		}
	}
	if (RFX.categories[idx][14]) {
		if (jQuery('#groupCode option:selected').index() >= 0) {
			groupCode = jQuery('#groupCode').val();
		}
		else {
			controlOk = false;
		}
	}
	if (RFX.categories[idx][17]) {
		if (jQuery('#unitCode option:selected').index() >= 0) {
			unitCode = jQuery('#unitCode').val();
		}
		else {
			controlOk = false;
		}
	}
	if (RFX.categories[idx][20]) {
		if (jQuery('#systemCode option:selected').index() >= 0) {
			systemCode = jQuery('#systemCode').val();
		}
		else {
			controlOk = false;
		}
	}
	if (RFX.categories[idx][23]) {
		if (jQuery('#channel option:selected').index() >= 0) {
			channel = jQuery('#channel').val();
		}
		else {
			controlOk = false;
		}
	}
	if (controlOk) {
		jQuery('#msg').html('Vera will reload to validate the changes...');
		jQuery('#msg').css({'color':'green'});
		RFX_callAction(device, RFX.SID, 'CreateNewDevice',
							{	'CategoryType':category,
								'DeviceType':deviceType,
								'Name':name,
								'RemoteId':id,
								'HouseCode':houseCode,
								'GroupCode':groupCode,
								'UnitCode':unitCode,
								'SystemCode':systemCode,
								'Channel':channel
							} );
	}
	else {
		jQuery('#msg').html('Please fill correctly all input fields.');
		jQuery('#msg').css({'color':'red'});
	}
}

function RFX_changeDeviceType(device)
{
	var id = jQuery('#selDeviceID').html();
	var name = encodeURIComponent(jQuery('#newName').val());
	var idx = jQuery('#newDeviceType option:selected').index();
	if (id == '') {
		jQuery('#msg2').html('Please first select a device in the table');
		jQuery('#msg2').css({'color':'red'});
	}
	else if (idx < 0) {
		jQuery('#msg2').html('Device type cannot be changed for this device');
		jQuery('#msg2').css({'color':'red'});
	}
	else {
		var deviceType = jQuery('#newDeviceType').val();
		jQuery('#msg2').html('Vera will reload to validate the changes...');
		jQuery('#msg2').css({'color':'green'});
		RFX_callAction(device, RFX.SID, 'ChangeDeviceType', { 'DeviceId':id, 'DeviceType':deviceType, 'Name':name } );
	}
}

function RFX_deleteDevices(device, discardCreation)
{
	var selectedDevices = '';
	var i=0;
	while (jQuery('#SelectDevice'+i).length > 0) {
		if (jQuery('#SelectDevice'+i).is(':checked')) {
			for (j=0; j<RFX.userData.devices.length; j++) {
				if (RFX.userData.devices[j].id == jQuery('#SelectDevice'+i).val()) {
					if (selectedDevices != '') {
						selectedDevices = selectedDevices + ',';
					}
					selectedDevices = selectedDevices + RFX.userData.devices[j].altid;
					break;
				}
			}
		}
		i++;
	}
	if (selectedDevices == '') {
		jQuery('#msg2').html('Please first select a device in the table');
		jQuery('#msg2').css({'color':'red'});
	}
	else {
		jQuery('#msg2').html('Vera will reload to validate the changes...');
		jQuery('#msg2').css({'color':'green'});
		var discard = 'false';
		if (discardCreation) {
			discard = 'true';
		}
		RFX_callAction(device, RFX.SID, 'DeleteDevices', { 'ListDevices':selectedDevices, 'DisableCreation':discard } );
	}
}

function RFX_runCommand(device)
{
	var id = jQuery('#selDeviceID').html();
	var idx = jQuery('#commands option:selected').index();
	if (id == '') {
		jQuery('#msg2').html('Please first select a device in the table');
		jQuery('#msg2').css({'color':'red'});
	}
	else if (idx < 0) {
		jQuery('#msg2').html('No command available for this device');
		jQuery('#msg2').css({'color':'red'});
	}
	else {
		var command = jQuery('#commands').val();
		jQuery('#msg2').html('Command transmitted');
		jQuery('#msg2').css({'color':'green'});
		RFX_callAction(device, RFX.SID, 'SendCommand', { 'DeviceId':id, 'CommandType':command } );
	}
}

function RFX_setTempUnit(device) {
	var unit = undefined;
	if (jQuery('#tempUnit1').is(':checked')) {
		unit = 'CELCIUS';
	}
	else if (jQuery('#tempUnit2').is(':checked')) {
		unit = 'FAHRENHEIT';
	}
	if (unit != undefined) {
		RFX_callAction(device, RFX.SID, 'SetTemperatureUnit', { 'unit':unit } );
	}
}

function RFX_setSpeedUnit(device) {
	var unit = undefined;
	if (jQuery('#speedUnit1').is(':checked')) {
		unit = 'KMH';
	}
	else if (jQuery('#speedUnit2').is(':checked')) {
		unit = 'MPH';
	}
	if (unit != undefined) {
		RFX_callAction(device, RFX.SID, 'SetSpeedUnit', { 'unit':unit } );
	}
}

function RFX_setVoltage(device) {
	var voltage = jQuery('#voltage').val();
	RFX_callAction(device, RFX.SID, 'SetVoltage', { 'voltage':voltage } );
}

function RFX_setDebugLogs(device) {
	var enable = undefined;
	if (jQuery('#debugLogsOn').is(':checked')) {
		enable = 'true';
	}
	else if (jQuery('#debugLogsOff').is(':checked')) {
		enable = 'false';
	}
	if (enable != undefined) {
		RFX_callAction(device, RFX.SID, 'SetDebugLogs', { 'enable':enable } );
	}
}

function RFX_setAutoCreate(device) {
	var enable = undefined;
	if (jQuery('#autoCreateOn').is(':checked')) {
		enable = 'true';
	}
	else if (jQuery('#autoCreateOff').is(':checked')) {
		enable = 'false';
	}
	if (enable != undefined) {
		RFX_callAction(device, RFX.SID, 'SetAutoCreate', { 'enable':enable } );
	}
}

function RFX_callAction(device, sid, actname, args) {
	var q={
		'id':'lu_action',
		'output_format':'xml',
		'DeviceNum':device,
		'serviceId':sid,
		'action':actname
	};
	var key;
	for (key in args) {
		if (args[key] != undefined && args[key] != '') {
			q[key] = args[key];
		}
	}
    if (RFX.browserIE) {
    	q['timestamp'] = new Date().getTime(); //we need this to avoid IE caching of the AJAX get
    }
	new Ajax.Request (command_url+'/data_request', {
		method: 'get',
		parameters: q,
		onSuccess: function (response) {
		},
		onFailure: function (response) {
		},
		onComplete: function (response) {
		}
	});
}

