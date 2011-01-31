/**
	\file Sinoplex.cpp

	A simple and naive amplitude modulator plug-in. Provided as an example for NuEdge Development Symbiosis AU / VST.
	
	\version

	Version 1.0

	\page Copyright

	Sinoplex is released under the "New Simplified BSD License". http://www.opensource.org/licenses/bsd-license.php
	
	Copyright (c) 2011, NuEdge Development / Magnus Lidstroem
	All rights reserved.

	Redistribution and use in source and binary forms, with or without modification, are permitted provided that the
	following conditions are met:

	Redistributions of source code must retain the above copyright notice, this list of conditions and the following
	disclaimer. 
	
	Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following
	disclaimer in the documentation and/or other materials provided with the distribution. 
	
	Neither the name of the NuEdge Development nor the names of its contributors may be used to endorse or promote
	products derived from this software without specific prior written permission.
	
	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
	INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
	DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
	SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
	SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
	WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
	OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#if !defined(IS_WINDOWS) && !defined(IS_MAC)
	#if defined(_WIN32) // Visual C++ version
		#define IS_WINDOWS 1
	#elif defined(__APPLE__) // Mac OS X version
		#define IS_MAC 1
	#else
		#error IS_WINDOWS or IS_MAC must be defined to 1
	#endif
#endif

#if (IS_WINDOWS)
	#if !defined(WIN32_LEAN_AND_MEAN)
		#define WIN32_LEAN_AND_MEAN
	#endif
	#include <Windows.h>
	#include <crtdbg.h>
#endif

#if !defined(SINOPLEX_USE_VST_VERSION)	// See Sinoplex_Prefix.pch for information on this define.
	#if defined(kVstVersion)			// In case the VST SDK is included in the precompiled header, use the kVstVersion defined in aeffect.h
		#define SINOPLEX_USE_VST_VERSION kVstVersion
	#else
		#define SINOPLEX_USE_VST_VERSION 2400
	#endif
#endif

#if (SINOPLEX_USE_VST_VERSION == 2400)
	#include "pluginterfaces/vst2.x/aeffectx.h"
	#include "public.sdk/source/vst2.x/aeffeditor.h"
	#include "public.sdk/source/vst2.x/audioeffectx.h"
#elif (SINOPLEX_USE_VST_VERSION == 2300)
	#include "source/common/vstplugsmacho.h"
	#include "source/common/aeffectx.h"
	#include "source/common/AEffEditor.hpp"
	#define DECLARE_VST_DEPRECATED(x) x
	typedef short VstInt16;
	typedef long VstInt32;
	typedef VstInt32 VstIntPtr;
#else
	#error Unsupported VST SDK version!
#endif

#include <assert.h>
#include <stdio.h>
#include <math.h>

/* --- Plug-in constants --- */

const int kProductID = 'SiPx';
const int kInputCount = 2; // Valid values are 0 (for synth), 1 or 2 for mono and stereo effect.
const int kOutputCount = 2; // Valid values are 1 or 2 for mono and stereo or 4 for dual stereo (aux channel test).
const int kProgramCount = 10;
const int kParameterCount = 12;
const int kSyncedLFODivsCount = 20;
const double kSyncedLFODivs[kSyncedLFODivsCount] = {
	4/1.0, 3/1.0, 8/3.0, 2/1.0, 3/2.0, 4/3.0, 1/1.0, 3/4.0, 2/3.0, 1/2.0, 3/8.0, 2/6.0, 1/4.0, 3/16.0, 2/12.0, 1/8.0
	, 2/24.0, 1/16.0, 2/48.0, 1/32.0
};
const char* kSyncedLFODivsStrings[kSyncedLFODivsCount] = {
	"4/1", "3/1 (2/1.)", "4/1T", "2/1", "3/2 (1/1.)", "2/1T", "1/1", "3/4 (1/2.)", "1/1T", "1/2", "3/8 (1/4.)", "1/2T",
	"1/4", "3/16 (1/8.)", "1/4T", "1/8", "1/8T", "1/16", "1/16T", "1/32"
};
const char* kLFOWaveformStrings[4] = { "Sine", "Square", "Saw Down", "Saw Up" };

/* --- Utility constants and functions --- */

const float kPIf = 3.14159265358979323846264338327950f;
const float kLn2f = 0.69314718055994530941723212145817f;
const float kLn10f = 2.3025850929940456840179914546843f;

static inline float squaref(float x) { return x * x; }
static inline float cubef(float x) { return x * x * x; }

#if (IS_WINDOWS)

static inline float cbrtf(float x) { return (x < 0) ? -powf(-x, 0.3333333333333334f) : powf(x, 0.3333333333333334f); }
static inline int strcmpNoCase(const char* a, const char* b) { return _stricmp(a, b); }
static inline int strncmpNoCase(const char* a, const char* b, int l) { return _strnicmp(a, b, l); }

#else

static inline int strcmpNoCase(const char* a, const char* b) { return strcasecmp(a, b); }
static inline int strncmpNoCase(const char* a, const char* b, int l) { return strncasecmp(a, b, l); }

#endif

static inline float decayConstant(float time, float reach) {
	return (time == 0.0f) ? 0.0f : expf(-1.0f / time * logf(1.0f / reach));
}

/**
	SinoplexProgram is a struct containing all parameters that constitutes a program / preset / patch. I have chosen
	to represent all parameters here in natural C++ types (but not necessarily natural units), and performing the
	conversion to and from these types in the VST getParameter() / setParameter() calls. Later in the processing the
	parameters are converted to natural units and the mathematical variables necessary for the dsp code. There are
	static helper functions in this struct for performing such conversion. These functions are also used to convert
	parameters to and from text representation.
	
	For thread atomicity, all fields in this class (except the program name) should be less than 32-bit and they have
	to be unrelated so that they can be updated randomly in any order.
	
	The reason I choose to use the struct keyword here instead of class is to emphasize that this struct will be handled
	as a POD (plain-old-data) type, so it musn't contain constructors, destructors or virtual methods.
*/
struct SinoplexProgram {
	enum Parameter {
		kFreq
		, kLFOAmount
		, kEnvAmount
		, kEnvInvert
		, kLFOWaveform
		, kLFOSync
		, kLFORate
		, kEnvAttack
		, kEnvDecay
		, kMidi
		, kAM
		, kMix
	};

