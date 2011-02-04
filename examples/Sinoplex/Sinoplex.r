#define UseExtendedThingResource 1

#include <CoreServices/CoreServices.r>
#include <AudioUnit/AudioUnit.r>

/*********************************************************************************************************************/
/*****																											 *****/
/*****									   Change the following definitions										 *****/
/*****																											 *****/
/*********************************************************************************************************************/

// IMPORTANT : You should define i386_YES (for Intel 32-bit), x86_64_YES (for Intel 64-bit), ppc_YES (for PPC) or a
// combination of these (for "universal binary"). Otherwise the Audio Unit may not be found during scanning. To make
// this selection depend on the architectures settings in XCode, add the following definition for OTHER_REZFLAGS to the
// project configuration: -d ppc_$(ppc) -d i386_$(i386) -d x86_64_$(x86_64)
//

#ifndef ppc_YES || i386_YES || x86_64_YES
	#define ppc_YES
	#define i386_YES
	#define x86_64_NO
#endif

// AudioUnit name in "company: product" format. This is typically the name that is presented to the user by the host
// (also, some hosts arranges their plug-in menus according to company name).
//
#define NAME "NuEdge Development: Sinoplex"

// Description (anything you want).
//
#define DESCRIPTION "NuEdge Development Symbiosis Example Effect"

// Plug-in version aa.bb.cc in 0xaabbcc format. Remember to keep this up-to-date so that hosts will rescan plug-ins
// when they change.
//
#define VERSION 0x010000

// kAudioUnitType_Effect (no MIDI), kAudioUnitType_MusicDevice (MIDI, no input) or kAudioUnitType_MusicEffect (MIDI +
// input). See AudioUnit/AUComponent.r for all types.
//
#define TYPE kAudioUnitType_MusicEffect

// Use the same unique ID you use for the VST.
//
#define SUBTYPE	'SiPx'

// Your unique manufacturer signature.
//
#define SIGNATURE 'NuEd'

// Set to 1 if your VST has a custom GUI (editor), set to 0 if you wish to use the standard editor.
//
#define CUSTOM_GUI 0

/*********************************************************************************************************************/
/*****																											 *****/
/*****							   That's it, the rest you shouldn't need to touch.								 *****/
/*****																											 *****/
/*********************************************************************************************************************/

resource 'STR ' (10002, "AUName", purgeable) { NAME };
resource 'STR ' (10003, "AUDescription", purgeable) { DESCRIPTION };
resource 'dlle' (10004, "AUEntryPoint") { "SymbiosisEntry" };
resource 'thng' (10000, NAME) {
	TYPE,
	SUBTYPE,
	SIGNATURE,
	0, 0,
	0, 0,
	'STR ',	10002,
	'STR ',	10003,
	0, 0,
	VERSION, 
	componentHasMultiplePlatforms | componentDoAutoVersion,
	0,
	{
		#ifndef ppc_YES
			#ifndef i386_YES
				#printf("***** You must define ppc_YES, i386_YES or both, see comment in .r for more info. *****\n")
				#error
			#endif
		#endif
		#ifdef ppc_YES
			0x10000000, 
			'dlle', 10004,
			platformPowerPCNativeEntryPoint
			#ifdef i386_YES
				,
			#endif
		#endif
		#ifdef i386_YES
			0x10000000, 
			'dlle', 10004,
			platformIA32NativeEntryPoint
			#ifdef x86_64_YES
				,
			#endif
		#endif
		#ifdef x86_64_YES
			0x10000000, 
			'dlle', 10004,
			8
		#endif
	}
};

#if (CUSTOM_GUI)

resource 'STR ' (10005, "AUViewName", purgeable) { NAME " AUView" };
resource 'STR ' (10006, "AUViewDescription", purgeable) { NAME " AUView" }; // Description for AUView is same as name.
resource 'dlle' (10007, "AUViewEntryPoint") { "SymbiosisViewEntry" };
resource 'thng' (10001, NAME " AUView") {
	kAudioUnitCarbonViewComponentType,
	SUBTYPE,
	SIGNATURE,
	0, 0,
	0, 0,
	'STR ',	10005,
	'STR ',	10006,
	0, 0,
	VERSION,
	componentHasMultiplePlatforms | componentDoAutoVersion,
	0,
	{
		#ifndef ppc_YES
			#ifndef i386_YES
				#printf("***** You must define ppc_YES, i386_YES or both, see comment in .r for more info. *****\n")
				#error
			#endif
		#endif
		#ifdef ppc_YES
			0x10000000, 
			'dlle', 10007,
			platformPowerPCNativeEntryPoint,
			#ifdef i386_YES
				,
			#endif
		#endif
		#ifdef i386_YES
			0x10000000, 
			'dlle', 10007,
			platformIA32NativeEntryPoint
			#ifdef x86_64_YES
				,
			#endif
		#endif
		#ifdef x86_64_YES
			0x10000000, 
			'dlle', 10007,
			8
		#endif
	}
};

#endif