	enum LFOWaveform {
		kSine
		, kSquare
		, kSawDown
		, kSawUp
	};

	char name[24 + 1];
	float freq;
	float lfoAmount;
	float envAmount;
	bool envInvert;
	LFOWaveform lfoWaveform;
	bool lfoSync;
	float lfoRate;
	float envAttack;
	float envDecay;
	bool midi;
	bool am;
	float mix;
	
	void setParameter(Parameter param, float value) volatile;															// That's right, by declaring the member function volatile we say that it is ok to call this function on an object that is volatile, e.g. shared between threads.
	float getParameter(Parameter param) const volatile;																	// - " -
	void convertParameterValueToString(Parameter parameter, float value, char* string) const volatile;
	float convertParameterStringToValue(Parameter parameter, const char* string) const volatile;

	static LFOWaveform convertParamToLFOWaveform(float x) { return static_cast<LFOWaveform>(int(x * 3 + 0.5f)); }
	static float convertLFOWaveformToParam(LFOWaveform form) { return form / 3.0f; }
	static int convertLFORateParamToSyncedIndex(float x) { return static_cast<int>(x * (kSyncedLFODivsCount - 1) + 0.5f); }
	static float convertLFORateSyncedIndexToParam(int x) { return x / static_cast<float>(kSyncedLFODivsCount - 1); }
	static float convertFreqParamToHz(float x) { return 20.0f * expf(kLn10f * 3.0f * x); }
	static float convertFreqHzToParam(float x) { return (x <= 0) ? 0.0f : (log(x / 20.0f) / (kLn10f * 3.0f)); }
	static float convertLFOParamToHz(float x) { return 0.1f * expf(kLn10f * 4.0f * x); }
	static float convertLFOHzToParam(float x) { return (x <= 0) ? 0.0f : (log(x / 0.1f) / (kLn10f * 4.0f)); }
	static float convertModParamToOcts(float x) { return squaref(x) * 4.0f; }
	static float convertModOctsToParam(float x) { return (x < 0) ? 0.0f : sqrtf(x / 4.0f); }
	static float convertAttackParamToSecs(float x) { return cubef(x) * 2.0f; }
	static float convertAttackSecsToParam(float x) { return (x < 0) ? 0.0f : cbrtf(x / 2.0f); }
	static float convertDecayParamToSecs(float x) { return cubef(x) * 10.0f; }
	static float convertDecaySecsToParam(float x) { return (x < 0) ? 0.0f : cbrtf(x / 10.0f); }
	static const char* getParameterLabel(Parameter param);
	static const char* getParameterName(Parameter param);
};

/* --- Factory programs --- */

const int kFactoryProgramCount = 10;
const SinoplexProgram kFactoryPrograms[kFactoryProgramCount] = {
	{ "Add Chirps And Serve", 0.68f, 0.01f, 1.00f, false, SinoplexProgram::kSine, true, 1.00f, 0.21f, 0.21f, false, false, 0.25f }
	, { "AM dot klimax", 0.50f, 1.00f, 0.00f, false, SinoplexProgram::kSawUp, true, 0.00f, 0.40f, 0.40f, false, true, 1.00f }
	, { "Bleep Me", 0.79f, 0.53f, 0.35f, true, SinoplexProgram::kSquare, true, 1.00f, 0.17f, 0.38f, false, true, 0.15f }
	, { "Doing Doing Doing", 0.41f, 0.48f, 0.71f, true, SinoplexProgram::kSine, false, 1.0f, 0.14f, 0.67f, false, true, 1.00f }
	, { "Eat Ma Hi Fi", 0.27f, 0.01f, 1.00f, false, SinoplexProgram::kSine, true, 1.00f, 0.01f, 0.00f, false, false, 1.00f }
	, { "Hi Freek", 0.91f, 0.27f, 0.00f, true, SinoplexProgram::kSine, false, 0.10f, 0.00f, 0.08f, false, true, 0.15f }
	, { "Play Duck", 0.57f, 0.00f, 0.00f, true, SinoplexProgram::kSine, false, 0.52f, 0.10f, 0.10f, true, false, 0.5f }
	, { "Rice In Sun", 0.74f, 0.48f, 0.88f, true, SinoplexProgram::kSawUp, false, 1.0f, 0.4f, 0.90f, false, false, 0.33f }
	, { "Stop Whining", 0.57f, 0.35f, 0.72f, false, SinoplexProgram::kSine, false, 0.90f, 0.44f, 0.48f, false, false, 0.50f }
	, { "3Molo", 0.00f, 1.00f, 0.00f, true, SinoplexProgram::kSine, false, 0.00f, 0.38f, 0.88f, false, true, 1.00f }
};

/**
	Very simple class for generating a sine signal.
*/
class SineGenerator {
	public:		SineGenerator();			///< Constructs and resets phase to 0.
	public:		void reset();				///< Resets phase to 0.
	public:		float render(float rate);	///< Renders one sample of the sine signal and increments the phase by \p rate.
	private:	float p;					///< Phase.
};

/**
	Simplest possible envelope follower (as I am aware of). It is basically a single pole filter, following the absolute
	of the input signal. There are seperate constants for the filter used for attack and decay of the follower. The
	attack constant is used if the input signal is higher than the currently track signal, and vice versa.
*/
class EnvelopeFollower {
	public:		EnvelopeFollower();										///< Constructs and resets all variables to 0.
	public:		void reset();											///< Resets all internal variables to 0.
	public:		void setup(float attackConstant, float decayConstant);	///< Sets up the follower attack and decay constants. These are the constants for the single pole filter. One way to calculate them is by using decayConstant, for example: 1.0f - decayConstant(secs * sr, 0.001f).
	public:		float process(float in);								///< Processes a single input sample and returns the tracked signal.
	public:		float getCurrent() const;								///< Returns the last tracked signal, as returned by process().
	private:	float y;												///< Tracked signal value.
	private:	float ac;												///< Attack constant.
	private:	float dc;												///< Decay constant.
};

/**
	Simple three-stage envelope with attack, sustain and release. Envelope (usually) starts at 0.0 and the attack is
	linear up to 1.0, after this it is sustained until released when it decays back to 0.0 exponentially.
*/
class AREnvelope {
	public:		enum Stage {
					kAttack												///< Attack stage. The current value goes linearly from the current value to 1.0 according to the attack-rate configured with setup().
					, kSustain											///< Sustain stage. The envelope will remain at 1.0 until release() is called.
					, kRelease											///< Release stage. The envelope will decay exponentially to approx 0.0 according to the decay-rate configured with setup().
					, kDead												///< Initial and final stage. When the release value has decayed beneath 0.00001, the value is set to exact 0 and the stage is set to kDead.
				};
	public:		AREnvelope();											///< Constructs, resets all variables to 0 and sets the stage to kDead.
	public:		void reset();											///< Resets all internal variables to 0 and sets the stage to kDead.
	public:		void setup(float attackRate, float releaseConstant);	///< Sets up the envelope attack and release times. Attack is the rate at which it linearly increases per sample up to 1.0. Decay is the exponential decay constant multiplication per sample. Calculation examples: attack = (secs * sr < 1.0f) ? 1.0f : (1.0f / (secs * sr)), decay = decayConstant(secs * sr, 0.001f).
	public:		void attack();											///< Triggers the envelope by putting it into the attack stage. (If attack-rate is approx 1.0 it immediately goes to the sustain stage.)
	public:		void release();											///< Releases the envelope by putting it into the release stage.
	public:		float render();											///< Ticks the envelope, updating it's current value (and possible stage) and returns the current value between 0.0 and 1.0.
	public:		Stage getStage() const;									///< Returns the current envelope stage.
	public:		float getCurrent() const;								///< Returns the current envelope value (as returned last by render()).
	private:	Stage stage;											///< Current stage.
	private:	float current;											///< Current value.
	private:	float ar;												///< Attack rate.
	private:	float rc;												///< Release constant.
};

class Sinoplex : public AudioEffectX {
	public:		Sinoplex(audioMasterCallback audioMaster);
	public:		virtual VstPlugCategory getPlugCategory();
	public:		virtual bool getEffectName (char* name);
	public:		virtual bool getVendorString (char* text);
	public:		virtual bool getProductString (char* text);
	public:		virtual VstInt32 getVendorVersion();
	public:		virtual VstInt32 canDo(char* text);
	public:		virtual void setProgram(VstInt32 program);
	public:		virtual void setProgramName(char* name);
	public:		virtual bool getProgramNameIndexed(VstInt32 category, VstInt32 index, char* text);
	public:		virtual void getProgramName(char* name);
	public:		virtual void setParameter(VstInt32 index, float value);
	public:		virtual float getParameter(VstInt32 index);
	public:		virtual void getParameterLabel(VstInt32 index, char* label);
	public:		virtual void getParameterDisplay(VstInt32 index, char* text);
	public:		virtual void getParameterName(VstInt32 index, char* text);
	public:		virtual void resume();
	public:		virtual bool setBypass(bool onOff);
	public:		virtual void DECLARE_VST_DEPRECATED (process) (float **inputs, float **outputs, VstInt32 sampleFrames);
	public:		virtual void processReplacing(float **inputs, float **outputs, VstInt32 sampleFrames);
	public:		virtual VstInt32 getTailSize();
	public:		virtual VstInt32 getGetTailSize();																		// Typo in (some?) VST implementations.
	public:		virtual bool getInputProperties(VstInt32 index, VstPinProperties* properties);
	public:		virtual bool getOutputProperties(VstInt32 index, VstPinProperties* properties);
	public:		virtual VstIntPtr vendorSpecific(VstInt32 lArg1, VstIntPtr lArg2, void* ptrArg, float floatArg);
/*	public:		virtual ~Sinoplex(); */

	protected:	template<class OP> void processTemplate(float** inputs, float** outputs, VstInt32 sampleFrames, OP op);	// We declare a template for the processing method so that we can use the same routine for accumulating and replacing calls from the host.
	protected:	void convertParameterValueToString(SinoplexProgram::Parameter parameter, float value, char* string);
	protected:	void midiNoteOn(int note, bool resetLFOPhase);
	protected:	void midiNoteOff(int note);
	protected:	void midiAllNotesOff(bool muteDirectly);
	protected:	virtual VstInt32 processEvents(VstEvents* events);
	protected:	void processBegin(const SinoplexProgram& p);
	protected:	float processOne(const SinoplexProgram& p, float mono, float& env);
	protected:	void applyAM(const SinoplexProgram& p, float osc, float env, float inLeft, float inRight, float& outLeft, float& outRight);
	protected:	void applyMix(const SinoplexProgram& p, float osc, float env, float inLeft, float inRight, float& outLeft, float& outRight);
	protected:	bool willOutputBeSilent(const SinoplexProgram& p, bool inputIsSilent);

	protected:	volatile SinoplexProgram programs[kProgramCount];														// Volatile since they may be accessed from different threads simultaneously.
	protected:	volatile SinoplexProgram* volatile currentProgram;														// Volatile since the program pointer may be updated concurrently.
	protected:	bool isBypassing;
	protected:	bool inputIsSilent;
	protected:	bool outputIsSilent;
	protected:	int midiHeldKey; // < 0 = released.
	protected:	float oscRate;
	protected:	float midiNoteRate;
	protected:	float lfoAmount;
	protected:	float envAmount;
	protected:	float lfoRate;
	protected:	float lfoPhase;
	protected:	AREnvelope envelope;
	protected:	EnvelopeFollower follower;
	protected:	SineGenerator osc;
};

/* --- SinoplexProgram --- */

void SinoplexProgram::setParameter(Parameter param, float value) volatile {
	switch (param) {
		case kFreq: freq = value; break;
		case kLFOAmount: lfoAmount = value; break;
		case kEnvAmount: envAmount = value; break;
		case kEnvInvert: envInvert = (value >= 0.5f); break;
		case kLFOWaveform: lfoWaveform = convertParamToLFOWaveform(value); break;
		case kLFOSync: lfoSync = (value >= 0.5f); break;
		case kLFORate: lfoRate = value; break;
		case kEnvAttack: envAttack = value; break;
		case kEnvDecay: envDecay = value; break;
		case kMidi: midi = (value >= 0.5f); break;
		case kAM: am = (value >= 0.5f); break;
		case kMix: mix = value; break;
		default: assert(0); break;
	}
}

float SinoplexProgram::getParameter(Parameter param) const volatile {
	switch (param) {
		case kFreq: return freq;
		case kLFOAmount: return lfoAmount;
		case kEnvAmount: return envAmount;
		case kEnvInvert: return envInvert;
		case kLFOWaveform: return convertLFOWaveformToParam(lfoWaveform);
		case kLFOSync: return lfoSync ? 1.0f : 0.0f;
		case kLFORate: return lfoRate;
		case kEnvAttack: return envAttack;
		case kEnvDecay: return envDecay;
		case kMidi: return midi ? 1.0f : 0.0f;
		case kAM: return am ? 1.0f : 0.0f;
		case kMix: return mix;
		default: assert(0); break;
	}
	return 0.0f;
}

const char* SinoplexProgram::getParameterLabel(Parameter param) {
	switch (param) {
		case kFreq: return "Hz";
		case kLFOAmount: break;
		case kEnvAmount: return "sm";
		case kEnvInvert: break;
		case kLFOWaveform: break;
		case kLFOSync: break;
		case kLFORate: break; // Depends on sync switch, so this is included in 'getParameterDisplay' instead.
		case kEnvAttack:
		case kEnvDecay: return "ms";
		case kMidi: break;
		case kAM: break;
		case kMix: return "%";
		default: assert(0); break;
	}
	return "";
}

const char* SinoplexProgram::getParameterName(Parameter param) {
	switch (param) {
		case kMidi: return "MIDI";
		case kFreq: return "Freq";
		case kLFOAmount: return "LFOAmt";
		case kEnvAmount: return "EnvAmt";
		case kEnvInvert: return "EnvInv";
		case kLFOWaveform: return "LFOWave";
		case kLFOSync: return "LFOSync";
		case kLFORate: return "LFORate";
		case kEnvAttack: return "Attack";
		case kEnvDecay: return "Decay";
		case kAM: return "AM";
		case kMix: return "Mix";
		default: assert(0);
	}
	return "";
}

void SinoplexProgram::convertParameterValueToString(Parameter parameter, float value, char* string) const volatile {
	assert(value >= 0.0f && value <= 1.0f);
	string[0] = '\0';
	switch (parameter) {
		case kFreq: sprintf(string, "%.2f", convertFreqParamToHz(value)); break;
		case kLFOAmount:
		case kEnvAmount: sprintf(string, "%.2f", convertModParamToOcts(value) * 12.0f); break;
		case kLFOWaveform: strcpy(string, kLFOWaveformStrings[convertParamToLFOWaveform(value)]); break;			
		case kEnvAttack: sprintf(string, "%.2f", convertAttackParamToSecs(value) * 1000.0f); break;
		case kEnvDecay: sprintf(string, "%.2f", convertDecayParamToSecs(value) * 1000.0f); break;
		case kEnvInvert:
		case kLFOSync:
		case kMidi:
		case kAM: strcpy(string, ((value >= 0.5) ? "on" : "off")); break;
		case kMix: sprintf(string, "%.0f", value * 100.0f); break;
		case kLFORate:
			if (lfoSync) {
				strcpy(string, kSyncedLFODivsStrings[convertLFORateParamToSyncedIndex(lfoRate)]);
			} else {
				sprintf(string, "%.2f Hz", convertLFOParamToHz(value));
			}
			break;

		default: assert(0); break;
	}
}

float SinoplexProgram::convertParameterStringToValue(Parameter parameter, const char* string) const volatile {
	float value = 0.0f;
	switch (parameter) {
		case kFreq: value = convertFreqHzToParam(atof(string)); break;
		case kLFOAmount:
		case kEnvAmount: value = convertModOctsToParam(atof(string) / 12.0f); break;
		case kEnvAttack: value = convertAttackSecsToParam(atof(string) / 1000.0f); break;
		case kEnvDecay: value = convertDecaySecsToParam(atof(string) / 1000.0f); break;
		case kEnvInvert:
		case kLFOSync:
		case kMidi:
		case kAM: value = (strcmpNoCase(string, "on") == 0) ? 1.0f : 0.0f; break;
		case kMix: value = atof(string) / 100.0f; break;
		case kLFOWaveform: {
			int l = strlen(string);
			for (int i = 0; i < 4; ++i) {
				if (strncmpNoCase(string, kLFOWaveformStrings[i], l) == 0) {
					value = convertLFOWaveformToParam(static_cast<LFOWaveform>(i));
					break;
				}
			}
			break;
		}
		
		case kLFORate:
			if (lfoSync) {
				int l = strlen(string);
				for (int i = 0; i < kSyncedLFODivsCount; ++i) {
					if (strncmpNoCase(string, kSyncedLFODivsStrings[i], l) == 0) {
						value = convertLFORateSyncedIndexToParam(i);
						break;
					}
				}
			} else {
				value = convertLFOHzToParam(atof(string));
			}
			break;
			
		default: assert(0); break;
	}
	if (value < 0.0f) {
		value = 0.0f;
	} else if (value > 1.0f) {
		value = 1.0f;
	}
	return value;
}

/* --- SineGenerator --- */

SineGenerator::SineGenerator() { reset(); }
void SineGenerator::reset() { p = 0.0f; }

float SineGenerator::render(float rate) {
	assert(rate >= 0.0 && rate <= 0.5);
	float out = sinf(p);
	p += rate * (kPIf * 2);
	p = ((p >= kPIf) ? (p -= kPIf * 2) : p);
	return out;
}

/* --- EnvelopeFollower --- */

EnvelopeFollower::EnvelopeFollower() { reset(); }
void EnvelopeFollower::reset() { y = 0.0f; ac = 0.0f; dc = 0.0f; }
float EnvelopeFollower::getCurrent() const { return y; }
void EnvelopeFollower::setup(float attackConstant, float decayConstant) { ac = attackConstant; dc = decayConstant; }

float EnvelopeFollower::process(float in) {
	float x = fabsf(in);
	float d = x - y;
	if (fabsf(d) < 0.00001f) { // Note: this operation could be performed on a lower rate basis.
		y = x;
	} else {		
		y += d * ((d > 0) ? ac : dc);
	}
	return y;
}

/* --- AREnvelope --- */

AREnvelope::AREnvelope() { reset(); }
void AREnvelope::setup(float attackRate, float releaseConstant) { ar = attackRate; rc = releaseConstant; }
void AREnvelope::release() { stage = kRelease; }
AREnvelope::Stage AREnvelope::getStage() const { return stage; }
float AREnvelope::getCurrent() const { return current; }

void AREnvelope::reset() {
	stage = kDead;
	current = 0.0f;
	ar = 0.0f;
	rc = 0.0f;
}

void AREnvelope::attack() {
	stage = kAttack;
	if (ar > 0.99999f) {
		current = 1.0f;
		stage = kSustain;
	}
}

float AREnvelope::render() {
	switch (stage) {
		case kAttack:
			current += ar;
			if (current >= 1.0f) {
				current = 1.0;
				stage = kSustain;
			}
			break;

		case kRelease:
			current *= rc;
			if (current < 0.00001f) { // Note: this operation could be performed on a lower rate basis.
				current = 0.0f;
				stage = kDead;
			}
			break;
						
		case kDead:
		case kSustain: break;
		default: assert(0); break;
	}
	return current;
}

/* --- Sinoplex --- */

VstPlugCategory Sinoplex::getPlugCategory() { return (kInputCount == 0 ? kPlugCategSynth : kPlugCategEffect); }
bool Sinoplex::getEffectName (char* name) { strcpy(name, "Sinoplex"); return true; }
bool Sinoplex::getVendorString (char* text) { strcpy(text, "NuEdge Development"); return true; }
bool Sinoplex::getProductString (char* text) { strcpy(text, "Sinoplex"); return true; }
VstInt32 Sinoplex::getVendorVersion() { return 1; }
void Sinoplex::getProgramName(char* name) { getProgramNameIndexed(0, getProgram(), name); }
bool Sinoplex::setBypass(bool onOff) { isBypassing = onOff; return true; }

Sinoplex::Sinoplex(audioMasterCallback audioMaster)
	: AudioEffectX(audioMaster, kProgramCount, kParameterCount), currentProgram(&programs[0]), isBypassing(false)
	, inputIsSilent(false), outputIsSilent(false), midiHeldKey(-1), oscRate(0.0f), midiNoteRate(0.0f), lfoAmount(0.0f)
	, envAmount(0.0f), lfoRate(0.0f), lfoPhase(0.0f) {
	assert(0 <= kInputCount && kInputCount <= 2);
	assert(1 <= kOutputCount && kOutputCount <= 4);
	
	setUniqueID(kProductID);
	setNumInputs(kInputCount);
	setNumOutputs(kOutputCount);
	DECLARE_VST_DEPRECATED (canMono) (true);
	canProcessReplacing(true); // Required for Symbiosis compatibility.
	setProgram(0);
	setSampleRate(44100.0f);
	assert(kFactoryProgramCount <= kFactoryProgramCount);
	memcpy(const_cast<SinoplexProgram*>(programs), kFactoryPrograms, kFactoryProgramCount * sizeof (SinoplexProgram));
	memset(const_cast<SinoplexProgram*>(&programs[kFactoryProgramCount]), 0
			, (kProgramCount - kFactoryProgramCount) * sizeof (SinoplexProgram));
}

VstInt32 Sinoplex::canDo(char* text) {
	if (strcmp(text, "receiveVstEvents") == 0
			|| strcmp(text, "receiveVstMidiEvent") == 0
			|| strcmp(text, "receiveVstTimeInfo") == 0
			|| strcmp(text, "bypass") == 0) {
		return 1;
	} else {
		return 0;
	}
}

void Sinoplex::setProgram(VstInt32 program) {
	assert(program >= 0 && program < kProgramCount);
	currentProgram = &programs[program];
	AudioEffectX::setProgram(program);
}

void Sinoplex::setProgramName(char* name) {
	volatile SinoplexProgram* p = currentProgram;
	p->name[24] = '\0';
	strncpy(const_cast<char*>(p->name), name, 24);
}

bool Sinoplex::getProgramNameIndexed(VstInt32 category, VstInt32 index, char* text) {
	assert(index >= 0 && index < kProgramCount);
	strcpy(text, const_cast<const char*>(programs[index].name));
	return true;
}

void Sinoplex::setParameter(VstInt32 index, float value) {
	assert(index >= 0 && index < kParameterCount);
	currentProgram->setParameter(static_cast<SinoplexProgram::Parameter>(index), value);
}

float Sinoplex::getParameter(VstInt32 index) {
	assert(index >= 0 && index < kParameterCount);
	return currentProgram->getParameter(static_cast<SinoplexProgram::Parameter>(index));
}

void Sinoplex::getParameterLabel(VstInt32 index, char* label) {
	strcpy(label, SinoplexProgram::getParameterLabel(static_cast<SinoplexProgram::Parameter>(index)));
}

void Sinoplex::getParameterDisplay(VstInt32 index, char* text) {
	SinoplexProgram::Parameter param = static_cast<SinoplexProgram::Parameter>(index);
	const volatile SinoplexProgram* p = currentProgram;
	p->convertParameterValueToString(param, p->getParameter(param), text);
}

void Sinoplex::getParameterName(VstInt32 index, char* text) {
	strcpy(text, SinoplexProgram::getParameterName(static_cast<SinoplexProgram::Parameter>(index)));
}

void Sinoplex::resume() {
	DECLARE_VST_DEPRECATED (wantEvents) ();
	midiHeldKey = -1;
	midiNoteRate = 0.0f;
	lfoPhase = 0.0f;
	envelope.reset();
	follower.reset();
	osc.reset();
}

void Sinoplex::midiNoteOn(int note, bool resetLFOPhase) {
	if (midiHeldKey < 0) {
		envelope.attack();
		if (resetLFOPhase) {
			lfoPhase = 0.0f;
		}
	}
	midiHeldKey = note;
	midiNoteRate = expf(kLn2f / 12.0f * (note - 60.0f));
}

void Sinoplex::midiNoteOff(int note) {
	if (note == midiHeldKey) {
		envelope.release();
		midiHeldKey = -1;
	}
}

void Sinoplex::midiAllNotesOff(bool muteDirectly) {
	if (muteDirectly) {
		envelope.reset();
	} else {
		envelope.release();
	}
	midiHeldKey = -1;
}

VstInt32 Sinoplex::processEvents(VstEvents* events) {
	// This code isn't sample accurate, nor does it have a back-log of held midi keys, but what do you expect for free? :-)
	
	bool resetLFOPhaseOnTrigger = !currentProgram->lfoSync;
	for (int i = 0; i < events->numEvents; ++i) {
		VstMidiEvent& event = *reinterpret_cast<VstMidiEvent*>(events->events[i]);
		if (event.type == kVstMidiType) {
			switch (event.midiData[0] & 0xF0) {
				case 0x80: midiNoteOff(event.midiData[1]); break;				
				
				case 0x90:
					if (event.midiData[2] == 0) {
						midiNoteOff(event.midiData[1]);
					} else {
						midiNoteOn(event.midiData[1], resetLFOPhaseOnTrigger);
					}
					break;
					
				case 0xB0:
					if (event.midiData[1] == 0x78 || event.midiData[1] == 0x7B) {
						midiAllNotesOff(event.midiData[1] == 0x78);
					}
					break;
			}
		}
	}
	return 1;
}

void Sinoplex::processBegin(const SinoplexProgram& p) {
	float sr = getSampleRate();

	oscRate = SinoplexProgram::convertFreqParamToHz(p.freq) * (p.midi ? midiNoteRate : 1.0f) / sr;
	if (p.lfoSync) {

		// Collect sync info from host (notice that this code only works perfectly without cycling, I know it kind of sucks, but hey...)
		float syncTempo = 120.0f;
		bool syncRunning = false;
		double syncPosition = 0.0;
		VstTimeInfo* timeInfo = getTimeInfo(kVstTransportPlaying | kVstTransportCycleActive | kVstPpqPosValid | kVstTempoValid | kVstCyclePosValid);
		if (timeInfo != 0) {
			if ((timeInfo->flags & kVstTempoValid) != 0) {
				syncTempo = timeInfo->tempo;
				if ((timeInfo->flags & kVstPpqPosValid) != 0) {
					syncRunning = ((timeInfo->flags & kVstTransportPlaying) != 0);
					syncPosition = timeInfo->ppqPos;
				}
			}
		}
		
		// Relative rate is inverse of "tempo division" and absolute rate is "relative rate" times "how many beats we do in one sample".
		lfoRate = 1.0f / (4.0f * kSyncedLFODivs[SinoplexProgram::convertLFORateParamToSyncedIndex(p.lfoRate)]);
		if (syncRunning) {
			lfoPhase = fmodf(lfoRate * syncPosition, 1.0f);
		}
		lfoRate *= (syncTempo / 60.0f) / sr;
	} else {
		lfoRate = SinoplexProgram::convertLFOParamToHz(p.lfoRate) / sr;
		lfoRate = ((lfoRate > 0.5f) ? 0.5f : lfoRate);
	}
	lfoAmount = SinoplexProgram::convertModParamToOcts(p.lfoAmount);
	envAmount = SinoplexProgram::convertModParamToOcts(p.envAmount) * (p.envInvert ? -1.0f : 1.0f);;
	float envAttackSamples = SinoplexProgram::convertAttackParamToSecs(p.envAttack) * sr;
	float attackRateConstant = (envAttackSamples < 1.0f) ? 1.0f : (1.0f / envAttackSamples);
	float decayDecayConstant = decayConstant(SinoplexProgram::convertDecayParamToSecs(p.envDecay) * sr, 0.001f);
	envelope.setup(attackRateConstant, decayDecayConstant);
	float attackDecayConstant = decayConstant(envAttackSamples, 0.001f);
	follower.setup((1.0f - attackDecayConstant), (1.0f - decayDecayConstant));
}

float Sinoplex::processOne(const SinoplexProgram& p, float mono, float& env) {
	envelope.render();
	follower.process(mono * 0.5f);
	env = ((p.midi) ? envelope.getCurrent() : follower.getCurrent());
	env = ((env > 1.0f) ? 1.0f : env);

	// Yeah, yeah, I know, no anti-aliasing here, no, no...
	float lfo;
	switch (p.lfoWaveform) {
		case SinoplexProgram::kSine: lfo = sinf(lfoPhase * 2.0f * kPIf); break;
		case SinoplexProgram::kSquare: lfo = (lfoPhase < 0.5f) ? 1.0f : -1.0f; break;
		case SinoplexProgram::kSawDown: lfo = 1.0f - (lfoPhase * 2.0f); break;
		case SinoplexProgram::kSawUp: lfo = -1.0f + (lfoPhase * 2.0f); break;
		default: assert(0);
	}
	lfoPhase += lfoRate;
	if (lfoPhase > 1.0f) {
		lfoPhase -= 1.0f;
		assert(lfoPhase < 1.0f);
	}

	float r = oscRate * expf(kLn2f * (lfo * lfoAmount + env * envAmount));
	r = ((r > 0.5f) ? 0.5f : r);
	return osc.render(r);
}

void Sinoplex::applyAM(const SinoplexProgram& p, float osc, float env, float inLeft, float inRight, float& outLeft
		, float& outRight) {
	float x = p.mix * (p.midi ? env : 1.0);
	float y = 1.0 + x * (osc - 1.0);
	outLeft = inLeft * y;
	outRight = inRight * y;
}

void Sinoplex::applyMix(const SinoplexProgram& p, float osc, float env, float inLeft, float inRight, float& outLeft
		, float& outRight) {
	float x = 1.0 - (p.midi ? env : p.mix);
	float y = osc * p.mix * env * 0.5;
	outLeft = inLeft * x + y;
	outRight = inRight * x + y;
}

// Note: the only thing that should "leak" this quick silence input->output detection is if we use "midi mode" and have a "mix" of 0.
bool Sinoplex::willOutputBeSilent(const SinoplexProgram& p, bool inputIsSilent) {
	if (!inputIsSilent) {
		return false;
	} else if (isBypassing || p.am) {
		return true;
	} else if (!p.midi) {
		return (follower.getCurrent() == 0.0f);
	} else {
		return (envelope.getStage() == AREnvelope::kDead);
	}
}

struct AssignOp { void operator()(float& l, float r) { l = r; } };
struct AddOp { void operator()(float& l, float r) { l += r; } };

template<class OP> void Sinoplex::processTemplate(float** inputs, float** outputs, VstInt32 sampleFrames, OP op) {
	/*
		Use a copy of the program struct, so that any concurrent changes won't affect program flow logic etc.
		Notice, that this isn't perfect thread-safety. The fields may get modified concurrently while we copy the struct.
		This is not a problem in this plug-in though, since field sizes are max 32-bit and unrelated. The most important
		aspect here is that the fields stay consistent and don't change while we are in the processing loop.
	*/
	SinoplexProgram p = *const_cast<SinoplexProgram*>(currentProgram);

	processBegin(p);

	const float* leftInput = ((kInputCount > 0) ? inputs[0] : outputs[0]);
	const float* rightInput = ((kInputCount >= 2) ? inputs[1] : leftInput);
	float* leftOutput = outputs[0];
	float* rightOutput = ((kOutputCount >= 2) ? outputs[1] : leftOutput);
	float env;

	if (kInputCount == 0) {
		memset(leftOutput, 0, sampleFrames * sizeof (float));
	}

	outputIsSilent = willOutputBeSilent(p, inputIsSilent);
	if (outputIsSilent) {
		for (int i = 0; i < sampleFrames; ++i) {
			processOne(p, leftInput[i] + rightInput[i], env);
			op(leftOutput[i], 0.0f);
			op(rightOutput[i], 0.0f);
			if (kOutputCount >= 3) {
				op(outputs[2][i], 0.0f);
			}
			if (kOutputCount >= 4) {
				op(outputs[3][i], 0.0f);
			}
		}
	} else if (isBypassing) {
		for (int i = 0; i < sampleFrames; ++i) {
			processOne(p, leftInput[i] + rightInput[i], env);
			op(leftOutput[i], leftInput[i]);
			op(rightOutput[i], rightInput[i]);
			if (kOutputCount >= 3) {
				op(outputs[2][i], leftInput[i]);
			}
			if (kOutputCount >= 4) {
				op(outputs[3][i], rightInput[i]);
			}
		}
	} else if (p.am) {
		for (int i = 0; i < sampleFrames; ++i) {
			float osc = processOne(p, leftInput[i] + rightInput[i], env);
			float left;
			float right;
			applyAM(p, osc, env, leftInput[i], rightInput[i], left, right);
			op(leftOutput[i], left);
			op(rightOutput[i], right);
			if (kOutputCount >= 3) {
				op(outputs[2][i], -squaref(left));
			}
			if (kOutputCount >= 4) {
				op(outputs[3][i], -squaref(right));
			}
		}
	} else {
		for (int i = 0; i < sampleFrames; ++i) {
			float osc = processOne(p, leftInput[i] + rightInput[i], env);
			float left;
			float right;
			applyMix(p, osc, env, leftInput[i], rightInput[i], left, right);
			op(leftOutput[i], left);
			op(rightOutput[i], right);
			if (kOutputCount >= 3) {
				op(outputs[2][i], -squaref(left));
			}
			if (kOutputCount >= 4) {
				op(outputs[3][i], -squaref(right));
			}
		}
	}
}

// Note: not used by Symbiosis, but some (probably older) VST hosts still uses this.
void Sinoplex:: DECLARE_VST_DEPRECATED (process) (float **inputs, float **outputs, VstInt32 sampleFrames) {
	processTemplate(inputs, outputs, sampleFrames, AddOp());
}

void Sinoplex::processReplacing(float **inputs, float **outputs, VstInt32 sampleFrames) {
	processTemplate(inputs, outputs, sampleFrames, AssignOp());
}

VstInt32 Sinoplex::getTailSize() {
	// 10 secs is the max decay, it should be sufficient (I hope)
	return static_cast<VstInt32>(ceil(10.0 * getSampleRate() + 1));
}

VstInt32 Sinoplex::getGetTailSize() { // Typo in (some?) VST implementations.
	return getTailSize();
}

bool Sinoplex::getInputProperties(VstInt32 index, VstPinProperties* properties) {
	assert(0 <= index && index < kInputCount);
	memset(properties, 0, sizeof (*properties));
	sprintf(properties->label, "%s Input", (kInputCount == 1 ? "Mono" : "Stereo"));
	sprintf(properties->shortLabel, "%s In", (kInputCount == 1 ? "M." : "S."));
	if (index == 0 && kInputCount >= 2) {
		properties->flags |= kVstPinIsStereo;
	}
	return true;
}

bool Sinoplex::getOutputProperties(VstInt32 index, VstPinProperties* properties) {
	assert(0 <= index && index < kOutputCount);
	memset(properties, 0, sizeof (*properties));
	if (index < 2) {
		sprintf(properties->label, "%s Output", (kOutputCount < 2 ? "Mono" : "Stereo"));
		sprintf(properties->shortLabel, "%s Out", (kOutputCount < 2 ? "M." : "S."));
		if (index == 0 && kOutputCount >= 2) {
			properties->flags |= kVstPinIsStereo;
		}
	} else {
		sprintf(properties->label, "%s Aux", (kOutputCount < 4 ? "Mono" : "Stereo"));
		sprintf(properties->shortLabel, "%s Aux", (kOutputCount < 4 ? "M." : "S."));
		if (index == 2 && kOutputCount >= 4) {
			properties->flags |= kVstPinIsStereo;
		}
	}
	return true;
}

VstIntPtr Sinoplex::vendorSpecific(VstInt32 lArg1, VstIntPtr lArg2, void* ptrArg, float floatArg) {
	switch (lArg1) {
		case 'sHi!': return 1;																							// Can we speak Symbiosian?
		case 'sI00': inputIsSilent = (lArg2 != 0); return 1;															// Is input silent?
		case 'sO00': return outputIsSilent;																				// Is output silent?
		
		case 'sV2S': {																									// Parameter value to string conversion.
			float value = *reinterpret_cast<float*>(ptrArg);
			SinoplexProgram::Parameter param = static_cast<SinoplexProgram::Parameter>(lArg2);
			currentProgram->convertParameterValueToString(param, value, reinterpret_cast<char*>(ptrArg));
			return 1;
		}
		
		case 'sS2V': {																									// String to parameter value conversion.
			SinoplexProgram::Parameter param = static_cast<SinoplexProgram::Parameter>(lArg2);
			float value = currentProgram->convertParameterStringToValue(param, reinterpret_cast<char*>(ptrArg));
			*reinterpret_cast<float*>(ptrArg) = value;
			return 1;
		}

		default: return AudioEffectX::hostVendorSpecific(lArg1, lArg2, ptrArg, floatArg);
	}
	
	return 0;
}

/*
Sinoplex::~Sinoplex()
{
	const char* kLFOWaveformEnumStrings[4] = { "kSine", "kSquare", "kSawDown", "kSawUp" };
	for (int i = 0; i < kProgramCount; ++i) {
		const SinoplexProgram& p = programs[i];
		printf(", { \"%s\", %.2ff, %.2ff, %.2ff, %s, SinoplexProgram::%s, %s, %.2ff, %.2ff, %.2ff, %s, %s, %.2ff }\n", p.name, p.freq, p.lfoAmount, p.envAmount, p.envInvert ? "true" : "false", kLFOWaveformEnumStrings[static_cast<int>(p.lfoWaveform)], p.lfoSync ? "true" : "false", p.lfoRate, p.envAttack, p.envDecay, p.midi ? "true" : "false", p.am ? "true" : "false", p.mix);
	}
}
*/

#if defined (__GNUC__)
	#define VST_EXPORT	__attribute__ ((visibility ("default")))
#else
	#define VST_EXPORT
#endif

extern "C" VST_EXPORT AEffect* VSTPluginMain(audioMasterCallback audioMaster) {
	if (audioMaster(0, audioMasterVersion, 0, 0, 0, 0)) {
		Sinoplex* effect = new Sinoplex(audioMaster);
		return effect->getAeffect();
	}
	return 0;
}

#if (IS_WINDOWS)
	__declspec(dllexport) void* main(audioMasterCallback audioMaster) { return VSTPluginMain(audioMaster); }

	::BOOL WINAPI DllMain(::HINSTANCE hinstDLL, ::DWORD fdwReason, ::LPVOID lpvReserved) {
		static _CrtMemState memoryCheckPoint;
		switch (fdwReason) {
			case DLL_PROCESS_ATTACH: // Indicates that the DLL is being loaded into the virtual address space of the current process as a result of the process starting up or as a result of a call to LoadLibrary. DLLs can use this opportunity to initialize any instance data or to use the TlsAlloc function to allocate a thread local storage (TLS) index. 
				_CrtMemCheckpoint(&memoryCheckPoint);
				break;

			case DLL_PROCESS_DETACH: // Indicates that the DLL is being unloaded from the virtual address space of the calling process as a result of either a process exit or a call to FreeLibrary. The DLL can use this opportunity to call the TlsFree function to free any TLS indices allocated by using TlsAlloc and to free any thread local data.
				_CrtMemDumpStatistics(&memoryCheckPoint);
				_CrtMemDumpAllObjectsSince(&memoryCheckPoint);
				break;
		}
		return TRUE;
	}
#elif (IS_MAC)
	extern "C" __attribute__((visibility("default"))) AEffect *main_macho(audioMasterCallback audioMaster) { return VSTPluginMain(audioMaster); }
#endif
