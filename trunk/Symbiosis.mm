/**
	\file Symbiosis.cpp

	NuEdge Development Symbiosis AU / VST portability tools.
	
	\version

	Version 1.29b

	\page Copyright

	Symbiosis is released under the "New Simplified BSD License". http://www.opensource.org/licenses/bsd-license.php
	
	Copyright (c) 2010-2011, NuEdge Development / Magnus Lidstroem
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

#include <Carbon/Carbon.h>
#include <AudioUnit/AudioUnit.h>
#include <AudioToolbox/AudioUnitUtilities.h>
#include <mach-o/dyld.h>
#include <mach-o/ldsyms.h>
#include <pthread.h>
#include <stdio.h>
#include <assert.h>
#include <exception>
#include <new>

#if !defined(SY_INCLUDE_GUI_SUPPORT)
	#define SY_INCLUDE_GUI_SUPPORT 1
#endif

#if !defined(SY_USE_COCOA_GUI)
	#if __LP64__
		#define SY_USE_COCOA_GUI 1
	#else
		#define SY_USE_COCOA_GUI 0
	#endif
#endif

#if (SY_USE_COCOA_GUI)
	#import <Cocoa/Cocoa.h>
	#import <AudioUnit/AUCocoaUIView.h>
	#import "objc/runtime.h"
#elif (!SY_USE_COCOA_GUI)
	#include <AudioUnit/AudioUnitCarbonView.h>
#endif

#if !defined(SY_USE_VST_VERSION)	// See Symbiosis_Prefix.pch for information on this define.
	#if defined(kVstVersion)		// If the VST SDK is in precompiled header, use kVstVersion defined in aeffect.h
		#define SY_USE_VST_VERSION kVstVersion
	#elif !defined(kVstVersion)
		#define SY_USE_VST_VERSION 2400
	#endif
#endif

#if (SY_USE_VST_VERSION == 2400)
	#ifndef __aeffectx__
		#include "VST2400/pluginterfaces/vst2.x/aeffectx.h"
	#endif
	#ifndef __aeffeditor__
		#include "VST2400/public.sdk/source/vst2.x/aeffeditor.h"
	#endif
#elif (SY_USE_VST_VERSION == 2300)
	#include "VST2300/source/common/vstplugsmacho.h"
	#include "VST2300/source/common/aeffectx.h"
	#include "VST2300/source/common/AEffEditor.hpp"
	#define DECLARE_VST_DEPRECATED(x) x
	typedef short VstInt16;
	typedef int VstInt32;
	typedef long VstIntPtr;
#else
	#error Unsupported VST SDK version!
#endif

/* --- Configuration macros --- */

#if !defined(SY_DO_TRACE)
	#define SY_DO_TRACE (!defined(NDEBUG))
#endif
#if !defined(SY_DO_ASSERT)
	#define SY_DO_ASSERT (!defined(NDEBUG))
#endif

#if !defined(SY_STD_TRACE)
	#define SY_STD_TRACE 1
#endif
#if !defined(SY_STD_ASSERT)
	#define SY_STD_ASSERT 1
#endif

#if (SY_DO_TRACE)

	#if !defined(SY_TRACE_MISC)
		#define SY_TRACE_MISC 1
	#endif
	#if !defined(SY_TRACE_EXCEPTIONS)
		#define SY_TRACE_EXCEPTIONS 1
	#endif
	#if !defined(SY_TRACE_AU)
		#define SY_TRACE_AU 1
	#endif
	#if !defined(SY_TRACE_VST)
		#define SY_TRACE_VST 1
	#endif
	#if !defined(SY_TRACE_FREQUENT)
		#define SY_TRACE_FREQUENT 0
	#endif
	#if (SY_STD_TRACE)
		#define SY_TRACE(c, s) { if (c) fprintf(stderr, "[%s](%p) " s "\n", gTraceIdentifierString, ::pthread_self()); }
		#define SY_TRACE1(c, s, a1) { if (c) fprintf(stderr, "[%s](%p) " s "\n", gTraceIdentifierString, ::pthread_self(), (a1)); }
		#define SY_TRACE2(c, s, a1, a2) { if (c) fprintf(stderr, "[%s](%p) " s "\n", gTraceIdentifierString, ::pthread_self(), (a1), (a2)); }
		#define SY_TRACE3(c, s, a1, a2, a3) { if (c) fprintf(stderr, "[%s](%p) " s "\n", gTraceIdentifierString, ::pthread_self(), (a1), (a2), (a3)); }
		#define SY_TRACE4(c, s, a1, a2, a3, a4) { if (c) fprintf(stderr, "[%s](%p) " s "\n", gTraceIdentifierString, ::pthread_self(), (a1), (a2), (a3), (a4)); }
		#define SY_TRACE5(c, s, a1, a2, a3, a4, a5) { if (c) fprintf(stderr, "[%s](%p) " s "\n", gTraceIdentifierString, ::pthread_self(), (a1), (a2), (a3), (a4), (a5)); }
		#define SY_TRACE_STOP
	#endif

#elif (!SY_DO_TRACE)

	#define SY_TRACE(c, s)
	#define SY_TRACE1(c, s, a1)
	#define SY_TRACE2(c, s, a1, a2)
	#define SY_TRACE3(c, s, a1, a2, a3)
	#define SY_TRACE4(c, s, a1, a2, a3, a4)
	#define SY_TRACE5(c, s, a1, a2, a3, a4, a5)
	#define SY_TRACE_STOP
	
#endif

#if (SY_DO_ASSERT)
	#if (SY_STD_ASSERT)
		#define SY_ASSERT(x) assert(x)
	#endif
	#define SY_ASSERT0(x, d) { if (!(x)) { SY_TRACE(1, d); } SY_ASSERT(x); }
	#define SY_ASSERT1(x, d, a1) { if (!(x)) { SY_TRACE1(1, d, a1); } SY_ASSERT(x); }
	#define SY_ASSERT2(x, d, a1, a2) { if (!(x)) { SY_TRACE2(1, d, a1, a2); } SY_ASSERT(x); }
	#define SY_ASSERT3(x, d, a1, a2, a3) { if (!(x)) { SY_TRACE3(1, d, a1, a2, a3); } SY_ASSERT(x); }
	#define SY_ASSERT4(x, d, a1, a2, a3, a4) { if (!(x)) { SY_TRACE4(1, d, a1, a2, a3, a4); } SY_ASSERT(x); }
	#define SY_ASSERT5(x, d, a1, a2, a3, a4, a5) { if (!(x)) { SY_TRACE5(1, d, a1, a2, a3, a4); } SY_ASSERT(x); }
#elif (!SY_DO_ASSERT)
	#define SY_ASSERT(x)
	#define SY_ASSERT0(x, d)
	#define SY_ASSERT1(x, d, a1)
	#define SY_ASSERT2(x, d, a1, a2)
	#define SY_ASSERT3(x, d, a1, a2, a3)
	#define SY_ASSERT4(x, d, a1, a2, a3, a4)
	#define SY_ASSERT5(x, d, a1, a2, a3, a4)
#endif

#define SY_COMPONENT_CATCH(N) \
		catch (const MacOSException& x) { \
			SY_TRACE1(SY_TRACE_EXCEPTIONS, "Caught Mac OS exception in " N ": %s", x.what()); \
			return x.GetOSErrorCode(); \
		} \
		catch (const EOFException& x) { \
			SY_TRACE(SY_TRACE_EXCEPTIONS, "Caught end of file exception in " N); \
			return eofErr; \
		} \
		catch (const std::bad_alloc&) { \
			SY_TRACE(SY_TRACE_EXCEPTIONS, "Caught std::bad_alloc in " N); \
			return memFullErr; \
		} \
		catch (const std::exception& x) { \
			SY_TRACE1(SY_TRACE_EXCEPTIONS, "Caught exception in " N ": %s", x.what()); \
			return -32767; \
		} \
		catch (...) { \
			SY_TRACE(SY_TRACE_EXCEPTIONS, "Caught general exception in " N); \
			return -32767; \
		}

#if __LP64__
	// comp instance, parameters in forward order
	#define PARAM(_typ, _name, _index, _nparams) \
		_typ _name = *(_typ *)&params->params[_index + 1];
#else
	// parameters in reverse order, then comp instance
	#define PARAM(_typ, _name, _index, _nparams) \
		_typ _name = *(_typ *)&params->params[_nparams - 1 - _index];
#endif

#if (__MAC_OS_X_VERSION_MAX_ALLOWED < 1050)
	#if __LP64__
		typedef int FSIORefNum;
	#else
		typedef SInt16 FSIORefNum;
	#endif
#endif

/* --- Configuration constants --- */

static const char* kSymbiosisVSTVendorString = "NuEdge Development";
static const char* kSymbiosisVSTProductString = "Symbiosis";
static const int kSymbiosisVSTVersion = 0x010000;
static const int kIdleIntervalMS = 25;
static const int kMaxPropertyListeners = 128;
static const int kMaxAURenderCallbacks = 128;
static const int kMaxChannels = 32;
static const int kMaxBuses = 32;
static const int kMaxVSTMIDIEvents = 1024;
static const int kMaxFactoryPresets = 128;
static const int kMaxMappedParameters = 1024;
static const double kDefaultSampleRate = 44100.0;
static const int kDefaultMaxFramesPerSlice = 4096;
static const char* kAUPresetExtension = ".aupreset";
static const int kParametersFileNameChars = 16;
static const ::UniChar kParametersFileName[kParametersFileNameChars] = {
	'S', 'Y', 'P', 'a', 'r', 'a', 'm', 'e', 't', 'e', 'r', 's', '.', 't', 'x', 't'
};
static const int kFactoryPresetsFileNameChars = 20;
static const ::UniChar kFactoryPresetsFileName[kFactoryPresetsFileNameChars] = {
	'S', 'Y', 'F', 'a', 'c', 't', 'o', 'r', 'y', 'P', 'r', 'e', 's', 'e', 't', 's', '.', 't', 'x', 't'
};
static const int kDefaultFactoryPresetFileNameChars = 22;
static const ::UniChar kDefaultFactoryPresetFileName[kDefaultFactoryPresetFileNameChars] = {
	'F', 'a', 'c', 't', 'o', 'r', 'y', 'P', 'r', 'e', 's', 'e', 't', '.', 'a', 'u', 'p', 'r', 'e', 's', 'e', 't'
};
static const int kDefaultFactoryPresetFileNameCRChars = 23;
static const char kDefaultFactoryPresetFileNameCR[kDefaultFactoryPresetFileNameCRChars + 1]
		= "FactoryPreset.aupreset\r";																					// Yeah, I know, lazy to have another almost identical constant.
static const char* kDefaultFactoryPresetName = "Default";
static const char* kInitialPresetName = "Untitled";
static char gTraceIdentifierString[255 + 1] = "Symbiosis";
static const int kSymbiosisThngResourceId = 10000;
static const int kSymbiosisAUViewThngResourceId = 10001;
#if defined(__POWERPC__)
	static const int kBigEndianPCMFlag = kLinearPCMFormatFlagIsBigEndian;
#elif !defined(__POWERPC__)
	static const int kBigEndianPCMFlag = 0;
#endif

/* --- Exception classes --- */

class SymbiosisException : public std::exception {
	public:		explicit SymbiosisException(const char string[] = "General exception") throw() {
					strncpy(errorString, string, 255); errorString[255] = '\0';
				}
    public:		virtual const char* what() const throw() { return errorString; }
	protected:	char errorString[255 + 1];
};

class EOFException : public SymbiosisException {
    public:		explicit EOFException(const char string[] = "End of file error") throw() : SymbiosisException(string) {
				}
};

class FormatException : public SymbiosisException {
    public:		explicit FormatException(const char string[] = "Invalid data format") throw()
						: SymbiosisException(string) { }
};

class MacOSException : public std::exception {
	public:		explicit MacOSException(::OSStatus error) throw() : errorCode(error) { errorString[0] = '\0'; }
    public:		virtual const char* what() const throw()
				{
					if (errorString[0] == '\0') {
						sprintf(errorString, "Mac OS error code %d", static_cast<int>(errorCode));
					}
					return errorString;
				}
	public:		::OSStatus GetOSErrorCode() const { return errorCode; }
	protected:	mutable char errorString[255 + 1];
	protected:	::OSStatus errorCode;
};

/* --- Utility routines --- */

static inline void throwOnOSError(::OSStatus err) throw(MacOSException) {
	if (err != noErr) {
		throw MacOSException(err);
	}
}

static inline void throwOnNull(const void* p, const char s[]) throw(SymbiosisException) {
	if (p == 0) {
		throw SymbiosisException(s);
	}
}

static inline void releaseCFRef(::CFTypeRef* cf) throw() {
	SY_ASSERT(cf != 0);

	if ((*cf) != 0) {
		::CFRelease(*cf);
		(*cf) = 0;
	}
}

static void getPathForThisImage(char path[1023 + 1]) throw(SymbiosisException) {
	SY_ASSERT(path != 0);
	
	int image_count = _dyld_image_count();
	for (int i = 0; i < image_count; ++i) {
		if (reinterpret_cast<const void*>(_dyld_get_image_header(i))
				== reinterpret_cast<const void*>(&_mh_bundle_header)) {
			strncpy(path, _dyld_get_image_name(i), 1023);
			path[1023] = '\0';
			SY_TRACE3(SY_TRACE_MISC, "Found my image (%s) at %d of %d", path, i, image_count);
			return;
		}
	}
	throw SymbiosisException("Could not find image for current bundle");
}

static void addIntToDictionary(::CFMutableDictionaryRef dictionaryRef, ::CFStringRef keyRef, ::SInt32 value) throw() {
	SY_ASSERT(dictionaryRef != 0);
	SY_ASSERT(::CFGetTypeID(dictionaryRef) == ::CFDictionaryGetTypeID());
	SY_ASSERT(keyRef != 0);
	SY_ASSERT(::CFGetTypeID(keyRef) == ::CFStringGetTypeID());

	::CFNumberRef numberRef = ::CFNumberCreate(0, kCFNumberSInt32Type, &value);
	SY_ASSERT(numberRef != 0);
	::CFDictionarySetValue(dictionaryRef, keyRef, numberRef);
	releaseCFRef((::CFTypeRef*)&numberRef);
}

static ::CFTypeRef getValueOfKeyInDictionary(::CFDictionaryRef dictionaryRef, ::CFStringRef keyRef
		, ::CFTypeID expectedType) throw(SymbiosisException) {
	SY_ASSERT(dictionaryRef != 0);
	SY_ASSERT(::CFGetTypeID(dictionaryRef) == ::CFDictionaryGetTypeID());
	SY_ASSERT(keyRef != 0);
	SY_ASSERT(::CFGetTypeID(keyRef) == ::CFStringGetTypeID());

	::CFTypeRef valueRef = 0;
	throwOnNull(valueRef = ::CFDictionaryGetValue(dictionaryRef, keyRef), "Missing key in dictionary");
	if (::CFGetTypeID(valueRef) != expectedType) {
		throw FormatException("Value in dictionary is not of expected type");
	}
	return valueRef;
}

static void checkIntInDictionary(::CFDictionaryRef dictionaryRef, ::CFStringRef keyRef, int expectedValue)
		throw(SymbiosisException) {
	::SInt32 value;
	::CFNumberGetValue(reinterpret_cast< ::CFNumberRef >(getValueOfKeyInDictionary(dictionaryRef, keyRef
			, ::CFNumberGetTypeID())), kCFNumberSInt32Type, &value);
	if (value != expectedValue) {
		throw FormatException("Data in dictionary is not of expected value");
	}
}

static const char* cfStringToCString(::CFStringRef stringRef, ::CFStringEncoding encoding, char buffer[]
		, int maxStringLength) throw() {
	SY_ASSERT(stringRef != 0);
	SY_ASSERT(::CFGetTypeID(stringRef) == ::CFStringGetTypeID());
	SY_ASSERT(buffer != 0);
	SY_ASSERT(maxStringLength >= 0);

	const char* stringPointer = ::CFStringGetCStringPtr(stringRef, encoding);
	if (stringPointer == 0) {
		::Boolean wasOK = ::CFStringGetCString(stringRef, buffer, maxStringLength + 1, encoding);
		SY_ASSERT(wasOK);
		stringPointer = buffer;
	}
	return stringPointer;
}

static unsigned char* writeBigInt32(unsigned char* p, int x) throw() {
	SY_ASSERT(p != 0);

#if defined(__POWERPC__)
	*reinterpret_cast<int*>(p) = x;
	return p + 4;
#elif !defined(__POWERPC__)
	*p++ = static_cast<unsigned char>((x >> 24) & 0xFF);
	*p++ = static_cast<unsigned char>((x >> 16) & 0xFF);
	*p++ = static_cast<unsigned char>((x >> 8) & 0xFF);
	*p++ = static_cast<unsigned char>((x >> 0) & 0xFF);
	return p;
#endif
}

// Attention: this code expects the C++ representation of float to be in IEEE 754 format!
static inline unsigned char* writeBigFloat32(unsigned char* p, float x) throw() {
	SY_ASSERT(p != 0);
	SY_ASSERT(sizeof (float) == 4 && sizeof (int) == 4);

	return writeBigInt32(p, *reinterpret_cast<int*>(&x));
}

static const unsigned char* readBigInt32(const unsigned char* p, const unsigned char* e, int* x) throw(EOFException) {
	SY_ASSERT(p != 0);
	SY_ASSERT(e != 0);
	SY_ASSERT(x != 0);

	if (p + 4 > e) {
		throw EOFException();
	}
#if defined(__POWERPC__)
	(*x) = *reinterpret_cast<const int*>(p);
#elif !defined(__POWERPC__)
	(*x) = (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3];
#endif
	return p + 4;
}

// Attention: this code expects the C++ representation of float to be in IEEE 754 format!
static inline const unsigned char* readBigFloat32(const unsigned char* p, const unsigned char* e, float* x)
		throw(EOFException) {
	SY_ASSERT(p != 0);
	SY_ASSERT(e != 0);
	SY_ASSERT(x != 0);
	SY_ASSERT(sizeof (float) == 4 && sizeof (int) == 4);
	
	return readBigInt32(p, e, reinterpret_cast<int*>(x)); 
}

static const unsigned char* readLine(const unsigned char* p, const unsigned char* e, char* string, int maxStringLength)
		throw(EOFException) {
	SY_ASSERT(p != 0);
	SY_ASSERT(e != 0);
	SY_ASSERT(string != 0);
	SY_ASSERT(maxStringLength >= 0);
	
	if (p >= e) {
		throw EOFException();
	}
	char* s = string;
	while (p < e && (*p) != '\r' && (*p) != '\n') {
		if (s < &string[maxStringLength]) {
			*s++ = *p++;
		}
	}
	*s = '\0';
	if (p < e && (*p) == '\r') {
		++p;
	}
	if (p < e && (*p) == '\n') {
		++p;
	}
	return p;
}

static inline const char* eatSpace(const char* p) throw() {
	SY_ASSERT(p != 0);
	
	while (*p == ' ') {
		++p;
	}
	return p;
}

#if (SY_DO_TRACE && SY_INCLUDE_GUI_SUPPORT && !SY_USE_COCOA_GUI)
static void traceControlInfo(const char* s, ::ControlRef controlRef) throw(MacOSException) {
	if (controlRef == 0) {
		SY_TRACE2(SY_TRACE_MISC, "%s: @0x%8.8x", s, 0);
	} else {
		::ControlKind controlKind;
		throwOnOSError(::GetControlKind(controlRef, &controlKind));
		char buffer1[5]; *(reinterpret_cast< ::OSType* >(buffer1)) = controlKind.signature; buffer1[4] = '\0';
		char buffer2[5]; *(reinterpret_cast< ::OSType* >(buffer2)) = controlKind.kind; buffer2[4] = '\0';
		SY_TRACE4(SY_TRACE_MISC, "%s: @0x%8.8x %s/%s", s, reinterpret_cast<unsigned int>(controlRef), buffer1
				, buffer2);
	}
}
#endif

static void descendOrCreateFolder(const ::FSRef* parentFSRef, size_t nameLength, const char* name, ::FSRef* folderFSRef)
		throw(MacOSException) {
	SY_ASSERT(parentFSRef != 0);
	SY_ASSERT(nameLength > 0);
	SY_ASSERT(name != 0);
	SY_ASSERT(folderFSRef != 0);
	
	::UniChar uniName[1024];
	for (size_t i = 0; i < nameLength; ++i) {
		SY_ASSERT1((name[i] >= ' ' && name[i] < 127), "Folder name contained invalid character (ascii %d)", name[i]);
		uniName[i] = name[i];
	}
	::OSErr err = ::FSMakeFSRefUnicode(parentFSRef, nameLength, uniName, kTextEncodingUnknown, folderFSRef);
	if (err == fnfErr) {
		throwOnOSError(::FSCreateDirectoryUnicode(parentFSRef, nameLength, uniName, kFSCatInfoNone, 0, folderFSRef
				, 0, 0));
	} else {
		throwOnOSError(err);
	}
}

static unsigned char* loadFromFile(const ::FSRef* fsRef, size_t& size) throw(MacOSException, SymbiosisException) {
	SY_ASSERT(fsRef != 0);
	
	unsigned char* bytes = 0;
	::FSIORefNum fileFork = 0;
	bool isForkOpen = false;

	try {
		::HFSUniStr255 dataForkName;
		throwOnOSError(::FSGetDataForkName(&dataForkName));
		throwOnOSError(::FSOpenFork(fsRef, dataForkName.length, dataForkName.unicode, fsRdPerm, &fileFork));
		isForkOpen = true;
		::SInt64 forkSize;
		throwOnOSError(::FSGetForkSize(fileFork, &forkSize));
		if (static_cast< ::ByteCount >(forkSize) != static_cast< ::UInt64 >(forkSize)) {
			throw SymbiosisException("File size too large");
		}
		size = static_cast<size_t>(forkSize);
		bytes = new unsigned char[size];
		::ByteCount actualCount;
		throwOnOSError(::FSReadFork(fileFork, fsFromStart, 0, static_cast< ::ByteCount >(forkSize), bytes, &actualCount));
		SY_ASSERT(actualCount == static_cast< ::ByteCount >(forkSize));
		::OSErr err = ::FSCloseFork(fileFork);
		SY_ASSERT(err == noErr);
		isForkOpen = false;
	}
	catch (...) {
		if (isForkOpen) {
			::OSErr err = ::FSCloseFork(fileFork);
			SY_ASSERT(err == noErr);
			isForkOpen = false;
		}
		delete [] bytes;
		bytes = 0;
		throw;
	}
	return bytes;
}

static void saveToFile(const ::FSRef* fsRef, size_t size, const unsigned char bytes[]) throw(MacOSException) {
	SY_ASSERT(fsRef != 0);
	SY_ASSERT(size == 0 || bytes != 0);

	::FSIORefNum fileFork = 0;
	bool isForkOpen = false;

	try {
		::HFSUniStr255 dataForkName;
		throwOnOSError(::FSGetDataForkName(&dataForkName));
		throwOnOSError(::FSOpenFork(fsRef, dataForkName.length, dataForkName.unicode, fsWrPerm, &fileFork));
		isForkOpen = true;
		if (size > 0) {
			::ByteCount actualCount;
			throwOnOSError(::FSWriteFork(fileFork, fsFromStart, 0, size, bytes, &actualCount));
			SY_ASSERT(actualCount == size);
		}
		::OSErr err = ::FSCloseFork(fileFork);
		SY_ASSERT(err == noErr);
		isForkOpen = false;
	}
	catch (...) {
		if (isForkOpen) {
			::OSErr err = ::FSCloseFork(fileFork);
			SY_ASSERT(err == noErr);
			isForkOpen = false;
		}
		throw;
	}
}

static ::CFPropertyListRef loadProperties(const ::FSRef* fsRef) throw(SymbiosisException) {
	SY_ASSERT(fsRef != 0);
	
	::CFStringRef error = 0;
	::CFMutableDataRef data = 0;
	::CFPropertyListRef properties = 0;
	unsigned char* bytes = 0;
	try {
		size_t size = 0;
		bytes = loadFromFile(fsRef, size);
		data = ::CFDataCreateMutable(0, size);
		SY_ASSERT(data != 0);
		::CFDataAppendBytes(data, bytes, size);
		delete [] bytes;
		bytes = 0;
		properties = ::CFPropertyListCreateFromXMLData(0, data, kCFPropertyListImmutable, &error);
		releaseCFRef((::CFTypeRef*)&data);
		if (properties == 0) {
			if (error != 0) {
				char buffer1[1023 + 1];
				const char* errorString = cfStringToCString(error, kCFStringEncodingMacRoman, buffer1, 1023);
				releaseCFRef((::CFTypeRef*)&error);
				char buffer2[1023 + 1];
				snprintf(buffer2, 1023 + 1, "Could not create property list from XML data (%s)", errorString);
				throw SymbiosisException(buffer2);
			} else {
				throw SymbiosisException("Could not create property list from XML data");
			}
		}
	}
	catch (...) {
		delete [] bytes;
		bytes = 0;
		releaseCFRef((::CFTypeRef*)&data);
		releaseCFRef((::CFTypeRef*)&error);
		releaseCFRef((::CFTypeRef*)&properties);
		throw;
	}
	return properties;
}

static void saveProperties(::CFPropertyListRef propertyList, const ::FSRef* fsRef) {
	SY_ASSERT(propertyList != 0);
	SY_ASSERT(fsRef != 0);
	
	::CFDataRef data = 0;
	try {
		data = ::CFPropertyListCreateXMLData(0, propertyList);
		SY_ASSERT(data != 0);
		saveToFile(fsRef, ::CFDataGetLength(data), ::CFDataGetBytePtr(data));
		releaseCFRef((::CFTypeRef*)&data);
	}
	catch (...) {
		releaseCFRef((::CFTypeRef*)&data);
		throw;
	}
}

static void releaseBundleRef(::CFBundleRef& bundleRef) {
	if (bundleRef != 0) {
		::CFIndex retainCount = ::CFGetRetainCount(bundleRef);
		SY_TRACE1(SY_TRACE_MISC, "Bundle retain count before releasing: %ld", retainCount);
		if (retainCount == 1) {
			::CFBundleUnloadExecutable(bundleRef);
			SY_TRACE(SY_TRACE_MISC, "Unloaded bundle executable");
		}
		releaseCFRef((::CFTypeRef*)&bundleRef);
	}
}

/* --- SymbiosisVstEvents --- */

#if TARGET_API_MAC_CARBON && defined(__LP64__)
	#pragma options align=power
#elif TARGET_API_MAC_CARBON || PRAGMA_STRUCT_ALIGN || __MWERKS__
	#pragma options align=mac68k
#elif defined __BORLANDC__
	#pragma -a8
#elif defined(WIN32) || defined(__FLAT__)
	#pragma pack(push)
	#pragma pack(8)
#endif
struct SymbiosisVstEvents {																								// Attention, this struct is a customization of VstEvents and must match with field alignment etc
	VstInt32 numEvents;
	VstIntPtr reserved;
	VstEvent* events[kMaxVSTMIDIEvents];
};
#if TARGET_API_MAC_CARBON || PRAGMA_STRUCT_ALIGN || __MWERKS__
	#pragma options align=reset
#elif defined(WIN32) || defined(__FLAT__)
	#pragma pack(pop)
#elif defined __BORLANDC__
	#pragma -a-
#endif

/**
	SymbiosisAudioBufferList is a customization of AudioBufferList (with a fixed number of AudioBuffers) and must match
	the AudioBufferList struct concerning field alignment etc.
*/
struct SymbiosisAudioBufferList {
	UInt32		mNumberBuffers;
	AudioBuffer	mBuffers[kMaxChannels];
};

/* --- AUPropertyListener --- */

struct AUPropertyListener {
	::AudioUnitPropertyID fPropertyID;
	::AudioUnitPropertyListenerProc fListenerProc;
	void* fListenerRefCon;
};

class VSTPlugIn;

/**
	VSTHost is an "interface class" for handling "callbacks" to the host from a vst plug-in.
*/
class VSTHost {
	public:		virtual void getVendor(VSTPlugIn& plugIn, char vendor[63 + 1]) = 0;										///< Fill \p vendor with unique vendor name of up to 63 characters for this host.
	public:		virtual void getProduct(VSTPlugIn& plugIn, char product[63 + 1]) = 0;									///< Fill \p product with unique product name of up to 63 characters for this host.
	public:		virtual VstInt32 getVersion(VSTPlugIn& plugIn) = 0;														///< Return the version of the host as an integer.
	public:		virtual bool canDo(VSTPlugIn& plugIn, const char string[]) = 0;											///< Return true if the host supports the feature specified in \p string. 
	public:		virtual VstTimeInfo* getTimeInfo(VSTPlugIn& plugIn, VstInt32 flags) = 0;								///< Fill out a valid (and static) VstTimeInfo struct (according to \p flags) and return a pointer to this struct. Return 0 if timing info cannot be provided at all.
	public:		virtual void beginEdit(VSTPlugIn& plugIn, VstInt32 parameterIndex) = 0;									///< Indicates that the user is starting to edit parameter \p parameterIndex (for instance, by clicking the mouse button in a controller).
	public:		virtual void automate(VSTPlugIn& plugIn, VstInt32 parameterIndex, float value) = 0;						///< Parameter \p parameterIndex is being changed to \p value by the plug-in (you may record this change for automation).
	public:		virtual void endEdit(VSTPlugIn& plugIn, VstInt32 parameterIndex) = 0;									///< Indicates that the user has stopped editing parameter \p parameterIndex (for instance, by releasing the mouse button in a controller).
	public:		virtual bool isIOPinConnected(VSTPlugIn& plugIn, bool checkOutputPin, VstInt32 pinIndex) = 0;			///< If \p checkOutputPin is true, return true if plug-in output of index \p pinIndex is connected and used by the host. If \p checkOutputPin is false, return true if plug-in input is connected. 
	public:		virtual void idle(VSTPlugIn& plugIn) = 0;																///< The plug-in may issue this callback when it's GUI is busy, preventing the standard event loop from driving idling.
	public:		virtual void updateDisplay(VSTPlugIn& plugIn) = 0;														///< Some fact about the plug-in has changed and this should be reflected in the GUI host. Most frequently used to indicate that a program name has changed.
	public:		virtual void resizeWindow(VSTPlugIn& plugIn, VstInt32 width, VstInt32 height) = 0;						///< Plug-in is requesting that it's window should be resized.
	public:		virtual ~VSTHost() { };
};

/**
	VSTPlugin encapsulates a single instance of a VST plug-in.
*/
class VSTPlugIn {
	public:		VSTPlugIn(VSTHost& host, ::CFBundleRef bundleRef, float sampleRate = 44100.0f, VstInt32 blockSize = 0);	///< Construct a VST plug-in instance from the bundle referred to by \p bundleRef. Notice that the instance isn't usable until a successful call to open() has been made. \p host is your implementation of the host-interface with all the callbacks that the plug-in may use. \p sampleRate and \p blockSize are initial settings, you may set new rate and block-size with setSampleRate() and setBlockSize().
	public:		bool isOpen() const;																					///< Returns true if the plug-in instance has been successfully opened. (May be called before open().)
	public:		bool isEditorOpen() const;																				///< Returns true if the plug-in custom editor is currently open. (May be called before open().)
	public:		bool isResumed() const;																					///< Returns true if the plug-in is currently in resumed / running state (i.e. not suspended). (May be called before open().)
	public:		bool hasEditor() const;																					///< Returns true if the plug-in has implemented a custom editor. (May be called before open().)
	public:		bool canProcessReplacing() const;																		///< Returns true if the processReplacing() function is supported. (May be called before open().)
	public:		bool hasProgramChunks() const;																			///< Returns true if the plug-in wants to perform its own serialization of programs (and banks) as opposed to the host just storing program names and parameters. (May be called before open().)
	public:		bool dontProcessSilence() const;																		///< Returns true if passing digital silence to the plug-in effect means that the output will also always be silent. (May be called before open().)
	public:		VstInt32 getProgramCount() const;																		///< Returns the number of programs in a bank. You can expect the number of programs to stay constant during the life-time of the plug-in. (May be called before open().)
	public:		VstInt32 getParameterCount() const;																		///< Returns the number of parameters. You can expect the number of parameters to stay constant during the life-time of the plug-in. (May be called before open().)
	public:		VstInt32 getInputCount() const;																			///< Returns the number of input channels. You can expect the number of input channels to stay constant during the life-time of the plug-in. (May be called before open().)
	public:		VstInt32 getOutputCount() const;																		///< Returns the number of output channels. You can expect the number of output channels to stay constant during the life-time of the plug-in. (May be called before open().)
	public:		VstInt32 getInitialDelay() const;																		///< Returns the latency of the plug-in in samples. You need to "preroll" audio and MIDI data for the plug-in by this many samples. (May be called before open().)
	public:		void setSampleRate(float sampleRate);																	///< Updates the audio sample-rate. May be called at any time during processing (and even before calling open()), but it is a "polite behaviour" to surround this call with a pair of suspend() and resume() calls.
	public:		void setBlockSize(VstInt32 blockSize);																	///< Updates the block-size (i.e. the number of samples that you want to process with each process-call). Setting this before processing may improve plug-in performance, but if set you should always use the same number of samples. A block-size of 0 may be used if you don't know the block-size beforehand and need to process a variable number of samples with each process-call.
	public:		void open();																							///< Opens and initializes the plug-in. This is the method that actually loads the plug-in binary into memory (if this is the first instance) and makes the necessary initialization calls to the plug-in. Expect to receive callbacks to your VSTHost interface. The plug-in will be started in suspended state, so a call to resume() is necessary before processing. It is illegal to call open() more than once for a plug-in instance.
	public:		VstInt32 getVersion();																					///< Obtains the version number of the plug-in.
	public:		void setCurrentProgram(VstInt32 program);																///< Change current program selection in the plug-in to \p program (zero-based). \p program must be less than the value returned by getProgramCount(). Notice that the plug-in may also change the program selection at will.
	public:		VstInt32 getCurrentProgram();																			///< Obtains the current program selection (zero-based).
	public:		void getCurrentProgramName(char programName[24 + 1]);													///< Obtains the name of the current program. The string is truncated to max 24 characters.
	public:		void setCurrentProgramName(const char programName[24 + 1]);												///< Update the current program name to \p programName. Make sure the string is max 24 characters and null-terminated.
	public:		bool getProgramName(VstInt32 programIndex, char programName[24 + 1]);									///< Obtains the name program name of a specific zero-based program index (without changing the current program selection). If false is returned, this method is not supported by the plug-in and you need to resort to using getCurrentProgram().
	public:		float getParameter(VstInt32 parameterIndex);															///< Obtains the current parameter value of the zero-based parameter index. All VST parameter values are floating point between 0.0 and 1.0. \p parameterIndex must be less than the value returned by getParameterCount().
	public:		void setParameter(VstInt32 parameterIndex, float value);												///< Updates the parameter \p parameterIndex to \p value. Notice that some plug-ins quantizes or limits parameter values, so a call to getParameter() after setting the parameter can be used to retrieve the actual parameter value set.
	public:		void getParameterName(VstInt32 parameterIndex, char parameterName[24 + 1]);								///< Obtains the name of parameter \p parameterIndex. You can expect the names of parameters to stay constant during the life-time of the plug-in. The VST spec says 8 characters max, but many VSTs don't care about that, so I say 24. :-)
	public:		void getParameterDisplay(VstInt32 parameterIndex, char parameterDisplay[24 + 1]);						///< Obtains the current parameter value of \p parameterIndex as a human-readable string. The VST spec says 8 characters max, but many VSTs don't care about that, so I say 24. :-)
	public:		void getParameterLabel(VstInt32 parameterIndex, char parameterLabel[24 + 1]);							///< Obtains the label of \p parameterIndex. The label should be used as a suffix when presenting the parameter value to the user. You can expect the label to stay constant during the life-time of the plug-in. The VST spec says 8 characters max, but many VSTs don't care about that, so I say 24. :-)
	public:		bool setParameterFromString(VstInt32 parameterIndex, const char* string);								///< Tries to update the value of parameter \p to the value represented as an ascii string in \p string. The function is not mandatory, and false will be returned if the plug-in could not convert the string for one reason or another.
	public:		void resume();																							///< Resumes the plug-in. You must call this method before performing any processing. It is illegal to call this method if the plug-in is already in resumed state. (I.e. each call to resume() should be balanced with a call to suspend().)
	public:		void suspend();																							///< Suspends the plug-in. Calling this method allows the plug-in to release any resources necessary for processing (and if necessary update it's gui accordingly). It is illegal to call any of the processing methods when the plug-in is in suspended state. It is also illegal to call suspend more than once without a call to resume() in between. 
	public:		bool wantsMidi() const;																					///< Returns true if the plug-in has flagged that it is interested in receiving MIDI data.
	public:		void processAccumulating(const float* const* inBuffers, float* const* outBuffers, VstInt32 sampleCount);///< Processes samples from \p inBuffers and accumulates result in \p outBuffers. This is a legacy method for performing audio processing. processReplacing() is preferred. See processReplacing() for further documentation.
	public:		void processEvents(const VstEvents& events);															///< Processes the VST events in \p events (typically MIDI events). The events should be sorted in time (see deltaFrames in the VstEvent struct). Call this method before processReplacing(), and never more than once. The VstEvents struct only contains room for 2 events, so you would normally need to allocate your own VstEvents struct on the heap, or alternatively use a customized "hacked" VstEvents struct with more than 2 elements. See the VstEvents and VstEvent structs in the VST SDK documentation for more info. 
	public:		void processReplacing(const float* const* inBuffers, float* const* outBuffers, VstInt32 sampleCount);	///< Processes samples from \p inBuffers and places result in \p outBuffers. \p inBuffers and \p outBuffers are arrays with pointers to floating-point buffers for the sample data. You need to allocate and setup pointers to at least getInputCount() number of input buffers and getOutputCount() number of output buffers. Each input buffer should contain \p sampleCount number of samples, and each output buffer should contain space for at least as many samples. It is legal to use the input buffers as output buffers (for "in place processing").
	public:		VstIntPtr vendorSpecific(VstInt32 intA, VstIntPtr intB, void* pointer, float floating);					///< Perform any vendor-specific call to the plug-in. Used in Symbiosis for some AU-specific features. See Symbiosis documentation for more info.
	public:		VstInt32 getTailSize();																					///< Returns the "tail" of the effect plug-in. The "tail" is the number of samples that will need processing after the input has turned entirely silent, for example the tail of a decaying reverb. There are two special return values that you should pay attention to. 0 is returned if tail length is variable / unknown / not supported and 1 is returned if the plug-in has no tail at all.
	public:		bool setBypass(bool bypass);																			///< Starts or stops soft bypassing of the plug-in (according to \p bypass). Some plug-ins need processing calls even when bypassed, so you should still call the processing functions, but you can expect the output of the plug-in to be completely dry (although it doesn't need to be entirely identical to the input signal, see the VST SDK documentation on soft bypassing for more info). If setBypass returns false, the plug-in does not support soft bypassing, and you need not call any processing when bypassing the plug-in.
	public:		bool getInputProperties(VstInt32 inputPinIndex, VstPinProperties& properties);							///< Returns properties of input pin passed in \p inputPinIndex. Returns false if not supported. See VstPinProperties in the VST SDK documentation for more info.
	public:		bool getOutputProperties(VstInt32 inputPinIndex, VstPinProperties& properties);							///< Returns properties of output pin passed in \p inputPinIndex. Returns false if not supported. See VstPinProperties in the VST SDK documentation for more info.
	public:		void connectInputPin(VstInt32 inputPinIndex, bool connect);												///< Connects or disconnects an input (according to \p connect). A disconnected input is expected to be entirely silent during processing. The plug-in can use this information to optimize performance.
	public:		void connectOutputPin(VstInt32 outputPinIndex, bool connect);											///< Connects or disconnects an output (according to \p connect). A disconnected output will not contain valid output samples after processing. The plug-in can use this information to optimize performance.
	public:		unsigned char* createFXP(size_t& size);																	///< Creates an FXP file of the currently selected program in memory. You own the returned pointer and you are expected to delete it (with delete []) when you are done with it. \p size will contain the number of bytes of returned data.
	public:		unsigned char* createFXB(size_t& size);																	///< Creates an FXB file of the current plug-in state in memory. An FXB file is the entire state of a plug-in, including all currently loaded programs. You own the returned pointer and you are expected to delete it (with delete []) when you are done with it. \p size will contain the number of bytes of returned data.
	public:		bool loadFXPOrFXB(size_t size, const unsigned char bytes[]);											///< Loads an FXB or FXP file from memory. \p bytes should point to valid FXB or FXP data and \p size is the number of bytes for the data.
	public:		void idle();																							///< Call as often as possible from your main event loop. Many older plug-ins need idling both when editor is opened and not to perform low priority background tasks. Always call this method from the "GUI thread", *never* call it from the real-time audio thread.
	public:		void getEditorDimensions(VstInt32& width, VstInt32& height);											///< Returns the (initial) pixel dimensions of the plug-in GUI in \p width and \p height. It is illegal to call this method if hasEditor() has returned false.
	public:		void openEditor(::WindowRef inWindow);																	///< Opens the plug-in editor in the window referred to by \p inWindow. The plug-in will add it's user-pane control / HIView to this window and possibly hook other required event handlers to the window itself. It is important that you call closeEditor() before disposing the window. It is illegal to call this method if hasEditor() has returned false. It is also illegal to call this method more than once before a call to closeEditor().
	public:		void openEditor(::NSView* inNSView);																	///< Opens the plug-in editor in the Cocoa NSView referred to by \p inNSView. It is important that you call closeEditor() before disposing the window. It is illegal to call this method if hasEditor() has returned false. It is also illegal to call this method more than once before a call to closeEditor(). Only use this version of the function if the VST uses Cocoa views (e.g. 64-bit version).
	public:		void closeEditor();																						///< Closes the plug-in editor and disposes any views / event handles and other resources required by the GUI. It is important to call this method before closing the GUI window.
	public:		virtual ~VSTPlugIn();																					///< The destructor will close any open plug-in editor, issue a close call to the effect to dispose it and lastly release the bundle reference that was used to construct the plug-in instance.
	
	protected:	typedef AEffect* (VSTCALLBACK* VSTMainFunctionPointerType)(audioMasterCallback audioMaster);
	protected:	VstIntPtr myAudioMasterCallback(VstInt32 opcode, VstInt32 index, VstIntPtr value, void *ptr, float opt);
	protected:	static VstIntPtr staticAudioMasterCallback(AEffect *effect, VstInt32 opcode, VstInt32 index
						, VstIntPtr value, void *ptr, float opt);
	protected:	VstIntPtr dispatch(VstInt32 opCode, VstInt32 index, VstIntPtr value, void *ptr, float opt);
	protected:	unsigned char* writeFxCk(unsigned char* bp);
	protected:	const unsigned char* readFxCk(const unsigned char* bp, const unsigned char* ep, bool* wasPerfect);

	protected:	static VSTPlugIn* tempPlugInPointer;
	protected:	VSTHost& host;
	protected:	::CFBundleRef bundleRef;
	protected:	AEffect* aeffect;
	protected:	bool openFlag;
	protected:	bool resumedFlag;
	protected:	bool wantsMidiFlag;
	protected:	bool editorOpenFlag;
	protected:	float currentSampleRate;
	protected:	VstInt32 currentBlockSize;
};

#if (SY_INCLUDE_GUI_SUPPORT && SY_USE_COCOA_GUI)

class SymbiosisComponent;

/**
	Symbiosis20010220_CocoaView is an NSView with one simple override on 'dealloc' that calls the VST's close method.
	
	Cocoa has a flat name space, far from ideal for plug-ins. This means that each unique class must have a unique name
	and therefore we prefix this class with a version (which is actually a date). This date must be changed if the
	implementation changes.
*/

@interface Symbiosis20010220_CocoaView : NSView { SymbiosisComponent* symbiosis; }

- initWithFrame:(NSRect)frame symbiosis:(SymbiosisComponent*)symbiosisComponent;
- (void)dealloc;

@end

@interface Symbiosis20010220_CocoaViewFactory : NSObject <AUCocoaUIBase> { }

- (NSString*) description;

@end

#endif

/**
	SymbiosisComponent is our main class that manages the translation of all calls between AU and VST.
*/
class SymbiosisComponent : public VSTHost {
	public:		SymbiosisComponent(::AudioUnit auComponentInstance);
	public:		virtual void getVendor(VSTPlugIn& plugIn, char vendor[63 + 1]);
	public:		virtual void getProduct(VSTPlugIn& plugIn, char product[63 + 1]);
	public:		virtual VstInt32 getVersion(VSTPlugIn& plugIn);
	public:		virtual bool canDo(VSTPlugIn& plugIn, const char string[]);
	public:		virtual VstTimeInfo* getTimeInfo(VSTPlugIn& plugIn, VstInt32 /*flags*/);
	public:		virtual void beginEdit(VSTPlugIn& plugIn, VstInt32 parameterIndex);
	public:		virtual void automate(VSTPlugIn& plugIn, VstInt32 parameterIndex, float /*value*/);
	public:		virtual void endEdit(VSTPlugIn& plugIn, VstInt32 parameterIndex);
	public:		virtual void idle(VSTPlugIn& plugIn);
	public:		virtual bool isIOPinConnected(VSTPlugIn& plugIn, bool checkOutputPin, VstInt32 pinIndex);
	public:		virtual void updateDisplay(VSTPlugIn& plugIn);
	public:		virtual void resizeWindow(VSTPlugIn& plugIn, VstInt32 width, VstInt32 height);
	public:		void dispatch(::ComponentParameters* params);
#if (SY_INCLUDE_GUI_SUPPORT)
#if (SY_USE_COCOA_GUI)
	public:		virtual NSView* createView();
	public:		virtual void dropView();
#elif (!SY_USE_COCOA_GUI)
	public:		void createView(::ControlRef* createdControl, const ::Float32Point& /*requestedSize*/
						, const ::Float32Point& requestedLocation, ::ControlRef inParentControl, ::WindowRef inWindow
						, ::AudioUnitCarbonView auViewComponentInstance);
	public:		void dropView(::AudioUnitCarbonView auViewComponentInstance);
	public:		void setViewEventListener(::AudioUnitCarbonViewEventListener callback, void* userData);
#endif
#endif
	public:		virtual ~SymbiosisComponent();

	protected:	void uninit();
	protected:	void loadConfiguration();
	protected:	void getComponentName(char name[255 + 1]) const;
	protected:	::OSType getComponentType() const;
	protected:	::CFMutableDictionaryRef createAUPresetWithVSTData(size_t vstDataSize, const unsigned char vstData[]
						, ::CFStringRef presetName);
	protected:	::CFMutableDictionaryRef createAUPresetOfCurrentBank(::CFStringRef nameRef);
	protected:	::CFMutableDictionaryRef createAUPresetOfCurrentProgram(::CFStringRef nameRef);
	protected:	void convertLoadedPrograms(const ::FSRef* parentFSRef, bool writeNameListToFile = false
						, ::FSIORefNum nameListFork = 0);
	protected:	void convertVSTPreset(const ::FSRef* fsRef, bool isFXB);
	protected:	void convertVSTPresetsInDomain(short domain, const char componentName[]);
	protected:	void createFactoryPresets(::FSRef* factoryPresetsListFSRef);
	protected:	void loadFactoryPresets(::FSRef* factoryPresetsListFSRef);
	protected:	void loadOrCreateFactoryPresets();
	protected:	void convertVSTPresets();
	protected:	void readParameterMapping(const ::FSRef* fsRef);
	protected:	void createDefaultParameterMappingFile(const ::FSRef* fsRef);
	protected:	void readOrCreateParameterMapping();
	protected:	void reallocateIOBuffers();
	protected:	int getMaxInputChannels(int busNumber) const;
	protected:	int getMaxOutputChannels(int busNumber) const;
	protected:	int getActiveInputChannels(int busNumber) const;
	protected:	int getActiveOutputChannels(int busNumber) const;
	protected:	float scaleFromAUParameter(int parameterIndex, float auValue);
	protected:	float scaleToAUParameter(int parameterIndex, float vstValue);
	protected:	static pascal void idleTimerAction(::EventLoopTimerRef /*theTimer*/, void* theUserData);
	protected:	void propertyChanged(::AudioUnitPropertyID id, ::AudioUnitScope scope, ::AudioUnitElement element);
	protected:	void updateCurrentVSTProgramName(::CFStringRef presetName);
	protected:	bool updateCurrentAUPreset();
	protected:	void getPropertyInfo(::AudioUnitPropertyID id, ::AudioUnitScope scope, ::AudioUnitElement element
						, bool* isReadable, bool* isWritable, int* minDataSize, int* normalDataSize);
	protected:	void updateVSTTimeInfo(const ::AudioTimeStamp* inTimeStamp);
	protected:	bool collectInputAudio(int frameCount, float** inputPointers, const ::AudioTimeStamp* timeStamp);
	protected:	void renderOutput(int frameCount, const float* const* inputPointers, float** outputPointers
						, bool inputIsSilent);
	protected:	void render(::AudioUnitRenderActionFlags* ioActionFlags, const ::AudioTimeStamp* inTimeStamp
						, ::UInt32 inOutputBusNumber, ::UInt32 inNumberFrames, ::AudioBufferList* ioData);
	protected:	void getProperty(::UInt32* ioDataSize, void* outData, ::AudioUnitElement inElement
						, ::AudioUnitScope inScope, ::AudioUnitPropertyID inID);
	protected:	bool updateInitialDelayTime();
	protected:	bool updateTailTime();
	protected:	void updateInitialDelayAndTailTimes();
	protected:	bool updateSampleRate(::Float64 newSampleRate);
	protected:	void updateMaxFramesPerSlice(int newFramesPerSlice);
	protected:	void updateFormat(::AudioUnitScope scope, int busNumber, const ::AudioStreamBasicDescription& format);
	protected:	void setProperty(::UInt32 inDataSize, const void* inData, ::AudioUnitElement inElement
						, ::AudioUnitScope inScope, ::AudioUnitPropertyID inID);
	protected:	void tryToIdentifyHostApplication();

	protected:	enum HostApplication {
					undetermined
					, olderLogic
					, olderGarageBand
					, logic8_0
				};
				
	protected:	static ::EventLoopTimerUPP idleTimerUPP;
	protected:	::AudioUnit auComponentInstance;
	protected:	::CFBundleRef auBundleRef;
	protected:	::FSRef resourcesFSRef;
	protected:	::AudioStreamBasicDescription streamFormat;																// Note: only possible difference between input and output stream formats for all buses is the number of channels.
	protected:	int maxFramesPerSlice;
	protected:	int renderNotificationReceiversCount;
	protected:	::AURenderCallbackStruct renderNotificationReceivers[kMaxAURenderCallbacks];
	protected:	::Float64 lastRenderSampleTime;
	protected:	::AudioUnitConnection inputConnections[kMaxBuses];
	protected:	::AURenderCallbackStruct renderCallbacks[kMaxBuses];
	protected:	float* ioBuffers[kMaxChannels];
	protected:	bool silentOutput;
	protected:	int propertyListenersCount;
	protected:	AUPropertyListener propertyListeners[kMaxPropertyListeners];
	protected:	::HostCallbackInfo hostCallbackInfo;
	protected:	::AUPreset currentAUPreset;
	protected:	::AUPreset factoryPresets[kMaxFactoryPresets];
	protected:	::CFDataRef factoryPresetData[kMaxFactoryPresets];
	protected:	::CFMutableArrayRef factoryPresetsArray;
	protected:	int parameterCount;
	protected:	::AudioUnitParameterID parameterList[kMaxMappedParameters];
	protected:	::AudioUnitParameterInfo* parameterInfos;																// Index is actually VST parameter index since this is the same as the parameter id
	protected:	::CFArrayRef* parameterValueStrings;																	// Index is actually VST parameter index since this is the same as the parameter id
	protected:	bool presetIsFXB;
	protected:	bool autoConvertPresets;
	protected:	bool updateNameOnLoad;
	protected:	bool canDoMonoIO;
	protected:	VSTPlugIn* vst;
	protected:	SymbiosisVstEvents vstMidiEvents;
	protected:	VstTimeInfo vstTimeInfo;
	protected:	bool vstGotSymbiosisExtensions;
	protected:	bool vstSupportsTail;
	protected:	double initialDelayTime;
	protected:	double tailTime;
	protected:	bool vstSupportsBypass;
	protected:	bool isBypassing;
	protected:	int inputBusCount;
	protected:	int outputBusCount;
	protected:	int inputBusChannelNumbers[kMaxBuses + 1];
	protected:	int outputBusChannelNumbers[kMaxBuses + 1];
	protected:	int inputBusChannelCounts[kMaxBuses + 1];
	protected:	int outputBusChannelCounts[kMaxBuses + 1];
	protected:	::CFStringRef inputBusNames[kMaxBuses];
	protected:	::CFStringRef outputBusNames[kMaxBuses];
	protected:	int auChannelInfoCount;
	protected:	::AUChannelInfo auChannelInfos[4];
	protected:	HostApplication hostApplication;
	protected:	::EventLoopTimerRef idleTimerRef;
#if (SY_INCLUDE_GUI_SUPPORT)
#if (SY_USE_COCOA_GUI)
	protected:	NSView* cocoaView;
#elif (!SY_USE_COCOA_GUI)
	protected:	::AudioUnitCarbonView viewComponentInstance;
	protected:	::AudioUnitCarbonViewEventListener viewEventListener;
	protected:	void* viewEventListenerUserData;
	protected:	::WindowRef viewWindowRef;
	protected:	::ControlRef viewControl;
#endif
#endif
};

/* --- VSTPlugIn --- */

VSTPlugIn* VSTPlugIn::tempPlugInPointer = 0;

bool VSTPlugIn::isOpen() const { return openFlag; }
bool VSTPlugIn::isEditorOpen() const { return editorOpenFlag; }
bool VSTPlugIn::isResumed() const { return resumedFlag; }
bool VSTPlugIn::hasEditor() const { SY_ASSERT(aeffect != 0); return ((aeffect->flags & effFlagsHasEditor) != 0); }
VstInt32 VSTPlugIn::getProgramCount() const { SY_ASSERT(aeffect != 0); return aeffect->numPrograms; }
VstInt32 VSTPlugIn::getParameterCount() const { SY_ASSERT(aeffect != 0); return aeffect->numParams; }
VstInt32 VSTPlugIn::getInputCount() const { SY_ASSERT(aeffect != 0); return aeffect->numInputs; }
VstInt32 VSTPlugIn::getOutputCount() const { SY_ASSERT(aeffect != 0); return aeffect->numOutputs; }
VstInt32 VSTPlugIn::getInitialDelay() const { SY_ASSERT(aeffect != 0); return aeffect->initialDelay; }
bool VSTPlugIn::wantsMidi() const { SY_ASSERT(resumedFlag); return wantsMidiFlag; }
VstInt32 VSTPlugIn::getTailSize() { return static_cast<VstInt32>(dispatch(effGetTailSize, 0, 0, 0, 0)); }				// 0 = not supported, 1 = no tail 
void VSTPlugIn::closeEditor() { SY_ASSERT(editorOpenFlag); dispatch(effEditClose, 0, 0, 0, 0); editorOpenFlag = false; }

VstIntPtr VSTPlugIn::myAudioMasterCallback(VstInt32 opcode, VstInt32 index, VstIntPtr value, void *ptr, float opt) {
	switch (opcode) {
		case audioMasterAutomate:
			SY_TRACE2(SY_TRACE_FREQUENT, "VST audioMasterAutomate: %d=%f", index, opt);
			host.automate(*this, index, opt);
			break;
		
		case audioMasterCurrentId:
			SY_TRACE(SY_TRACE_VST, "VST audioMasterCurrentId");
			return (aeffect != 0) ? aeffect->uniqueID : 0;
			
		case DECLARE_VST_DEPRECATED(audioMasterPinConnected):
			SY_TRACE2(SY_TRACE_VST, "VST audioMasterPinConnected: i/o=%s, pin=%d", (value == 0) ? "in" : "out", index);
			return host.isIOPinConnected(*this, (value != 0), index) ? 0 : 1;											// 0 = true for backwards compatibility

		case DECLARE_VST_DEPRECATED(audioMasterWantMidi):
			SY_TRACE(SY_TRACE_VST, "VST audioMasterWantMidi");
			wantsMidiFlag = true;
			return 1;
		
		case audioMasterGetTime:
			SY_TRACE(SY_TRACE_FREQUENT, "audioMasterGetTime");
			return reinterpret_cast<VstIntPtr>(host.getTimeInfo((*this), static_cast<VstInt32>(value)));

		case audioMasterSizeWindow:
			SY_TRACE2(SY_TRACE_VST, "VST audioMasterSizeWindow: width=%d, height=%d", index, static_cast<int>(value));
			SY_ASSERT(editorOpenFlag);
			host.resizeWindow(*this, index, static_cast<VstInt32>(value));
			return 1;

		case DECLARE_VST_DEPRECATED(audioMasterGetParameterQuantization):
			SY_TRACE(SY_TRACE_VST, "VST audioMasterGetParameterQuantization");
			return 1;
								
		case audioMasterGetSampleRate:
			SY_TRACE(SY_TRACE_VST, "VST audioMasterGetSampleRate");
			SY_ASSERT(currentSampleRate != 0);
			return static_cast<VstInt32>(currentSampleRate + 0.5f);
				
		case audioMasterGetVendorString:
			SY_TRACE(SY_TRACE_VST, "VST audioMasterGetVendorString");
			host.getVendor((*this), reinterpret_cast<char*>(ptr));
			return 1;
		
		case audioMasterGetProductString:
			SY_TRACE(SY_TRACE_VST, "VST audioMasterGetProductString");
			host.getProduct((*this), reinterpret_cast<char*>(ptr));
			return 1;
		
		case audioMasterGetVendorVersion:
			SY_TRACE(SY_TRACE_VST, "VST audioMasterGetVendorVersion");
			return host.getVersion(*this);

		case audioMasterCanDo:
			SY_TRACE1(SY_TRACE_VST, "VST audioMasterCanDo: %s", reinterpret_cast<const char*>(ptr));
			return host.canDo((*this), reinterpret_cast<const char*>(ptr)) ? 1 : 0;										// Note: according to docs we should return -1 if we can't do, however there is a bug in the VST SDK plug-in class that returns true for canHostDo for anything != 0.

		case audioMasterUpdateDisplay:
			SY_TRACE(SY_TRACE_VST, "VST audioMasterUpdateDisplay");
			host.updateDisplay(*this);
			return 1;
		
		case audioMasterBeginEdit: // begin of automation session (when mouse down), parameter index in <index>
			SY_TRACE1(SY_TRACE_VST, "VST audioMasterBeginEdit: %d", index);
			host.beginEdit(*this, index);
			return 1;
		
		case audioMasterEndEdit: // end of automation session (when mouse up), parameter index in <index>
			SY_TRACE1(SY_TRACE_VST, "VST audioMasterEndEdit: %d", index);
			host.endEdit(*this, index);
			return 1;
		
		default: SY_TRACE1(SY_TRACE_VST, "VST unknown callback opcode: %d", opcode); break;
		case audioMasterVersion: SY_TRACE(SY_TRACE_VST, "VST audioMasterVersion"); return 2300;
		case audioMasterIdle: SY_TRACE(SY_TRACE_VST, "VST audioMasterIdle"); host.idle(*this); return 0;
		case audioMasterGetBlockSize: SY_TRACE(SY_TRACE_VST, "VST audioMasterGetBlockSize"); return currentBlockSize;
		case DECLARE_VST_DEPRECATED(audioMasterNeedIdle): SY_TRACE(SY_TRACE_VST, "VST audioMasterNeedIdle"); return 1;
		case DECLARE_VST_DEPRECATED(audioMasterSetTime): SY_TRACE(SY_TRACE_VST, "VST audioMasterSetTime (not supported)"); break;
		case DECLARE_VST_DEPRECATED(audioMasterTempoAt): SY_TRACE(SY_TRACE_VST, "VST audioMasterTempoAt (not supported)"); break;
		case DECLARE_VST_DEPRECATED(audioMasterGetNumAutomatableParameters): SY_TRACE(SY_TRACE_VST, "VST audioMasterGetNumAutomatableParameters (not supported)"); break;
		case audioMasterProcessEvents: SY_TRACE(SY_TRACE_VST, "VST audioMasterProcessEvents (not supported)"); break;
		case audioMasterIOChanged: SY_TRACE(SY_TRACE_VST, "VST audioMasterIOChanged (not supported)"); break;
		case audioMasterGetInputLatency: SY_TRACE(SY_TRACE_VST, "VST audioMasterGetInputLatency (not supported)"); break;
		case audioMasterGetOutputLatency: SY_TRACE(SY_TRACE_VST, "VST audioMasterGetOutputLatency (not supported)"); break;
		case DECLARE_VST_DEPRECATED(audioMasterGetPreviousPlug): SY_TRACE(SY_TRACE_VST, "VST audioMasterGetPreviousPlug (not supported)"); break;
		case DECLARE_VST_DEPRECATED(audioMasterGetNextPlug): SY_TRACE(SY_TRACE_VST, "VST audioMasterGetNextPlug (not supported)"); break;
		case DECLARE_VST_DEPRECATED(audioMasterWillReplaceOrAccumulate): SY_TRACE(SY_TRACE_VST, "VST audioMasterWillReplaceOrAccumulate (not supported)"); break;
		case audioMasterGetCurrentProcessLevel: SY_TRACE(SY_TRACE_FREQUENT, "audioMasterGetCurrentProcessLevel (not supported)"); break;
		case audioMasterGetAutomationState: SY_TRACE(SY_TRACE_VST, "VST audioMasterGetAutomationState (not supported)"); break;
		case audioMasterOfflineStart: SY_TRACE(SY_TRACE_VST, "VST audioMasterOfflineStart (not supported)"); break;
		case audioMasterOfflineRead: SY_TRACE(SY_TRACE_VST, "VST audioMasterOfflineRead (not supported)"); break;
		case audioMasterOfflineWrite: SY_TRACE(SY_TRACE_VST, "VST audioMasterOfflineWrite (not supported)"); break;
		case audioMasterOfflineGetCurrentPass: SY_TRACE(SY_TRACE_VST, "VST audioMasterOfflineGetCurrentPass (not supported)"); break;
		case audioMasterOfflineGetCurrentMetaPass: SY_TRACE(SY_TRACE_VST, "VST audioMasterOfflineGetCurrentMetaPass (not supported)"); break;
		case DECLARE_VST_DEPRECATED(audioMasterSetOutputSampleRate): SY_TRACE(SY_TRACE_VST, "VST audioMasterSetOutputSampleRate (not supported)"); break;
		case DECLARE_VST_DEPRECATED(audioMasterGetOutputSpeakerArrangement): SY_TRACE(SY_TRACE_VST, "VST audioMasterGetSpeakerArrangement (not supported)"); break;
		case audioMasterVendorSpecific: SY_TRACE(SY_TRACE_VST, "VST audioMasterVendorSpecific (not supported)"); break;
		case DECLARE_VST_DEPRECATED(audioMasterSetIcon): SY_TRACE(SY_TRACE_VST, "VST audioMasterSetIcon (not supported)"); break;
		case audioMasterGetLanguage: SY_TRACE(SY_TRACE_VST, "VST audioMasterGetLanguage (not supported)"); return kVstLangEnglish;
		case DECLARE_VST_DEPRECATED(audioMasterOpenWindow): SY_TRACE(SY_TRACE_VST, "VST audioMasterOpenWindow (not supported)"); break;
		case DECLARE_VST_DEPRECATED(audioMasterCloseWindow): SY_TRACE(SY_TRACE_VST, "VST audioMasterCloseWindow (not supported)"); break;
		case audioMasterGetDirectory: SY_TRACE(SY_TRACE_VST, "VST audioMasterGetDirectory (not supported)"); break;
		case audioMasterOpenFileSelector: SY_TRACE(SY_TRACE_VST, "VST audioMasterOpenFileSelector (not supported)"); break;
		case audioMasterCloseFileSelector: SY_TRACE(SY_TRACE_VST, "VST audioMasterCloseFileSelector (not supported)"); break;
		case DECLARE_VST_DEPRECATED(audioMasterEditFile): SY_TRACE(SY_TRACE_VST, "VST audioMasterEditFile (not supported)"); break;
		case DECLARE_VST_DEPRECATED(audioMasterGetChunkFile): SY_TRACE(SY_TRACE_VST, "VST audioMasterGetChunkFile (not supported)"); break;
		case DECLARE_VST_DEPRECATED(audioMasterGetInputSpeakerArrangement): SY_TRACE(SY_TRACE_VST, "VST audioMasterGetInputSpeakerArrangement (not supported)"); break;
	}

	return 0;
}

VstIntPtr VSTPlugIn::staticAudioMasterCallback(AEffect *effect, VstInt32 opcode, VstInt32 index, VstIntPtr value
		, void *ptr, float opt) {
	try {
		VSTPlugIn* plugIn;																								// During startup we use a temporary global plug-in pointer since we haven't been able to store it into the 'resvd1' field of 'aeffect' yet.
		if (effect == 0) {																								// Should only be for init stuff, so it is safe to use the global temp pointer.
			plugIn = tempPlugInPointer;
		} else {
			plugIn = reinterpret_cast<VSTPlugIn*>(effect->resvd1);														// Check resvd1 first, since during init, this may be a callback from another instance in a concurrent audio-thread.
			if (plugIn == 0) {
				plugIn = tempPlugInPointer;
				SY_ASSERT(plugIn != 0);
				plugIn->aeffect = effect;																				// Save away aeffect immediately, since some callbacks may require it.
			}
			SY_ASSERT(plugIn->aeffect == effect);
		}
		return plugIn->myAudioMasterCallback(opcode, index, value, ptr, opt);
	}
	catch (...) {
		SY_ASSERT0(0, "Caught exception in VST audio master callback");
		return 0;
	}
}

VSTPlugIn::VSTPlugIn(VSTHost& host, ::CFBundleRef vstBundleRef, float sampleRate, VstInt32 blockSize)
		: host(host), bundleRef(0), aeffect(0), openFlag(false), resumedFlag(false), wantsMidiFlag(false)
		, editorOpenFlag(false), currentSampleRate(sampleRate), currentBlockSize(blockSize)	{							// Note: some plug-ins request the sample rate and block-size during initialization (via the AudioMasterCallback), therefore we set them here to start with.
	::CFRetain(vstBundleRef);
	bundleRef = vstBundleRef;
}

bool VSTPlugIn::canProcessReplacing() const {
	SY_ASSERT(aeffect != 0);
	return ((aeffect->flags & effFlagsCanReplacing) != 0);
}

bool VSTPlugIn::hasProgramChunks() const {
	SY_ASSERT(aeffect != 0);
	return ((aeffect->flags & effFlagsProgramChunks) != 0);
}

bool VSTPlugIn::dontProcessSilence() const {
	SY_ASSERT(aeffect != 0);
	return ((aeffect->flags & effFlagsNoSoundInStop) != 0);
}

VstIntPtr VSTPlugIn::dispatch(VstInt32 opCode, VstInt32 index, VstIntPtr value, void *ptr, float opt) {
	SY_ASSERT(aeffect != 0);
	SY_ASSERT0((aeffect->dispatcher != 0), "VST dispatcher function pointer was null");
	try {
		return (*aeffect->dispatcher)(aeffect, opCode, index, value, ptr, opt);
	}
	catch (...) {
		SY_ASSERT0(0, "Caught exception in VST dispatcher");
		return 0;
	}
}

void VSTPlugIn::open() {
	SY_TRACE(SY_TRACE_VST, "VST open");
	SY_ASSERT(!openFlag);
	SY_ASSERT(!resumedFlag);
	if (!::CFBundleIsExecutableLoaded(bundleRef) && !::CFBundleLoadExecutable(bundleRef)) {
		throw SymbiosisException("Could not load VST bundle executable");
	}
	VSTMainFunctionPointerType mainFunction = (VSTMainFunctionPointerType)(::CFBundleGetFunctionPointerForName(bundleRef
			, CFSTR("main_macho")));
	if (mainFunction == 0) {
		mainFunction = (VSTMainFunctionPointerType)(::CFBundleGetFunctionPointerForName(bundleRef
				, CFSTR("VSTPluginMain")));
	}
	throwOnNull((void*)(mainFunction)
			, "Could not locate function in bundle executable (\"main_macho\" or \"VSTPluginMain\")");
	SY_ASSERT(tempPlugInPointer == 0);
	tempPlugInPointer = this;
	try {
		AEffect* newAEffect = (*mainFunction)(staticAudioMasterCallback);												// During startup we use a temporary global plug-in pointer since we haven't been able to store it into the 'resvd1' field of 'aeffect' yet.
		if (newAEffect == 0 || newAEffect->magic != kEffectMagic) {
			throw SymbiosisException("VST main() doesn't return object AEffect*");
		}
		SY_ASSERT(aeffect == 0 || aeffect == newAEffect);
		aeffect = newAEffect;
		aeffect->resvd1 = reinterpret_cast<VstIntPtr>(this);
	}
	catch (...) {
		tempPlugInPointer = 0;
		throw;
	}
	tempPlugInPointer = 0;
	setSampleRate(currentSampleRate);
	if (currentBlockSize != 0) {
		setBlockSize(currentBlockSize);
	}
	dispatch(effOpen, 0, 0, 0, 0);
	openFlag = true;
}

void VSTPlugIn::setSampleRate(float sampleRate) {
	SY_TRACE1(SY_TRACE_VST, "VST setSampleRate: %f", sampleRate);
	currentSampleRate = sampleRate;
	if (openFlag) {
		dispatch(effSetSampleRate, 0, 0, 0, sampleRate);
	}
}

void VSTPlugIn::setBlockSize(VstInt32 blockSize) {
	SY_TRACE1(SY_TRACE_VST, "VST setBlockSize: %d", blockSize);
	currentBlockSize = blockSize;
	if (openFlag) {
		dispatch(effSetBlockSize, 0, blockSize, 0, 0);
	}
}

void VSTPlugIn::setCurrentProgram(VstInt32 program) {
	SY_TRACE1(SY_TRACE_VST, "VST setCurrentProgram: %d", program);
	SY_ASSERT(program >= 0 && program < getProgramCount());
	dispatch(effSetProgram, 0, program, 0, 0);
}

VstInt32 VSTPlugIn::getCurrentProgram() {
	SY_TRACE(SY_TRACE_VST, "VST getCurrentProgram");
	VstInt32 programNumber = static_cast<VstInt32>(dispatch(effGetProgram, 0, 0, 0, 0));
	return (programNumber > aeffect->numPrograms) ? aeffect->numPrograms : programNumber;
}

void VSTPlugIn::getCurrentProgramName(char programName[24 + 1]) {
	SY_TRACE(SY_TRACE_VST, "VST getCurrentProgramName");
	char buffer[1024] = "";
	dispatch(effGetProgramName, 0, 0, reinterpret_cast<void*>(buffer), 0);
	strncpy(programName, buffer, 24);
	programName[24] = '\0';
}

void VSTPlugIn::setCurrentProgramName(const char programName[24 + 1]) {
	SY_TRACE1(SY_TRACE_VST, "VST setCurrentProgramName: %s", programName);
	SY_ASSERT(strlen(programName) <= 24);
	dispatch(effSetProgramName, 0, 0, reinterpret_cast<void*>(const_cast<char*>(programName)), 0);
}

bool VSTPlugIn::getProgramName(VstInt32 programIndex, char programName[24 + 1]) {
	SY_TRACE1(SY_TRACE_VST, "VST getProgramName: %d", programIndex);
	SY_ASSERT(programIndex < aeffect->numPrograms);
	char buffer[1024] = "";
	if (dispatch(effGetProgramNameIndexed, programIndex, -1, reinterpret_cast<void*>(buffer), 0) == 0) {
		return false;
	} else {
		strncpy(programName, buffer, 24);
		programName[24] = '\0';
		return true;
	}
}

float VSTPlugIn::getParameter(VstInt32 parameterIndex) {
	SY_TRACE1(SY_TRACE_FREQUENT, "VST getParameter: %d", parameterIndex);
	SY_ASSERT(parameterIndex >= 0 && parameterIndex < getParameterCount());
	SY_ASSERT(aeffect != 0);
	SY_ASSERT0((aeffect->getParameter != 0), "VST getParameter function pointer was null");
	try {
		float value = (*aeffect->getParameter)(aeffect, parameterIndex);
		SY_ASSERT(value >= 0.0f);
		SY_ASSERT(value <= 1.0f);
		return value;
	}
	catch (...) {
		SY_ASSERT0(0, "Caught exception in VST getParameter");
		return 0;
	}
}

void VSTPlugIn::setParameter(VstInt32 parameterIndex, float value) {
	SY_TRACE2(SY_TRACE_FREQUENT, "VST setParameter: %d=%f", parameterIndex, value);
	SY_ASSERT(parameterIndex >= 0 && parameterIndex < getParameterCount());
	SY_ASSERT(value >= 0.0);
	SY_ASSERT(value <= 1.0);
	SY_ASSERT(aeffect != 0);
	SY_ASSERT0((aeffect->setParameter != 0), "VST setParameter function pointer was null");
	try {
		(*aeffect->setParameter)(aeffect, parameterIndex, value);
	}
	catch (...) {
		SY_ASSERT0(0, "Caught exception in VST setParameter");
	}
}

void VSTPlugIn::getParameterName(VstInt32 parameterIndex, char parameterName[24 + 1]) {									// The VST spec says 8 characters max, but many VSTs don't care about that, so I say 24. :-)
	SY_TRACE1(SY_TRACE_VST, "VST getParameterName: %d", parameterIndex);
	SY_ASSERT(parameterIndex >= 0 && parameterIndex < getParameterCount());
	char buffer[1024] = "";
	dispatch(effGetParamName, parameterIndex, -1, reinterpret_cast<void*>(buffer), 0);
	strncpy(parameterName, buffer, 24);
	parameterName[24] = '\0';
}

void VSTPlugIn::getParameterDisplay(VstInt32 parameterIndex, char parameterDisplay[24 + 1]) {							// The VST spec says 8 characters max, but many VSTs don't care about that, so I say 24. :-)
	SY_TRACE1(SY_TRACE_VST, "VST getParameterDisplay: %d", parameterIndex);
	SY_ASSERT(parameterIndex >= 0 && parameterIndex < getParameterCount());
	char buffer[1024] = "";
	dispatch(effGetParamDisplay, parameterIndex, -1, reinterpret_cast<void*>(buffer), 0);
	strncpy(parameterDisplay, buffer, 24);
	parameterDisplay[24] = '\0';
}

void VSTPlugIn::getParameterLabel(VstInt32 parameterIndex, char parameterLabel[24 + 1]) {								// The VST spec says 8 characters max, but many VSTs don't care about that, so I say 24. :-)
	SY_TRACE1(SY_TRACE_VST, "VST getParameterLabel: %d", parameterIndex);
	SY_ASSERT(parameterIndex >= 0 && parameterIndex < getParameterCount());
	char buffer[1024] = "";
	dispatch(effGetParamLabel, parameterIndex, -1, reinterpret_cast<void*>(buffer), 0);
	strncpy(parameterLabel, buffer, 24);
	parameterLabel[24] = '\0';
}

bool VSTPlugIn::setParameterFromString(VstInt32 parameterIndex, const char* string) {
	SY_TRACE2(SY_TRACE_VST, "VST setParameterFromString: %d=%s", parameterIndex, (string == 0) ? "<null>" : string);
	SY_ASSERT(parameterIndex >= 0 && parameterIndex < getParameterCount());
	return (dispatch(effString2Parameter, parameterIndex, 0, const_cast<void*>(reinterpret_cast<const void*>(string))
			, 0) != 0);
}

void VSTPlugIn::resume() {
	SY_TRACE(SY_TRACE_VST, "VST resume");
	SY_ASSERT(aeffect != 0);
	SY_ASSERT(openFlag);
	SY_ASSERT(!resumedFlag);
	dispatch(effMainsChanged, 0, 1, 0, 0);
	resumedFlag = true;
}

void VSTPlugIn::suspend() {
	SY_TRACE(SY_TRACE_VST, "VST suspend");
	SY_ASSERT(aeffect != 0);
	SY_ASSERT(openFlag);
	SY_ASSERT(resumedFlag);
	dispatch(effMainsChanged, 0, 0, 0, 0);
	resumedFlag = false;
}

void VSTPlugIn::processAccumulating(const float* const* inBuffers, float* const* outBuffers, VstInt32 sampleCount) {
	SY_ASSERT(aeffect != 0);
	SY_ASSERT0((aeffect->DECLARE_VST_DEPRECATED(process) != 0), "VST process function pointer was null");
	SY_ASSERT(openFlag && resumedFlag);
	try {
		(*aeffect->DECLARE_VST_DEPRECATED(process))(aeffect, const_cast<float**>(inBuffers)
				, const_cast<float**>(outBuffers), sampleCount);
	}
	catch (...) {
		SY_ASSERT0(0, "Caught exception in VST process");
	}
}

void VSTPlugIn::processEvents(const VstEvents& events) {
	SY_ASSERT(openFlag && resumedFlag);
	dispatch(effProcessEvents, 0, 0, (void*)(&events), 0);
}

void VSTPlugIn::processReplacing(const float* const* inBuffers, float* const* outBuffers, VstInt32 sampleCount) {
	SY_ASSERT(aeffect != 0);
	SY_ASSERT0(aeffect->processReplacing != 0, "VST processReplacing function pointer was null");
	SY_ASSERT(openFlag && resumedFlag);
	SY_ASSERT(canProcessReplacing());
	try {
		(*aeffect->processReplacing)(aeffect, const_cast<float**>(inBuffers), const_cast<float**>(outBuffers)
				, sampleCount);
	}
	catch (...) {
		SY_ASSERT0(0, "Caught exception in VST processReplacing");
	}
}

VstIntPtr VSTPlugIn::vendorSpecific(VstInt32 intA, VstIntPtr intB, void* pointer, float floating) {
	return dispatch(effVendorSpecific, intA, intB, pointer, floating);
}

bool VSTPlugIn::setBypass(bool bypass) {
	SY_TRACE1(SY_TRACE_VST, "VST setBypass: %s", bypass ? "on" : "off");
	return (dispatch(effSetBypass, 0, bypass ? 1 : 0, 0, 0) != 0);
}

bool VSTPlugIn::getInputProperties(VstInt32 inputPinIndex, VstPinProperties& properties) {
	SY_TRACE1(SY_TRACE_VST, "VST getInputProperties: %d", inputPinIndex);
	SY_ASSERT(0 <= inputPinIndex && inputPinIndex < getInputCount());
	return (dispatch(effGetInputProperties, inputPinIndex, 0, &properties, 0) != 0);
}

bool VSTPlugIn::getOutputProperties(VstInt32 outputPinIndex, VstPinProperties& properties) {
	SY_TRACE1(SY_TRACE_VST, "VST getOutputProperties: %d", outputPinIndex);
	SY_ASSERT(0 <= outputPinIndex && outputPinIndex < getOutputCount());
	return (dispatch(effGetOutputProperties, outputPinIndex, 0, &properties, 0) != 0);
}

void VSTPlugIn::connectInputPin(VstInt32 inputPinIndex, bool connect) {
	SY_TRACE2(SY_TRACE_VST, "VST connectInputPin: %d=%s", inputPinIndex, connect ? "on" : "off");
	dispatch(DECLARE_VST_DEPRECATED(effConnectInput), inputPinIndex, connect ? 1 : 0, 0, 0);
}

void VSTPlugIn::connectOutputPin(VstInt32 outputPinIndex, bool connect) {
	SY_TRACE2(SY_TRACE_VST, "VST connectOutputPin: %d=%s", outputPinIndex, connect ? "on" : "off");
	dispatch(DECLARE_VST_DEPRECATED(effConnectOutput), outputPinIndex, connect ? 1 : 0, 0, 0);
}

unsigned char* VSTPlugIn::writeFxCk(unsigned char* bp) {
	bp = writeBigInt32(bp, 'CcnK');
	bp = writeBigInt32(bp, 56 - 8 + getParameterCount() * 4);
	bp = writeBigInt32(bp, 'FxCk');
	bp = writeBigInt32(bp, 1);
	bp = writeBigInt32(bp, aeffect->uniqueID);
	bp = writeBigInt32(bp, aeffect->version);
	bp = writeBigInt32(bp, getParameterCount());
	memset(bp, 0, 28);
	getCurrentProgramName(reinterpret_cast<char*>(bp));
	bp += 28;
	for (int i = 0; i < getParameterCount(); ++i) {
		bp = writeBigFloat32(bp, getParameter(i));
	}
	return bp;
}

const unsigned char* VSTPlugIn::readFxCk(const unsigned char* bp, const unsigned char* ep, bool* wasPerfect) {
	bool begunSetProgram = false;
	try {
		int magicID;
		int dataSize;
		int formatID;
		int version;
		int plugInID;
		int plugInVersion;
		bp = readBigInt32(bp, ep, &magicID);
		bp = readBigInt32(bp, ep, &dataSize);
		bp = readBigInt32(bp, ep, &formatID);
		bp = readBigInt32(bp, ep, &version);
		bp = readBigInt32(bp, ep, &plugInID);
		bp = readBigInt32(bp, ep, &plugInVersion);
		if (magicID != 'CcnK' || version != 1 || plugInID != aeffect->uniqueID) {
			throw FormatException("Invalid format of FXP / FXB data");
		}

		int parametersCount;
		bp = readBigInt32(bp, ep, &parametersCount);
		if (getParameterCount() != parametersCount) {
			SY_TRACE2(SY_TRACE_MISC, "Unexpected parameter count in FXP, expected %d, got %d", getParameterCount()
					, parametersCount);
			(*wasPerfect) = false;
		}
		char programName[24 + 1];
		strncpy(programName, reinterpret_cast<const char*>(bp), 24);
		programName[24] = '\0';
		setCurrentProgramName(programName);
		bp += 28;
		dispatch(effBeginSetProgram, 0, 0, 0, 0);
		begunSetProgram = true;
		for (int i = 0; i < getParameterCount(); ++i) {
			float value = 0;
			if (i < parametersCount) {
				bp = readBigFloat32(bp, ep, &value);
			}
			if (i < getParameterCount()) {
				if (value < 0.0f || value > 1.0f) {
					SY_TRACE2(SY_TRACE_MISC, "Invalid parameter in FXP: %d=%f", i, value);
					(*wasPerfect) = false;
					value = (value < 0) ? 0.0f : 1.0f;
				}
				setParameter(i, value);
			}
		}
		dispatch(effEndSetProgram, 0, 0, 0, 0);
		begunSetProgram = false;
	}
	catch (...) {
		if (begunSetProgram) {
			dispatch(effEndSetProgram, 0, 0, 0, 0);
			begunSetProgram = false;
		}
		throw;
	}
	return bp;
}

unsigned char* VSTPlugIn::createFXP(size_t& size) {
	SY_ASSERT(aeffect != 0);
	SY_ASSERT(openFlag);
	SY_TRACE(SY_TRACE_VST, "VST createFXP");
	
	unsigned char* bytes = 0;
	size = 0;
	try {
		if (hasProgramChunks()) {
			unsigned char* chunkPointer = 0;
			size_t chunkSize = dispatch(effGetChunk, 1, 0, &chunkPointer, 0);
			SY_ASSERT(static_cast<unsigned int>(chunkSize) == chunkSize);
			if (static_cast<long>(chunkSize) <= 0) {
				throw SymbiosisException("VST could not create chunk for FXP");
			}
			SY_ASSERT(chunkPointer != 0);
			size = 60 + chunkSize;
			SY_ASSERT(static_cast<unsigned int>(size) == size);
			bytes = new unsigned char[size];
			unsigned char* bp = bytes;
			bp = writeBigInt32(bp, 'CcnK');
			bp = writeBigInt32(bp, static_cast<unsigned int>(size - 8));
			bp = writeBigInt32(bp, 'FPCh');
			bp = writeBigInt32(bp, 1);
			bp = writeBigInt32(bp, aeffect->uniqueID);
			bp = writeBigInt32(bp, aeffect->version);
			bp = writeBigInt32(bp, aeffect->numParams);
			memset(bp, 0, 28);
			getCurrentProgramName(reinterpret_cast<char*>(bp));
			bp += 28;
			bp = writeBigInt32(bp, static_cast<unsigned int>(chunkSize));
			memcpy(bp, chunkPointer, chunkSize);
			bp += chunkSize;
			SY_ASSERT(static_cast<size_t>(bp - bytes) == size);
		} else {
			size = (56 + getParameterCount() * 4);
			bytes = new unsigned char[size];
			unsigned char* bp = bytes;
			bp = writeFxCk(bp);
			SY_ASSERT(static_cast<size_t>(bp - bytes) == size);
		}
	}
	catch (...) {
		delete [] bytes;
		size = 0;
		bytes = 0;
		throw;
	}
	return bytes;
}
				
unsigned char* VSTPlugIn::createFXB(size_t& size) {
	SY_ASSERT(aeffect != 0);
	SY_ASSERT(openFlag);
	SY_TRACE(SY_TRACE_VST, "VST createFXB");
	
	int oldProgramIndex = -1;
	unsigned char* bytes = 0;
	size = 0;
	try {
		if (hasProgramChunks()) {
			unsigned char* chunkPointer = 0;
			size_t chunkSize = dispatch(effGetChunk, 0, 0, &chunkPointer, 0);
			SY_ASSERT(static_cast<unsigned int>(chunkSize) == chunkSize);
			if (static_cast<long>(chunkSize) <= 0) {
				throw SymbiosisException("VST could not create chunk for FXB");
			}
			SY_ASSERT(chunkPointer != 0);
			size = 160 + chunkSize;
			SY_ASSERT(static_cast<unsigned int>(size) == size);
			bytes = new unsigned char[size];
			unsigned char* bp = bytes;
			bp = writeBigInt32(bp, 'CcnK');
			bp = writeBigInt32(bp, static_cast<unsigned int>(size - 8));
			bp = writeBigInt32(bp, 'FBCh');
			bp = writeBigInt32(bp, 1);
			bp = writeBigInt32(bp, aeffect->uniqueID);
			bp = writeBigInt32(bp, aeffect->version);
			bp = writeBigInt32(bp, aeffect->numPrograms);
			memset(bp, 0, 128);
			bp += 128;
			bp = writeBigInt32(bp, static_cast<unsigned int>(chunkSize));
			memcpy(bp, chunkPointer, chunkSize);
			bp += chunkSize;
			SY_ASSERT(static_cast<size_t>(bp - bytes) == size);
		} else {
			size = 156 + aeffect->numPrograms * (56 + getParameterCount() * 4);
			SY_ASSERT(static_cast<unsigned int>(size) == size);
			bytes = new unsigned char[size];
			unsigned char* bp = bytes;
			bp = writeBigInt32(bp, 'CcnK');
			bp = writeBigInt32(bp, static_cast<unsigned int>(size - 8));
			bp = writeBigInt32(bp, 'FxBk');
			bp = writeBigInt32(bp, 1);
			bp = writeBigInt32(bp, aeffect->uniqueID);
			bp = writeBigInt32(bp, aeffect->version);
			bp = writeBigInt32(bp, aeffect->numPrograms);
			memset(bp, 0, 128);
			bp += 128;
			oldProgramIndex = getCurrentProgram();
			SY_ASSERT(oldProgramIndex >= 0);
			for (int i = 0; i < aeffect->numPrograms; ++i) {
				setCurrentProgram(i);
				bp = writeFxCk(bp);
			}
			setCurrentProgram(oldProgramIndex);
			oldProgramIndex = -1;
			SY_ASSERT(static_cast<size_t>(bp - bytes) == size);
		}
	}
	catch (...) {
		if (oldProgramIndex >= 0) {
			setCurrentProgram(oldProgramIndex);
		}
		delete [] bytes;
		size = 0;
		bytes = 0;
		throw;
	}
	return bytes;
}

bool VSTPlugIn::loadFXPOrFXB(size_t size, const unsigned char bytes[]) {
	SY_ASSERT(size >= 0);
	SY_ASSERT(bytes != 0);
	SY_ASSERT(aeffect != 0);
	SY_ASSERT(openFlag);
	SY_TRACE1(SY_TRACE_VST, "VST loadFXPOrFXB (size=%ld)", static_cast<long>(size));

	int oldProgramIndex = -1;
	try {
		const unsigned char* bp = bytes;
		const unsigned char* ep = bytes + size;
		int magicID;
		int dataSize;
		int formatID;
		int version;
		int plugInID;
		int plugInVersion;
		bp = readBigInt32(bp, ep, &magicID);
		bp = readBigInt32(bp, ep, &dataSize);
		bp = readBigInt32(bp, ep, &formatID);
		bp = readBigInt32(bp, ep, &version);
		bp = readBigInt32(bp, ep, &plugInID);
		bp = readBigInt32(bp, ep, &plugInVersion);
		if (magicID != 'CcnK' || (static_cast<size_t>(dataSize) + 8) > size
				|| version != 1 || plugInID != aeffect->uniqueID) {
			throw FormatException("Invalid format of FXP / FXB data");
		}
		switch (formatID) {
			default: throw FormatException("Invalid format of FXP / FXB data");
			
			case 'FxCk': {		// FXP parameter list
				SY_TRACE(SY_TRACE_VST, "VST loading FxCk");
				bool isPerfect = true;
				bp = readFxCk(bytes, ep, &isPerfect);
				return isPerfect;
			}
			
			case 'FPCh': {		// FXP custom chunk
				SY_TRACE(SY_TRACE_VST, "VST loading FPCh");
				SY_ASSERT(hasProgramChunks());
				bp += 4;
				char programName[24 + 1];
				strncpy(programName, reinterpret_cast<const char*>(bp), 24);
				programName[24] = '\0';
				setCurrentProgramName(programName);
				bp += 28;
				int chunkSize;
				bp = readBigInt32(bp, ep, &chunkSize);
				if (bp + chunkSize > ep) {
					throw EOFException("Unexpected end of file in FXP / FXB data");
				}
				return (dispatch(effSetChunk, 1, chunkSize, reinterpret_cast<void*>(const_cast<unsigned char*>(bp)), 0)
						!= 0);
			}

			case 'FxBk': {		// FXB program list
				SY_TRACE(SY_TRACE_VST, "VST loading FxBk");
				bool isPerfect = true;
				int programsCount;
				bp = readBigInt32(bp, ep, &programsCount);
				if (programsCount != aeffect->numPrograms) {
					SY_TRACE2(SY_TRACE_MISC, "Unexpected program count in FXB data, expected %d, got %d"
							, static_cast<int>(aeffect->numPrograms), programsCount);
					isPerfect = false;
					if (aeffect->numPrograms < programsCount) {
						programsCount = aeffect->numPrograms;
					}
				}
				bp += 128;
				oldProgramIndex = getCurrentProgram();
				SY_ASSERT(oldProgramIndex >= 0);
				for (int i = 0; i < programsCount; ++i) {
					setCurrentProgram(i);
					bp = readFxCk(bp, ep, &isPerfect);
				}
				setCurrentProgram(oldProgramIndex);
				oldProgramIndex = -1;
				return isPerfect;
			}
			
			case 'FBCh': {		// FXB custom chunk
				SY_TRACE(SY_TRACE_VST, "VST loading FBCh");
				SY_ASSERT(hasProgramChunks());
				bp += 4 + 128;
				int chunkSize;
				bp = readBigInt32(bp, ep, &chunkSize);
				if (bp + chunkSize > ep) {
					throw EOFException("Unexpected end of file in FXB data");
				}
				return (dispatch(effSetChunk, 0, chunkSize, reinterpret_cast<void*>(const_cast<unsigned char*>(bp)), 0)
						!= 0);
			}
		}
	}
	catch (...) {
		if (oldProgramIndex >= 0) {
			setCurrentProgram(oldProgramIndex);
		}
		throw;
	}
	return false;
}

void VSTPlugIn::idle() {
	dispatch(DECLARE_VST_DEPRECATED(effIdle), 0, 0, 0, 0);
	if (editorOpenFlag != 0) {
		dispatch(effEditIdle, 0, 0, 0, 0);
	}
}

void VSTPlugIn::getEditorDimensions(VstInt32& width, VstInt32& height) {
	SY_ASSERT(hasEditor());
	ERect* rectPointer = 0;
	VstIntPtr vstDispatchReturn = dispatch(effEditGetRect, 0, 0, reinterpret_cast<void*>(&rectPointer), 0);
	SY_ASSERT(vstDispatchReturn != 0);
	SY_ASSERT(rectPointer != 0);
	SY_ASSERT(rectPointer->left <= rectPointer->right);
	SY_ASSERT(rectPointer->top <= rectPointer->bottom);
	width = rectPointer->right - rectPointer->left;
	height = rectPointer->bottom - rectPointer->top;
}

void VSTPlugIn::openEditor(::WindowRef inWindow) {
	SY_ASSERT(hasEditor());
	SY_ASSERT(!editorOpenFlag);
	SY_ASSERT(inWindow != 0);
	editorOpenFlag = true;
	VstIntPtr vstDispatchReturn = dispatch(effEditOpen, 0, 0, reinterpret_cast<void*>(inWindow), 0);
	if (vstDispatchReturn == 0) {
		throw SymbiosisException("VST could not open editor");
	}
}

void VSTPlugIn::openEditor(::NSView* inNSView) {
	SY_ASSERT(hasEditor());
	SY_ASSERT(!editorOpenFlag);
	SY_ASSERT(inNSView != 0);
	editorOpenFlag = true;
	VstIntPtr vstDispatchReturn = dispatch(effEditOpen, 0, 0, reinterpret_cast<void*>(inNSView), 0);
	if (vstDispatchReturn == 0) {
		throw SymbiosisException("VST could not open editor");
	}
}

VSTPlugIn::~VSTPlugIn() {
	if (editorOpenFlag) {
		closeEditor();
	}

	if (aeffect != 0) {
		dispatch(effClose, 0, 0, 0, 0);
		aeffect = false;
		aeffect = 0; // Note: sending an effClose to a VST destroys the aeffect instance
	}

	SY_ASSERT(bundleRef != 0);
	SY_ASSERT(::CFBundleIsExecutableLoaded(bundleRef));
	releaseBundleRef(bundleRef);
}

/* --- SymbiosisComponent --- */

void SymbiosisComponent::idle(VSTPlugIn& plugIn) { SY_ASSERT(&plugIn == vst); }
VstInt32 SymbiosisComponent::getVersion(VSTPlugIn& plugIn) { SY_ASSERT(&plugIn == vst); return kSymbiosisVSTVersion; }
SymbiosisComponent::~SymbiosisComponent() { uninit(); }

void SymbiosisComponent::uninit() {
#if (SY_INCLUDE_GUI_SUPPORT)
#if (!SY_USE_COCOA_GUI)
	if (viewComponentInstance != 0) {
		::SetComponentInstanceStorage(reinterpret_cast< ::ComponentInstance >(viewComponentInstance), 0);
		dropView(viewComponentInstance);
		SY_ASSERT(viewComponentInstance == 0);
	}
#endif
#endif

	if (idleTimerRef != 0) {
		throwOnOSError(::RemoveEventLoopTimer(idleTimerRef));
		idleTimerRef = 0;
	}

	for (int i = 0; i < kMaxFactoryPresets; ++i) {
		releaseCFRef((::CFTypeRef*)&factoryPresets[i].presetName);
		releaseCFRef((::CFTypeRef*)&factoryPresetData[i]);
	}
	releaseCFRef((::CFTypeRef*)&factoryPresetsArray);
	releaseCFRef((::CFTypeRef*)&currentAUPreset.presetName);
	
	if (vst != 0 && vst->isOpen()) {
		for (int i = 0; i < vst->getParameterCount(); ++i) {
			releaseCFRef((::CFTypeRef*)&parameterInfos[i].unitName);
			releaseCFRef((::CFTypeRef*)&parameterInfos[i].cfNameString);
			releaseCFRef((::CFTypeRef*)&parameterValueStrings[i]);
		}
	}

	delete [] parameterInfos;
	parameterInfos = 0;
	delete [] parameterValueStrings;
	parameterValueStrings = 0;
	delete vst;
	vst = 0;
	
	for (int i = 0; i < kMaxVSTMIDIEvents; ++i) {
		delete vstMidiEvents.events[i];
		vstMidiEvents.events[i] = 0;
	}
	
	for (int i = 0; i < kMaxChannels; ++i) {
		delete [] ioBuffers[i];
		ioBuffers[i] = 0;
	}
	
	for (int i = 0; i < kMaxBuses; ++i) {
		releaseCFRef((::CFTypeRef*)&inputBusNames[i]);
		releaseCFRef((::CFTypeRef*)&outputBusNames[i]);
	}
						
	releaseBundleRef(auBundleRef);
}

void SymbiosisComponent::loadConfiguration() {
	::CFDictionaryRef infoDictionaryRef = 0;
	throwOnNull(infoDictionaryRef = ::CFBundleGetInfoDictionary(auBundleRef)
			, "Could not get info dictionary for bundle");
	::CFDictionaryRef syConfigDictionaryRef = reinterpret_cast< ::CFDictionaryRef >
			(getValueOfKeyInDictionary(infoDictionaryRef, CFSTR("SYConfig"), ::CFDictionaryGetTypeID()));
	autoConvertPresets = ::CFBooleanGetValue(reinterpret_cast< ::CFBooleanRef >
			(getValueOfKeyInDictionary(syConfigDictionaryRef, CFSTR("AutoConvertPresets"), ::CFBooleanGetTypeID())));
	presetIsFXB = ::CFBooleanGetValue(reinterpret_cast< ::CFBooleanRef >
			(getValueOfKeyInDictionary(syConfigDictionaryRef, CFSTR("PresetIsFXB"), ::CFBooleanGetTypeID())));
	updateNameOnLoad = ::CFBooleanGetValue(reinterpret_cast< ::CFBooleanRef >
			(getValueOfKeyInDictionary(syConfigDictionaryRef, CFSTR("UpdateNameOnLoad"), ::CFBooleanGetTypeID())));
	canDoMonoIO = ::CFBooleanGetValue(reinterpret_cast< ::CFBooleanRef >
			(getValueOfKeyInDictionary(syConfigDictionaryRef, CFSTR("CanDoMonoIO"), ::CFBooleanGetTypeID())));
}

void SymbiosisComponent::getComponentName(char name[255 + 1]) const {
	SY_ASSERT(name != 0);
	::Handle nameHandle = 0;
	try {
		::ComponentDescription desc;
		nameHandle = ::NewHandleClear(255 + 1);
		throwOnOSError(::GetComponentInfo(reinterpret_cast< ::Component >(auComponentInstance), &desc, nameHandle, 0
				, 0));
		int length = *reinterpret_cast<const unsigned char*>(*nameHandle);
		memcpy(name, reinterpret_cast<const unsigned char*>(*nameHandle) + 1, length);
		name[length] = 0;
		::DisposeHandle(nameHandle);
		nameHandle = 0;
	}
	catch (...) {
		if (nameHandle != 0) {
			::DisposeHandle(nameHandle);
			nameHandle = 0;
		}
		throw;
	}
}

::OSType SymbiosisComponent::getComponentType() const {
	::ComponentDescription desc;
	throwOnOSError(::GetComponentInfo(reinterpret_cast< ::Component >(auComponentInstance), &desc, 0, 0, 0));
	return desc.componentType;
}

::CFMutableDictionaryRef SymbiosisComponent::createAUPresetWithVSTData(size_t vstDataSize, const unsigned char vstData[]
		, ::CFStringRef presetName) {
	SY_ASSERT(vstData != 0);
	SY_ASSERT(presetName != 0);
	::CFMutableDictionaryRef dictionary = 0;
	::CFMutableDataRef data = 0;
	try {
		::ComponentDescription desc;
		throwOnOSError(::GetComponentInfo(reinterpret_cast< ::Component >(auComponentInstance), &desc, 0, 0, 0));
		dictionary = ::CFDictionaryCreateMutable(0, 0, &kCFTypeDictionaryKeyCallBacks
				, &kCFTypeDictionaryValueCallBacks);
		SY_ASSERT(dictionary != 0);
		addIntToDictionary(dictionary, CFSTR(kAUPresetVersionKey), 1);
		addIntToDictionary(dictionary, CFSTR(kAUPresetTypeKey), desc.componentType);
		addIntToDictionary(dictionary, CFSTR(kAUPresetSubtypeKey), desc.componentSubType);
		addIntToDictionary(dictionary, CFSTR(kAUPresetManufacturerKey), desc.componentManufacturer);
		::CFDictionarySetValue(dictionary, CFSTR(kAUPresetNameKey), presetName);
		data = ::CFDataCreateMutable(0, vstDataSize);
		SY_ASSERT(data != 0);
		::CFDataAppendBytes(data, vstData, vstDataSize);
		::CFDictionarySetValue(dictionary, CFSTR(kAUPresetVSTDataKey), data);
		releaseCFRef((::CFTypeRef*)&data);
	}
	catch (...) {
		releaseCFRef((::CFTypeRef*)&data);
		releaseCFRef((::CFTypeRef*)&dictionary);
		throw;
	}
	return dictionary;
}

::CFMutableDictionaryRef SymbiosisComponent::createAUPresetOfCurrentBank(::CFStringRef nameRef) {
	SY_ASSERT(nameRef != 0);
	SY_ASSERT(::CFGetTypeID(nameRef) == ::CFStringGetTypeID());
	
	unsigned char* fxpData = 0;
	::CFMutableDictionaryRef dictionary = 0;
	try {
		size_t fxpSize;
		fxpData = vst->createFXB(fxpSize);
		dictionary = createAUPresetWithVSTData(fxpSize, fxpData, nameRef);
		delete [] fxpData;
		fxpData = 0;
	}
	catch (...) {
		releaseCFRef((::CFTypeRef*)&dictionary);
		delete [] fxpData;
		fxpData = 0;
		throw;
	}
	return dictionary;
}

::CFMutableDictionaryRef SymbiosisComponent::createAUPresetOfCurrentProgram(::CFStringRef nameRef) {
	SY_ASSERT(nameRef != 0);
	SY_ASSERT(::CFGetTypeID(nameRef) == ::CFStringGetTypeID());
	
	unsigned char* fxpData = 0;
	::CFMutableDictionaryRef dictionary = 0;
	try {
		size_t fxpSize;
		fxpData = vst->createFXP(fxpSize);
		dictionary = createAUPresetWithVSTData(fxpSize, fxpData, nameRef);
		delete [] fxpData;
		fxpData = 0;
	}
	catch (...) {
		releaseCFRef((::CFTypeRef*)&dictionary);
		delete [] fxpData;
		fxpData = 0;
		throw;
	}
	return dictionary;
}

void SymbiosisComponent::convertLoadedPrograms(const ::FSRef* parentFSRef, bool writeNameListToFile
		, ::FSIORefNum nameListFork) {
	SY_ASSERT(parentFSRef != 0);
	SY_ASSERT(!presetIsFXB);

	::CFMutableDictionaryRef auPresetDictionary = 0;
	::CFStringRef auPresetName = 0;
	int oldProgramIndex = -1;
	try {
		oldProgramIndex = vst->getCurrentProgram();
		SY_ASSERT(oldProgramIndex >= 0);
		char lastProgramName[24 + 9 + 1] = "";																			// 9 extra for aupreset extension
		for (int i = 0; i < vst->getProgramCount(); ++i) {
			vst->setCurrentProgram(i);
			char filenameBuffer[24 + 9 + 1 + 1] = "";																	// 9 extra for aupreset extension, one extra for the '\r' if we write to name-list file
			vst->getCurrentProgramName(filenameBuffer);
			char* filename = const_cast<char*>(eatSpace(filenameBuffer));												// Skip leading spaces
			size_t l = strlen(filename);
			while (l > 0 && filename[l - 1] == ' ') {
				--l;
			}
			if (l <= 0) {
				continue;
			}
			filename[l] = '\0';
			SY_ASSERT(strlen(filename) <= 24);
			if (i == 0 || strcmp(lastProgramName, filename) != 0) {
				strcpy(lastProgramName, filename);
				
				SY_ASSERT(auPresetName == 0);
				auPresetName = ::CFStringCreateWithCString(0, filename, kCFStringEncodingMacRoman);
				SY_ASSERT(auPresetName != 0);
				SY_ASSERT(auPresetDictionary == 0);
				auPresetDictionary = createAUPresetOfCurrentProgram(auPresetName);
				releaseCFRef((::CFTypeRef*)&auPresetName);
				
				strcat(filename, kAUPresetExtension);

				SY_ASSERT(auPresetName == 0);
				auPresetName = ::CFStringCreateWithCString(0, filename, kCFStringEncodingMacRoman);
				SY_ASSERT(auPresetName != 0);
				::HFSUniStr255 uniName;
				::CFRange range;
				range.location = 0;
				range.length = ::CFStringGetLength(auPresetName);
				SY_ASSERT(range.length <= 255);
				::CFStringGetCharacters(auPresetName, range, uniName.unicode);
				releaseCFRef((::CFTypeRef*)&auPresetName);
				uniName.length = range.length;

				::FSRef newFSRef;
				::OSErr err = ::FSMakeFSRefUnicode(parentFSRef, uniName.length, uniName.unicode, kTextEncodingUnknown
						, &newFSRef);
				if (err == noErr) {
					::FSDeleteObject(&newFSRef);
				}
				throwOnOSError(::FSCreateFileUnicode(parentFSRef, uniName.length, uniName.unicode, kFSCatInfoNone, 0
						, &newFSRef, 0));
				saveProperties(auPresetDictionary, &newFSRef);
				releaseCFRef((::CFTypeRef*)&auPresetDictionary);
				SY_TRACE1(SY_TRACE_MISC, "Converted program: %s", filename);
				
				if (writeNameListToFile) {
					strcat(filename, "\r");
					::ByteCount actualCount;
					throwOnOSError(::FSWriteFork(nameListFork, fsAtMark, 0, strlen(filename), filename, &actualCount));
					SY_ASSERT(actualCount == strlen(filename));
				}
			}
		}
		vst->setCurrentProgram(oldProgramIndex);
		oldProgramIndex = -1;
	}
	catch (...) {
		if (oldProgramIndex >= 0) {
			vst->setCurrentProgram(oldProgramIndex);
		}
		releaseCFRef((::CFTypeRef*)&auPresetName);
		releaseCFRef((::CFTypeRef*)&auPresetDictionary);
		throw;
	}
}

void SymbiosisComponent::convertVSTPreset(const ::FSRef* fsRef, bool isFXB) {
	SY_ASSERT(fsRef != 0);
	SY_ASSERT(isFXB || !presetIsFXB);
	
	unsigned char* bytes = 0;
	::CFDictionaryRef auPresetDictionary = 0;
	::CFStringRef auPresetName = 0;
	try {
		::HFSUniStr255 uniName;
		::FSRef parentFSRef;
		throwOnOSError(::FSGetCatalogInfo(fsRef, kFSCatInfoNone, 0, &uniName, 0, &parentFSRef));
		::UniCharCount extensionStartIndex;
		throwOnOSError(::LSGetExtensionInfo(uniName.length, uniName.unicode, &extensionStartIndex));
		SY_ASSERT(extensionStartIndex == kLSInvalidExtensionIndex || (extensionStartIndex >= 1
				&& extensionStartIndex <= uniName.length));
		if (isFXB && !presetIsFXB) {
			::FSRef newFolderFSRef;
			if (::FSCreateDirectoryUnicode(&parentFSRef, (extensionStartIndex == kLSInvalidExtensionIndex)
					? uniName.length : extensionStartIndex - 1, uniName.unicode, kFSCatInfoNone, 0, &newFolderFSRef, 0
					, 0) == noErr) {
				size_t size = 0;
				bytes = loadFromFile(fsRef, size);
				vst->loadFXPOrFXB(size, bytes);
				delete [] bytes;
				bytes = 0;
				convertLoadedPrograms(&newFolderFSRef);
				SY_TRACE(SY_TRACE_MISC, "Successfully converted fxb to multiple presets");
			}
		} else {
			if (extensionStartIndex != kLSInvalidExtensionIndex && extensionStartIndex > 255 - 8) {
				extensionStartIndex = kLSInvalidExtensionIndex;
			}
			if (extensionStartIndex == kLSInvalidExtensionIndex) {
				if (uniName.length > 255 - 9) {
					uniName.length = 255 - 9;
				}
				uniName.unicode[uniName.length] = '.';
				extensionStartIndex = uniName.length + 1;
			}
			auPresetName = ::CFStringCreateWithCharacters(0, uniName.unicode, extensionStartIndex - 1);
			SY_ASSERT(auPresetName != 0);
			for (int i = 0; i < 8; ++i) {
				uniName.unicode[extensionStartIndex + i] = kAUPresetExtension[1 + i];
			}
			::FSRef newFSRef;
			if (::FSCreateFileUnicode(&parentFSRef, extensionStartIndex + 8, uniName.unicode, kFSCatInfoNone, 0
					, &newFSRef, 0) == noErr) {
				size_t size = 0;
				bytes = loadFromFile(fsRef, size);
				auPresetDictionary = createAUPresetWithVSTData(size, bytes, auPresetName);
				delete [] bytes;
				bytes = 0;
				saveProperties(auPresetDictionary, &newFSRef);
				releaseCFRef((::CFTypeRef*)&auPresetDictionary);
				SY_TRACE1(SY_TRACE_MISC, "Successfully converted %s to single preset", (isFXB) ? "fxb" : "fxp");
			}
			releaseCFRef((::CFTypeRef*)&auPresetName);
		}
	}
	catch (const std::exception& x) {
		SY_TRACE1(SY_TRACE_EXCEPTIONS, "Failed converting preset, caught exception: %s", x.what());
		releaseCFRef((::CFTypeRef*)&auPresetDictionary);
		releaseCFRef((::CFTypeRef*)&auPresetName);
		delete [] bytes;
		bytes = 0;
		// No throw!
	}
	catch (...) {
		SY_TRACE(SY_TRACE_EXCEPTIONS, "Failed converting preset (caught general exception)");
		releaseCFRef((::CFTypeRef*)&auPresetDictionary);
		releaseCFRef((::CFTypeRef*)&auPresetName);
		delete [] bytes;
		bytes = 0;
		// No throw!
	}
}

void SymbiosisComponent::convertVSTPresetsInDomain(short domain, const char componentName[]) {
	SY_ASSERT(componentName != 0);
	
	::LSItemInfoRecord itemInfo;
	memset(&itemInfo, 0, sizeof (itemInfo));
	::FSIterator iterator = 0;
	try {
		::FSRef folderFSRef;
		throwOnOSError(::FSFindFolder(domain, kAudioSupportFolderType, kDontCreateFolder, &folderFSRef));
		descendOrCreateFolder(&folderFSRef, 7, "Presets", &folderFSRef);
		const char* p = componentName;
		while (*p != '\0') {
			p = eatSpace(p);
			const char* s = p;
			const char* e = s;
			while (*p != '\0' && *p != ':') {
				if (*p != ' ') {
					e = p + 1;
				}
				++p;
			}
			if (e != s) {
				descendOrCreateFolder(&folderFSRef, e - s, s, &folderFSRef);
			}
			if (*p != '\0') {
				++p;
			}
		}

		throwOnOSError(::FSOpenIterator(&folderFSRef, kFSIterateFlat, &iterator));
		SY_ASSERT(iterator != 0);
		::OSErr fsGetCatalogInfoBulkReturn = noErr;
		do {
			::FSRef fsRefs[64];
			::ItemCount itemCount;
			fsGetCatalogInfoBulkReturn = ::FSGetCatalogInfoBulk(iterator, 64, &itemCount, 0, kFSCatInfoNone, 0, fsRefs
					, 0, 0);
			if (fsGetCatalogInfoBulkReturn != errFSNoMoreItems) {
				throwOnOSError(fsGetCatalogInfoBulkReturn);
			}
			SY_ASSERT(itemCount <= 64);
			for (::ItemCount i = 0; i < itemCount; ++i) {
				SY_ASSERT(itemInfo.extension == 0);
				if (::LSCopyItemInfoForRef(&fsRefs[i], kLSRequestExtension | kLSRequestTypeCreator
						| kLSRequestBasicFlagsOnly, &itemInfo) == noErr) {
					if ((itemInfo.flags & (kLSItemInfoIsPlainFile | kLSItemInfoIsInvisible))
							== kLSItemInfoIsPlainFile) {
						bool isFXP = (itemInfo.filetype == 'AFxP' || (itemInfo.extension != 0
								&& ::CFStringCompare(itemInfo.extension, CFSTR("fxp"), kCFCompareCaseInsensitive)
								== kCFCompareEqualTo));
						bool isFXB = (itemInfo.filetype == 'AFxB' || (itemInfo.extension != 0
								&& ::CFStringCompare(itemInfo.extension, CFSTR("fxb"), kCFCompareCaseInsensitive)
								== kCFCompareEqualTo));
						if ((isFXP && !presetIsFXB) || isFXB) {
						#if (SY_DO_TRACE)
							char buffer[1023 + 1];
							if (::FSRefMakePath(&fsRefs[i], reinterpret_cast< ::UInt8* >(buffer), 1023) == noErr) {
								SY_TRACE2(SY_TRACE_MISC, "Found %s: %s", (isFXP) ? "fxp" : "fxb", buffer);
							}
						#endif
							convertVSTPreset(&fsRefs[i], isFXB);
						}
					}
					releaseCFRef((::CFTypeRef*)&itemInfo.extension);
				}
			}
		} while (fsGetCatalogInfoBulkReturn == noErr);

		::OSErr err = ::FSCloseIterator(iterator);
		SY_ASSERT(err == noErr);
		iterator = 0;
	}
	catch (...) {
		if (iterator != 0) {
			::OSErr err = ::FSCloseIterator(iterator);
			SY_ASSERT(err == noErr);
			iterator = 0;
		}
		releaseCFRef((::CFTypeRef*)&itemInfo.extension);
		// No throw!
	}
}

void SymbiosisComponent::createFactoryPresets(::FSRef* factoryPresetsListFSRef) {
	SY_ASSERT(factoryPresetsListFSRef != 0);
	
	::CFDictionaryRef auPresetDictionary = 0;
	::CFStringRef auPresetName = 0;
	::FSIORefNum fileFork = 0;
	bool isForkOpen = false;
	try {
		::HFSUniStr255 dataForkName;
		throwOnOSError(::FSGetDataForkName(&dataForkName));
		throwOnOSError(::FSOpenFork(factoryPresetsListFSRef, dataForkName.length, dataForkName.unicode, fsWrPerm
				, &fileFork));
		isForkOpen = true;
	
		if (presetIsFXB) {
			::FSRef newFSRef;
			::OSErr err = ::FSMakeFSRefUnicode(&resourcesFSRef, kDefaultFactoryPresetFileNameChars
					, kDefaultFactoryPresetFileName, kTextEncodingUnknown, &newFSRef);
			if (err == noErr) {
				::FSDeleteObject(&newFSRef);
			}
			throwOnOSError(::FSCreateFileUnicode(&resourcesFSRef, kDefaultFactoryPresetFileNameChars
					, kDefaultFactoryPresetFileName, kFSCatInfoNone, 0, &newFSRef, 0));
			auPresetName = ::CFStringCreateWithCString(0, kDefaultFactoryPresetName, kCFStringEncodingMacRoman);
			SY_ASSERT(auPresetName != 0);
			auPresetDictionary = createAUPresetOfCurrentBank(auPresetName);
			releaseCFRef((::CFTypeRef*)&auPresetName);
			saveProperties(auPresetDictionary, &newFSRef);
			releaseCFRef((::CFTypeRef*)&auPresetDictionary);
			SY_TRACE(SY_TRACE_MISC, "Converted single fxb factory preset");
			
			::ByteCount actualCount;
			throwOnOSError(::FSWriteFork(fileFork, fsAtMark, 0, kDefaultFactoryPresetFileNameCRChars
					, kDefaultFactoryPresetFileNameCR, &actualCount));
			SY_ASSERT(static_cast<int>(actualCount) == kDefaultFactoryPresetFileNameCRChars);
		} else {
			convertLoadedPrograms(&resourcesFSRef, true, fileFork);
		}

		::OSErr err = ::FSCloseFork(fileFork);
		SY_ASSERT(err == noErr);
		isForkOpen = false;
	}
	catch (...) {
		if (isForkOpen) {
			::OSErr err = ::FSCloseFork(fileFork);
			SY_ASSERT(err == noErr);
			isForkOpen = false;
		}
		releaseCFRef((::CFTypeRef*)&auPresetDictionary);
		releaseCFRef((::CFTypeRef*)&auPresetName);
		throw;
	}
}

void SymbiosisComponent::loadFactoryPresets(::FSRef* factoryPresetsListFSRef) {
	SY_ASSERT(factoryPresetsListFSRef != 0);
	
	::CFPropertyListRef properties = 0;
	unsigned char* bytes = 0;
	try {
		SY_ASSERT(factoryPresetsArray == 0);					
		factoryPresetsArray = ::CFArrayCreateMutable(0, 0, 0);
		SY_ASSERT(factoryPresetsArray != 0);
								
		size_t size = 0;
		bytes = loadFromFile(factoryPresetsListFSRef, size);
		
		char line[2047 + 1];
		const unsigned char* bp = bytes;
		const unsigned char* ep = bytes + size;
		int factoryPresetCount = 0;
		while (bp < ep && factoryPresetCount < kMaxFactoryPresets) {
			bp = readLine(bp, ep, line, 2047);
			const char* lp = eatSpace(line);
			if ((*lp) == '\0' || (*lp) == ';') {
				continue;
			}
			
			::HFSUniStr255 presetFileName;
			presetFileName.length = strlen(lp);
			for (int i = 0; i < presetFileName.length; ++i) {
				presetFileName.unicode[i] = lp[i];
			}
			
			::FSRef fsRef;
			throwOnOSError(::FSMakeFSRefUnicode(&resourcesFSRef, presetFileName.length, presetFileName.unicode
					, kTextEncodingUnknown, &fsRef));
			properties = loadProperties(&fsRef);
			if (::CFGetTypeID(properties) != ::CFDictionaryGetTypeID()) {
				throw FormatException("Invalid AUPreset format");
			}
			
			::CFDataRef vstData = reinterpret_cast< ::CFDataRef >(getValueOfKeyInDictionary
					(reinterpret_cast< ::CFDictionaryRef >(properties), CFSTR(kAUPresetVSTDataKey)
					, ::CFDataGetTypeID()));
			::CFStringRef presetName = reinterpret_cast< ::CFStringRef >(getValueOfKeyInDictionary
					(reinterpret_cast< ::CFDictionaryRef >(properties), CFSTR(kAUPresetNameKey)
					, ::CFStringGetTypeID()));
			
			factoryPresets[factoryPresetCount].presetNumber = factoryPresetCount;
			factoryPresets[factoryPresetCount].presetName = presetName;
			factoryPresetData[factoryPresetCount] = vstData;
			::CFArrayAppendValue(factoryPresetsArray, &factoryPresets[factoryPresetCount]);
			::CFRetain(presetName);
			::CFRetain(vstData);
			++factoryPresetCount;
			
			releaseCFRef((::CFTypeRef*)&properties);
		}
		delete [] bytes;
		bytes = 0;
		SY_ASSERT(factoryPresetCount == ::CFArrayGetCount(factoryPresetsArray));
		SY_TRACE1(SY_TRACE_MISC, "Successfully loaded %d factory presets", factoryPresetCount);
	}
	catch (const std::exception& x) {
		SY_TRACE1(SY_TRACE_EXCEPTIONS, "Failed loading factory presets, caught exception: %s", x.what());
		delete [] bytes;
		bytes = 0;
		releaseCFRef((::CFTypeRef*)&properties);
		// No throw!
	}
	catch (...) {
		SY_TRACE(SY_TRACE_EXCEPTIONS, "Failed loading factory presets (caught general exception)");
		delete [] bytes;
		bytes = 0;
		releaseCFRef((::CFTypeRef*)&properties);
		// No throw!
	}
}

void SymbiosisComponent::loadOrCreateFactoryPresets() {
	::FSRef factoryPresetsListFSRef;
	::OSErr err = ::FSMakeFSRefUnicode(&resourcesFSRef, kFactoryPresetsFileNameChars, kFactoryPresetsFileName
			, kTextEncodingUnknown, &factoryPresetsListFSRef);
	if (err == fnfErr) {
		throwOnOSError(::FSCreateFileUnicode(&resourcesFSRef, kFactoryPresetsFileNameChars, kFactoryPresetsFileName
				, kFSCatInfoNone, 0, &factoryPresetsListFSRef, 0));
		createFactoryPresets(&factoryPresetsListFSRef);
		err = ::FSMakeFSRefUnicode(&resourcesFSRef, kFactoryPresetsFileNameChars, kFactoryPresetsFileName
				, kTextEncodingUnknown, &factoryPresetsListFSRef);
	}
	throwOnOSError(err);
	loadFactoryPresets(&factoryPresetsListFSRef);
}

void SymbiosisComponent::convertVSTPresets() {
	char name[255 + 1];
	getComponentName(name);
	try {
		convertVSTPresetsInDomain(kUserDomain, name);
	}
	catch (const std::exception& x) {
		SY_TRACE1(SY_TRACE_EXCEPTIONS, "Failed converting presets in user domain, caught exception: %s", x.what());
		// No throw!
	}
	catch (...) {
		SY_TRACE(SY_TRACE_EXCEPTIONS, "Failed converting presets in user domain (caught general exception)");
		// No throw!
	}
	try {
		convertVSTPresetsInDomain(kLocalDomain, name);
	}
	catch (const std::exception& x) {
		SY_TRACE1(SY_TRACE_EXCEPTIONS, "Failed converting presets in local domain, caught exception: %s", x.what());
		// No throw!
	}
	catch (...) {
		SY_TRACE(SY_TRACE_EXCEPTIONS, "Failed converting presets in local domain (caught general exception)");
		// No throw!
	}
}

void SymbiosisComponent::readParameterMapping(const ::FSRef* fsRef) {
	SY_ASSERT(fsRef != 0);
	
	SY_ASSERT(parameterCount == 0);
	unsigned char* bytes = 0;
	::CFArrayRef choicesArray = 0;
	::CFStringRef choicesString = 0;
	::AudioUnitParameterInfo info;
	memset(&info, 0, sizeof (info));
	try {
		size_t size = 0;
		bytes = loadFromFile(fsRef, size);
		char line[2047 + 1];
		const unsigned char* bp = bytes;
		const unsigned char* ep = bytes + size;
		bp = readLine(bp, ep, line, 2047);
		int lineNumber = 2;
		while (bp < ep) {
			bp = readLine(bp, ep, line, 2047);
			const char* lp = eatSpace(line);
			if ((*lp) == '\0' || (*lp) == ';') {
				continue;
			}
			
			char indexAndFlags[32 + 1] = "";
			char auName[255 + 1] = "";
			float auMin = 0.0f;
			float auMax = 0.0f;
			float auDefault = 0.0f;
			char auUnit[255 + 1] = "";
			char auDisplayOption[1023 + 1] = "";
			int items = sscanf(lp, "%32s%*[\t]%255[^\t]%*[\t]%f%*[\t]%f%*[\t]%1023[^\t]%*[\t]%255[^\t]%*[\t]%f"
					, indexAndFlags, auName, &auMin, &auMax, auDisplayOption, auUnit, &auDefault);
			const char* auDisplayOptionPointer = eatSpace(auDisplayOption);

			bool isMeta = false;
			int vstParameterIndex = 0;
			size_t indexAndFlagsLength = strlen(indexAndFlags);
			if (indexAndFlagsLength > 0) {
				if (indexAndFlags[indexAndFlagsLength - 1] == '+') {
					indexAndFlags[indexAndFlagsLength - 1] = 0;
					isMeta = true;
				}
				vstParameterIndex = atoi(indexAndFlags);
			}
			
			bool isValid = true;
			if (items != 7) {
				isValid = false;
			} else if (!(vstParameterIndex >= 0 && vstParameterIndex < vst->getParameterCount())) {
				isValid = false;
			} else if (auMin >= auMax) {
				isValid = false;
			} else if (auDefault < auMin || auDefault > auMax) {
				isValid = false;
			} else if (parameterInfos[vstParameterIndex].name[0] != '\0') {												// Already exists?
				isValid = false;
			} else if (auDisplayOptionPointer[0] == '\0') {
				isValid = false;
			}
			
			if (!isValid) {
				SY_TRACE2(SY_TRACE_MISC, "Ignored invalid parameter-mapping line (%d): %s", lineNumber, line);
			} else {
				strncpy(info.name, auName, 51);
				info.name[51] = '\0';
				info.unitName = 0;
				info.unit = kAudioUnitParameterUnit_Generic;
				if (auUnit[0] != '\0' && strcmp(auUnit, "-") != 0) {
					info.unitName = ::CFStringCreateWithCString(0, auUnit, kCFStringEncodingMacRoman);
					SY_ASSERT(info.unitName != 0);
					info.unit = kAudioUnitParameterUnit_CustomUnit;
				}
				if (strcmp(auDisplayOptionPointer, "=") == 0) {
					info.flags = kAudioUnitParameterFlag_HasCFNameString | kAudioUnitParameterFlag_IsReadable
							| kAudioUnitParameterFlag_IsWritable;
				} else if (strcmp(auDisplayOptionPointer, "?") == 0) {
					info.flags = kAudioUnitParameterFlag_HasCFNameString | kAudioUnitParameterFlag_IsReadable
							| kAudioUnitParameterFlag_IsWritable | kAudioUnitParameterFlag_ValuesHaveStrings;
				} else if (strcmp(auDisplayOptionPointer, "b") == 0) {
					auMin = 0;
					auMax = 1;
					info.unit = kAudioUnitParameterUnit_Boolean;
					info.flags = kAudioUnitParameterFlag_HasCFNameString | kAudioUnitParameterFlag_IsReadable
							| kAudioUnitParameterFlag_IsWritable;
				} else {
					SY_ASSERT(choicesString == 0);
					choicesString = ::CFStringCreateWithCString(0, auDisplayOptionPointer, kCFStringEncodingMacRoman);
					SY_ASSERT(choicesString != 0);
					SY_ASSERT(choicesArray == 0);
					choicesArray = ::CFStringCreateArrayBySeparatingStrings(0, choicesString, CFSTR("|"));
					SY_ASSERT(choicesArray != 0);
					releaseCFRef((::CFTypeRef*)&choicesString);
					auMin = 0;
					auMax = static_cast<int>(::CFArrayGetCount(choicesArray)) - 1;
					SY_ASSERT(auMax >= 0);
					info.unit = kAudioUnitParameterUnit_Indexed;
					info.flags = kAudioUnitParameterFlag_HasCFNameString | kAudioUnitParameterFlag_IsReadable
							| kAudioUnitParameterFlag_IsWritable;
				}
				info.clumpID = 0;
				info.cfNameString = ::CFStringCreateWithCString(0, auName, kCFStringEncodingMacRoman);
				SY_ASSERT(info.cfNameString != 0);
				info.minValue = auMin;
				info.maxValue = auMax;
				info.defaultValue = auDefault;
				if (isMeta) {
					info.flags |= kAudioUnitParameterFlag_IsGlobalMeta;
				}
				if (parameterCount >= kMaxMappedParameters) {
					throw SymbiosisException("Too many mapped parameters");
				}
				parameterList[parameterCount] = vstParameterIndex;
				++parameterCount;
				parameterInfos[vstParameterIndex] = info;
				memset(&info, 0, sizeof (info));
				parameterValueStrings[vstParameterIndex] = choicesArray;
				choicesArray = 0;
			}
			++lineNumber;
		}
		delete [] bytes;
		bytes = 0;
		SY_TRACE1(SY_TRACE_MISC, "Successfully parsed %d parameter-mapping lines", parameterCount);
	}
	catch (...) {
		releaseCFRef((::CFTypeRef*)&info.unitName);
		releaseCFRef((::CFTypeRef*)&info.cfNameString);
		releaseCFRef((::CFTypeRef*)&choicesString);
		releaseCFRef((::CFTypeRef*)&choicesArray);
		delete [] bytes;
		bytes = 0;
		throw;
	}
}

void SymbiosisComponent::createDefaultParameterMappingFile(const ::FSRef* fsRef) {
	SY_ASSERT(fsRef != 0);
	
	::FSIORefNum fileFork = 0;
	bool isForkOpen = false;
	try {
		::HFSUniStr255 dataForkName;
		throwOnOSError(::FSGetDataForkName(&dataForkName));
		throwOnOSError(::FSOpenFork(fsRef, dataForkName.length, dataForkName.unicode, fsWrPerm, &fileFork));
		isForkOpen = true;
		char line[2047 + 1];
		snprintf(line, 2047 + 1, "vst param #\tname\tmin\tmax\tdisplay\tunit\tdefault\r");
		::ByteCount actualCount;
		throwOnOSError(::FSWriteFork(fileFork, fsAtMark, 0, strlen(line), line, &actualCount));
		SY_ASSERT(actualCount == strlen(line));
		
		for (int i = 0; i < vst->getParameterCount(); ++i) {
			char parameterName[24 + 1];
			vst->getParameterName(i, parameterName);
			char parameterLabel[24 + 1];
			vst->getParameterLabel(i, parameterLabel);
			
			float currentValue = vst->getParameter(i);
			char displayDefault[24 + 1];
			vst->getParameterDisplay(i, displayDefault);

			vst->setParameter(i, 0);
			char displayLow[24 + 1];
			vst->getParameterDisplay(i, displayLow);

			vst->setParameter(i, 0.5f);
			char displayMid[24 + 1];
			vst->getParameterDisplay(i, displayMid);

			vst->setParameter(i, 1);
			char displayHigh[24 + 1];
			vst->getParameterDisplay(i, displayHigh);
			
			vst->setParameter(i, currentValue);
			char* e;
			float lowValue = 0.0f;
			float defaultValue = currentValue;
			float highValue = 1.0f;
			float avgValue;
			float midValue;
			const char* eatenParameterName = eatSpace(parameterName);
			const char* eatenParameterLabel = eatSpace(parameterLabel);
			if (eatenParameterName[0] == '\0') {
				eatenParameterName = "-";
			}
			if (eatenParameterLabel[0] == '\0') {
				eatenParameterLabel = "-";
			}
			char displayChar = '=';
			if ((lowValue = strtof(displayLow, &e), e != &displayLow[strlen(displayLow)])
					|| (defaultValue = strtof(displayDefault, &e), e != &displayDefault[strlen(displayDefault)])
					|| (highValue = strtof(displayHigh, &e), e != &displayHigh[strlen(displayHigh)])
					|| (midValue = strtof(displayMid, &e), e != &displayMid[strlen(displayMid)])
					|| (avgValue = (lowValue + highValue) * 0.5f, midValue < avgValue - 0.0001f
					|| midValue > avgValue + 0.0001f)) {
				if (vstGotSymbiosisExtensions) {
					displayChar = '?';
				} else {
					eatenParameterLabel = "-";
				}
				lowValue = 0.0f;
				highValue = 1.0f;
				defaultValue = currentValue;
			}
			snprintf(line, 2047 + 1, "%d\t%s\t%g\t%g\t%c\t%s\t%g\r", i, eatenParameterName, lowValue, highValue
					, displayChar, eatenParameterLabel, defaultValue);
			throwOnOSError(::FSWriteFork(fileFork, fsAtMark, 0, strlen(line), line, &actualCount));
			SY_ASSERT(actualCount == strlen(line));
		}
		::OSErr err = ::FSCloseFork(fileFork);
		SY_ASSERT(err == noErr);
		isForkOpen = false;
	}
	catch (...) {
		if (isForkOpen) {
			::OSErr err = ::FSCloseFork(fileFork);
			SY_ASSERT(err == noErr);
			isForkOpen = false;
		}
		throw;
	}
}

void SymbiosisComponent::readOrCreateParameterMapping() {
	::FSRef parametersFSRef;
	::OSErr err = ::FSMakeFSRefUnicode(&resourcesFSRef, kParametersFileNameChars, kParametersFileName
			, kTextEncodingUnknown, &parametersFSRef);
	if (err == fnfErr) {
		throwOnOSError(::FSCreateFileUnicode(&resourcesFSRef, kParametersFileNameChars, kParametersFileName
				, kFSCatInfoNone, 0, &parametersFSRef, 0));
		createDefaultParameterMappingFile(&parametersFSRef);
		err = ::FSMakeFSRefUnicode(&resourcesFSRef, kParametersFileNameChars, kParametersFileName, kTextEncodingUnknown
				, &parametersFSRef);
	}
	throwOnOSError(err);
	readParameterMapping(&parametersFSRef);
}

void SymbiosisComponent::reallocateIOBuffers() {
	int ioCount = vst->getInputCount();
	int outputCount = vst->getOutputCount();
	if (ioCount < outputCount) {
		ioCount = outputCount;
	}
	for (int i = 0; i < kMaxChannels; ++i) {
		delete [] ioBuffers[i];
		ioBuffers[i] = 0;
	}
	for (int i = 0; i < ioCount; ++i) {
		ioBuffers[i] = new float[maxFramesPerSlice];
	}
}

int SymbiosisComponent::getMaxInputChannels(int busNumber) const {
	SY_ASSERT(0 <= busNumber && busNumber < kMaxBuses);
	int count = inputBusChannelNumbers[busNumber + 1] - inputBusChannelNumbers[busNumber];
	SY_ASSERT(0 <= count && count < kMaxChannels);
	return count;
}

int SymbiosisComponent::getMaxOutputChannels(int busNumber) const {
	SY_ASSERT(0 <= busNumber && busNumber < kMaxBuses);
	int count = outputBusChannelNumbers[busNumber + 1] - outputBusChannelNumbers[busNumber];
	SY_ASSERT(0 <= count && count < kMaxChannels);
	return count;
}

int SymbiosisComponent::getActiveInputChannels(int busNumber) const {
	SY_ASSERT(0 <= busNumber && busNumber < kMaxBuses);
	return inputBusChannelCounts[busNumber];
}

int SymbiosisComponent::getActiveOutputChannels(int busNumber) const {
	SY_ASSERT(0 <= busNumber && busNumber < kMaxBuses);
	return outputBusChannelCounts[busNumber];
}

void SymbiosisComponent::tryToIdentifyHostApplication() {
	hostApplication = undetermined;
	::CFBundleRef mainBundleRef = ::CFBundleGetMainBundle();
	SY_TRACE1(SY_TRACE_MISC, "Main bundle reference : %p", mainBundleRef);
	if (mainBundleRef != 0) {
		::CFStringRef mainBundleIdRef = ::CFBundleGetIdentifier(mainBundleRef);
		::CFTypeRef versionRef = ::CFBundleGetValueForInfoDictionaryKey(mainBundleRef
				, CFSTR("CFBundleShortVersionString"));

		char buffer[1024];
		SY_TRACE2(SY_TRACE_MISC, "Main bundle id reference : %p = %s"
				, mainBundleIdRef, (mainBundleIdRef != 0)
				? cfStringToCString(mainBundleIdRef, kCFStringEncodingMacRoman, buffer, 1023) : "?");
		SY_TRACE2(SY_TRACE_MISC, "Main bundle version reference : %p = %s"
				, versionRef, (versionRef != 0 && ::CFGetTypeID(versionRef) == ::CFStringGetTypeID())
				? cfStringToCString(reinterpret_cast< ::CFStringRef >(versionRef), kCFStringEncodingMacRoman, buffer
				, 1023) : "?");

		if (mainBundleIdRef != 0 && versionRef != 0 && ::CFGetTypeID(versionRef) == ::CFStringGetTypeID()) {
			if (::CFStringCompare(mainBundleIdRef, CFSTR("com.apple.logic.pro"), 0) == kCFCompareEqualTo
					|| ::CFStringCompare(mainBundleIdRef, CFSTR("com.apple.logic.express"), 0) == kCFCompareEqualTo) {
				if (::CFStringCompare(reinterpret_cast< ::CFStringRef >(versionRef), CFSTR("8.0.0")
						, kCFCompareCaseInsensitive | kCFCompareNumerically) == kCFCompareLessThan) {
					hostApplication = olderLogic;
				} else if (::CFStringCompare(reinterpret_cast< ::CFStringRef >(versionRef), CFSTR("8.0.1")
						, kCFCompareCaseInsensitive | kCFCompareNumerically) == kCFCompareLessThan) {
					hostApplication = logic8_0;
				}
			} else if (::CFStringCompare(mainBundleIdRef, CFSTR("com.apple.garageband"), 0) == kCFCompareEqualTo) {
				if (::CFStringCompare(reinterpret_cast< ::CFStringRef >(versionRef), CFSTR("4.2")
						, kCFCompareCaseInsensitive | kCFCompareNumerically) == kCFCompareLessThan) {
					hostApplication = olderGarageBand;
				}
			}
		}
	}
}

SymbiosisComponent::SymbiosisComponent(::AudioUnit auComponentInstance)
		: auComponentInstance(auComponentInstance), auBundleRef(0), maxFramesPerSlice(kDefaultMaxFramesPerSlice)
		, renderNotificationReceiversCount(0), lastRenderSampleTime(-12345678), silentOutput(false)
		, propertyListenersCount(0), factoryPresetsArray(0), parameterCount(0), parameterInfos(0)
		, parameterValueStrings(0), presetIsFXB(false), autoConvertPresets(false), updateNameOnLoad(false)
		, canDoMonoIO(false), vst(0), vstGotSymbiosisExtensions(false), vstSupportsTail(false), initialDelayTime(0.0)
		, tailTime(0.0), vstSupportsBypass(false), isBypassing(false), inputBusCount(0), outputBusCount(0)
		, auChannelInfoCount(0), hostApplication(undetermined), idleTimerRef(0)
	#if (SY_INCLUDE_GUI_SUPPORT)
	#if (SY_USE_COCOA_GUI)
		, cocoaView(0)
	#elif (!SY_USE_COCOA_GUI)
		, viewComponentInstance(0), viewEventListener(0), viewEventListenerUserData(0), viewWindowRef(0), viewControl(0)
	#endif
	#endif
{
	SY_ASSERT(auComponentInstance != 0);
	
	memset(&streamFormat, 0, sizeof (streamFormat));
	memset(&inputConnections, 0, sizeof (inputConnections));
	memset(&renderCallbacks, 0, sizeof (renderCallbacks));
	memset(&ioBuffers, 0, sizeof (ioBuffers));
	memset(&hostCallbackInfo, 0, sizeof (hostCallbackInfo));
	memset(&currentAUPreset, 0, sizeof (currentAUPreset));
	memset(factoryPresets, 0, sizeof (factoryPresets));
	memset(factoryPresetData, 0, sizeof (factoryPresetData));
	memset(&vstMidiEvents, 0, sizeof (vstMidiEvents));
	memset(&vstTimeInfo, 0, sizeof (vstTimeInfo));
	memset(inputBusChannelNumbers, 0, sizeof (inputBusChannelNumbers));
	memset(inputBusChannelCounts, 0, sizeof (inputBusChannelCounts));
	memset(outputBusChannelNumbers, 0, sizeof (outputBusChannelNumbers));
	memset(outputBusChannelCounts, 0, sizeof (outputBusChannelCounts));
	memset(inputBusNames, 0, sizeof (inputBusNames));
	memset(outputBusNames, 0, sizeof (outputBusNames));
	memset(auChannelInfos, 0, sizeof (auChannelInfos));

	streamFormat.mSampleRate = kDefaultSampleRate;
	streamFormat.mFormatID = kAudioFormatLinearPCM;
	streamFormat.mFormatFlags = kAudioFormatFlagIsFloat | kBigEndianPCMFlag | kAudioFormatFlagIsPacked
			| kAudioFormatFlagIsNonInterleaved;
	streamFormat.mBytesPerPacket = 4;
	streamFormat.mFramesPerPacket = 1;
	streamFormat.mBytesPerFrame = 4;
	streamFormat.mChannelsPerFrame = 2;
	streamFormat.mBitsPerChannel = 32;
	streamFormat.mReserved = 0;
	currentAUPreset.presetNumber = -1;

	::CFURLRef urlRef1 = 0;
	::CFURLRef urlRef2 = 0;
	::CFArrayRef urlArrayRef = 0;
	::CFBundleRef vstBundleRef = 0;
	try {
		// --- Initialize current preset info and allocate MIDI events
		
		SY_ASSERT(currentAUPreset.presetName == 0);
		currentAUPreset.presetName = ::CFStringCreateWithCString(0, kInitialPresetName, kCFStringEncodingMacRoman);
		SY_ASSERT(currentAUPreset.presetName != 0);

		for (int i = 0; i < kMaxVSTMIDIEvents; ++i) {
			if (vstMidiEvents.events[i] == 0) {
				vstMidiEvents.events[i] = reinterpret_cast<VstEvent*>(new VstMidiEvent);
				memset(vstMidiEvents.events[i], 0, sizeof (VstMidiEvent));
				vstMidiEvents.events[i]->type = kVstMidiType;
				vstMidiEvents.events[i]->byteSize = 24;
			}
		}

		// --- Find ourselves and load configuration from info.plist

		getComponentName(gTraceIdentifierString);

		char bundlePath[1023 + 1];
		getPathForThisImage(bundlePath);																				// We need to find the path through this mechanism since we do not know of a bundle identifier to look for (every component should have a unique identifier).
		SY_ASSERT(urlRef1 == 0);
		throwOnNull(urlRef1 = ::CFURLCreateFromFileSystemRepresentation(0, reinterpret_cast< ::UInt8* >(bundlePath)
				, strlen(bundlePath), false), "Could not create URL from file system representation");
		for (int i = 0; i < 3; ++i) {																					// Move three steps up to get the bundle directory.
			throwOnNull(urlRef2 = ::CFURLCreateCopyDeletingLastPathComponent(0, urlRef1)
					, "Could not remove last path component from URL");
			releaseCFRef((::CFTypeRef*)&urlRef1);
			urlRef1 = urlRef2;
			urlRef2 = 0;
		}
		SY_ASSERT(auBundleRef == 0);
		throwOnNull(auBundleRef = ::CFBundleCreate(0, urlRef1), "Could not create bundle from URL");
		releaseCFRef((::CFTypeRef*)&urlRef1);
								
		loadConfiguration();

		// --- Create FSRef for our Resources folder

		SY_ASSERT(urlRef1 == 0);
		throwOnNull(urlRef1 = ::CFBundleCopyResourcesDirectoryURL(auBundleRef)
				, "Could not locate resources directory within bundle");
		if (!::CFURLGetFSRef(urlRef1, &resourcesFSRef)) {
			throw MacOSException(fnfErr);
		}
		releaseCFRef((::CFTypeRef*)&urlRef1);

		// --- Find "external" VST bundle or alias in our resources (or use this bundle for VST too)

		SY_ASSERT(urlArrayRef == 0);
		throwOnNull(urlArrayRef = ::CFBundleCopyResourceURLsOfType(auBundleRef, CFSTR("vst"), 0)
				, "Could not locate resources of specific type in bundle");
		size_t vstCount = ::CFArrayGetCount(urlArrayRef);
		if (vstCount < 1) {
			::CFRetain(auBundleRef);
			SY_ASSERT(vstBundleRef == 0);
			vstBundleRef = auBundleRef;
			SY_TRACE(SY_TRACE_MISC, "No VST bundle or alias found in resources, assuming fat AU bundle");
		} else if (vstCount >= 2) {
			throw SymbiosisException("Found more than one VST bundle or alias in resources");
		} else {
			urlRef1 = reinterpret_cast< ::CFURLRef >(::CFArrayGetValueAtIndex(urlArrayRef, 0));
			::CFRetain(urlRef1);
		#if (SY_DO_TRACE && SY_TRACE_MISC)
			char buffer[1024] = "?";
			::CFURLGetFileSystemRepresentation(urlRef1, true, reinterpret_cast< ::UInt8* >(buffer), 1023);
			SY_TRACE1(SY_TRACE_MISC, "Found VST bundle or alias at %s", buffer);
		#endif

			// --- Resolve alias (if it is an alias)
			
			::FSRef fsRef;
			if (::CFURLGetFSRef(urlRef1, &fsRef)) {
				::Boolean targetIsFolder;
				::Boolean wasAliased;
				if (::FSResolveAliasFile(&fsRef, true, &targetIsFolder, &wasAliased) == noErr) {
					releaseCFRef((::CFTypeRef*)&urlRef1);
					throwOnNull(urlRef1 = ::CFURLCreateFromFSRef(NULL, &fsRef), "Could not create URL from FSRef");
				#if (SY_DO_TRACE && SY_TRACE_MISC)
					::CFURLGetFileSystemRepresentation(urlRef1, true, reinterpret_cast< ::UInt8* >(buffer), 1023);
					SY_TRACE1(SY_TRACE_MISC, "Resolved alias to %s", buffer);
				#endif
				}
			}
			SY_ASSERT(vstBundleRef == 0);
			throwOnNull(vstBundleRef = ::CFBundleCreate(0, urlRef1), "Could not locate VST bundle");
			releaseCFRef((::CFTypeRef*)&urlRef1);
		}
		releaseCFRef((::CFTypeRef*)&urlArrayRef);
		
		// --- Create and initialize VST plug-in

		vst = new VSTPlugIn(*this, vstBundleRef, static_cast<float>(streamFormat.mSampleRate), maxFramesPerSlice);
		releaseBundleRef(vstBundleRef);
		vst->open();
		
		// --- Check VST compatibility and configuration
		
		int inputCount = vst->getInputCount();
		int outputCount = vst->getOutputCount();
		if (inputCount > kMaxChannels) {
			throw SymbiosisException("VST has too many inputs");
		}
		if (outputCount > kMaxChannels) {
			throw SymbiosisException("VST has too many outputs");
		}
		// We require process replacing, all plug-ins should implement this nowadays.
		if (!vst->canProcessReplacing()) {
			throw SymbiosisException("VST does not support processReplacing()");
		}
		vstGotSymbiosisExtensions = (vst->vendorSpecific('sHi!', 0, 0, 0) != 0);
		vstSupportsTail = (vst->getTailSize() != 0);
		vstSupportsBypass = vst->setBypass(false);
		SY_TRACE1(SY_TRACE_MISC, "VST %s Symbiosis extensions"
				, (vstGotSymbiosisExtensions ? "supports" : "does not support"));
		SY_TRACE1(SY_TRACE_MISC, "VST %s tail size", (vstSupportsTail ? "supports" : "does not support"));
		SY_TRACE1(SY_TRACE_MISC, "VST %s bypassing", (vstSupportsBypass ? "supports" : "does not support"));
		SY_ASSERT0(!vstSupportsTail || !vst->dontProcessSilence()
				, "VST supports tail but has flagged not to process silent input, makes no sense!")
		
		// --- Figure out channel configuration
		
		tryToIdentifyHostApplication();
		switch (hostApplication) {
			case undetermined: SY_TRACE(SY_TRACE_MISC, "Hosting application: undetermined"); break;
			case olderLogic: SY_TRACE(SY_TRACE_MISC, "Hosting application: Logic 7 or older"); break;
			case logic8_0: SY_TRACE(SY_TRACE_MISC, "Hosting application: Logic 8.0"); break;
			case olderGarageBand: SY_TRACE(SY_TRACE_MISC, "Hosting application: GarageBand 4.1 or older"); break;
			default: SY_ASSERT(0);
		}
		
		::OSType type = getComponentType();
		SY_TRACE4(SY_TRACE_MISC, "Component type: %c%c%c%c", static_cast<char>((type >> 24) & 0xFF)
				, static_cast<char>((type >> 16) & 0xFF), static_cast<char>((type >> 8) & 0xFF)
				, static_cast<char>((type >> 0) & 0xFF));

		/*
			Instruments may have a variable number of channels on it's output buses if we return an "unsupported" error
			on kAudioUnitProperty_SupportedNumChannels. Effects need to support this though (or they will be required to
			take any number of inputs -> any number of outputs), which also means *effects need the same number of
			channels on all output buses.* This is simply a limitation in the AU design. Not much we can do about it.
			According to Apple, this choice of design was made for historical reasons.
			
			Furthermore, Logic 7 (or older) doesn't support a mixture of mono and stereo on instruments either.
		*/
		
		bool requireNumChannels = (type != kAudioUnitType_MusicDevice || hostApplication == olderLogic);
		
		// --- Figure out input bus configuration
		
		int inputPinIndex = 0;
		int inputChannelCount = 0;
		while (inputPinIndex < inputCount) {
			VstPinProperties properties;
			bool propertiesSupported = vst->getInputProperties(inputPinIndex, properties);
			if (inputPinIndex == 0 || !requireNumChannels) {
				inputChannelCount = ((inputCount & 1) == 0 ? 2 : 1);
				if (propertiesSupported) {
					inputChannelCount = ((properties.flags & kVstPinIsStereo) != 0 ? 2 : 1);
				}
			}
			if (inputPinIndex + inputChannelCount <= inputCount) {
				SY_ASSERT(inputBusCount <= kMaxBuses);
				inputBusChannelNumbers[inputBusCount] = inputPinIndex;
				if (propertiesSupported) {
					inputBusNames[inputBusCount] = ::CFStringCreateWithCString(0, properties.label
							, kCFStringEncodingMacRoman);
				}
				inputBusChannelCounts[inputBusCount] = inputChannelCount;
				++inputBusCount;
				inputPinIndex += inputChannelCount;
			}
		}
		SY_ASSERT(inputBusCount <= kMaxBuses);
		inputBusChannelNumbers[inputBusCount] = inputPinIndex;
		SY_ASSERT0(inputPinIndex == inputCount, "Invalid VST input count");

		// --- Figure out output bus configuration

		int outputPinIndex = 0;
		int outputChannelCount = 0;
		while (outputPinIndex < outputCount) {
			VstPinProperties properties;
			bool propertiesSupported = vst->getOutputProperties(outputPinIndex, properties);
			if (outputPinIndex == 0 || !requireNumChannels) {
				outputChannelCount = ((outputCount & 1) == 0 ? 2 : 1);
				if (propertiesSupported) {
					outputChannelCount = ((properties.flags & kVstPinIsStereo) != 0 ? 2 : 1);
				}
			}
			if (outputPinIndex + outputChannelCount <= outputCount) {
				SY_ASSERT(outputBusCount <= kMaxBuses);
				outputBusChannelNumbers[outputBusCount] = outputPinIndex;
				if (propertiesSupported) {
					outputBusNames[outputBusCount] = ::CFStringCreateWithCString(0, properties.label
							, kCFStringEncodingMacRoman);
				}
				outputBusChannelCounts[outputBusCount] = outputChannelCount;
				++outputBusCount;
				outputPinIndex += outputChannelCount;
			}
			// FIX : char label[kVstMaxLabelLen];	///< pin name
			// FIX : 	char shortLabel[kVstMaxShortLabelLen];	///< short name (recommended: 6 + delimiter)
		}
		SY_ASSERT(outputBusCount <= kMaxBuses);
		outputBusChannelNumbers[outputBusCount] = outputPinIndex;
		SY_ASSERT0(outputPinIndex == outputCount, "Invalid VST output count");
		
		int maxInputChannels = ((inputBusCount > 0) ? getMaxInputChannels(0) : 0);
		int maxOutputChannels = ((outputBusCount > 0) ? getMaxOutputChannels(0) : 0);
		
		bool supportNumChannelsProperty = true;
		for (int i = 1; i < inputBusCount; ++i) {
			if (getMaxInputChannels(i) != maxInputChannels) {
				supportNumChannelsProperty = false;
				break;
			}
		}
		for (int i = 1; i < outputBusCount; ++i) {
			if (getMaxOutputChannels(i) != maxOutputChannels) {
				supportNumChannelsProperty = false;
				break;
			}
		}
		
		if (!supportNumChannelsProperty) {
			auChannelInfoCount = 0;
		} else {
			if (canDoMonoIO) {
				if (maxInputChannels == 2) {
					if (maxOutputChannels == 2) {
						SY_ASSERT(auChannelInfoCount < sizeof (auChannelInfos) / sizeof (*auChannelInfos));
						auChannelInfos[auChannelInfoCount].inChannels = 1;
						auChannelInfos[auChannelInfoCount].outChannels = 1;
						++auChannelInfoCount;
					}
					SY_ASSERT(auChannelInfoCount < sizeof (auChannelInfos) / sizeof (*auChannelInfos));
					auChannelInfos[auChannelInfoCount].inChannels = 1;
					auChannelInfos[auChannelInfoCount].outChannels = maxOutputChannels;
					++auChannelInfoCount;
				}
				if (maxOutputChannels == 2) {
					SY_ASSERT(auChannelInfoCount < sizeof (auChannelInfos) / sizeof (*auChannelInfos));
					auChannelInfos[auChannelInfoCount].inChannels = maxInputChannels;
					auChannelInfos[auChannelInfoCount].outChannels = 1;
					++auChannelInfoCount;
				}
			}
			SY_ASSERT(auChannelInfoCount < sizeof (auChannelInfos) / sizeof (*auChannelInfos));
			auChannelInfos[auChannelInfoCount].inChannels = maxInputChannels;
			auChannelInfos[auChannelInfoCount].outChannels = maxOutputChannels;
			++auChannelInfoCount;
		}
		
		SY_ASSERT(auChannelInfoCount > 0 || !requireNumChannels);
		SY_TRACE5(SY_TRACE_MISC, "VST has %d inputs and %d outputs configured into %d input buses and %d output buses"
				" (SupportedNumChannels %s)", inputCount, outputCount, inputBusCount, outputBusCount
				, (auChannelInfoCount > 0 ? "supported" : "not supported"));
		
		// --- Allocate parameters and audio buffers
		
		SY_ASSERT(parameterValueStrings == 0);
		parameterValueStrings = new ::CFArrayRef[vst->getParameterCount()];
		memset(parameterValueStrings, 0, sizeof (::CFArrayRef) * vst->getParameterCount());
		SY_ASSERT(parameterInfos == 0);
		parameterInfos = new ::AudioUnitParameterInfo[vst->getParameterCount()];
		memset(parameterInfos, 0, sizeof (::AudioUnitParameterInfo) * vst->getParameterCount());
		reallocateIOBuffers();
		
		// --- Load (or create) various AU wrapping configurations and convert presets
		
		readOrCreateParameterMapping();
		loadOrCreateFactoryPresets();
		if (autoConvertPresets) {
			convertVSTPresets();
		}

		// --- Update "our" state from VST state
		
		updateInitialDelayTime();
		updateTailTime();
		updateCurrentAUPreset();
								
		// --- Create idle timer event
		
		SY_ASSERT(idleTimerRef == 0);
		throwOnOSError(::InstallEventLoopTimer(::GetMainEventLoop(), kIdleIntervalMS * kEventDurationMillisecond
				, kIdleIntervalMS * kEventDurationMillisecond, idleTimerUPP, reinterpret_cast<void*>(this)
				, &idleTimerRef));
		SY_ASSERT(idleTimerRef != 0);
	}
	catch (...) {
		releaseBundleRef(vstBundleRef);
		releaseCFRef((::CFTypeRef*)&urlRef1);
		releaseCFRef((::CFTypeRef*)&urlRef2);
		releaseCFRef((::CFTypeRef*)&urlArrayRef);
		uninit();
		throw;
	}
}

float SymbiosisComponent::scaleFromAUParameter(int parameterIndex, float auValue) {
	SY_ASSERT(parameterIndex >= 0 && parameterIndex < vst->getParameterCount());
	const ::AudioUnitParameterInfo& parameterInfo = parameterInfos[parameterIndex];
	SY_ASSERT(auValue >= parameterInfo.minValue && auValue <= parameterInfo.maxValue);
	return (auValue - parameterInfo.minValue) / (parameterInfo.maxValue - parameterInfo.minValue);
}

float SymbiosisComponent::scaleToAUParameter(int parameterIndex, float vstValue) {
	SY_ASSERT(parameterIndex >= 0 && parameterIndex < vst->getParameterCount());
	SY_ASSERT(vstValue >= 0.0f && vstValue <= 1.0f);
	const ::AudioUnitParameterInfo& parameterInfo = parameterInfos[parameterIndex];
	switch (parameterInfo.unit) {
		default: SY_ASSERT(0);
		case kAudioUnitParameterUnit_Generic:
		case kAudioUnitParameterUnit_CustomUnit:
			return parameterInfo.minValue + vstValue * (parameterInfo.maxValue - parameterInfo.minValue);
		case kAudioUnitParameterUnit_Boolean:
		case kAudioUnitParameterUnit_Indexed:
			return floorf(parameterInfo.minValue + vstValue * (parameterInfo.maxValue - parameterInfo.minValue) + 0.5f);
	}
}

void SymbiosisComponent::getVendor(VSTPlugIn& plugIn, char vendor[63 + 1]) {
	SY_ASSERT(&plugIn == vst);
	SY_ASSERT(vendor != 0);
	strcpy(vendor, kSymbiosisVSTVendorString);
}

void SymbiosisComponent::getProduct(VSTPlugIn& plugIn, char product[63 + 1]) {
	SY_ASSERT(&plugIn == vst);
	SY_ASSERT(product != 0);
	strcpy(product, kSymbiosisVSTProductString);
}

bool SymbiosisComponent::canDo(VSTPlugIn& plugIn, const char string[]) {
	SY_ASSERT(&plugIn == vst);
	SY_ASSERT(string != 0);
	if (strcmp(string, "sendVstEvents") == 0
			|| strcmp(string, "sendVstMidiEvent") == 0
			|| strcmp(string, "sendVstTimeInfo") == 0
			|| strcmp(string, "reportConnectionChanges") == 0
			|| strcmp(string, "sizeWindow") == 0
			|| strcmp(string, "supplyIdle") == 0) {
		return true;
	} else {
		return false;
	}
}

VstInt32 VSTPlugIn::getVersion() {
	SY_TRACE(SY_TRACE_VST, "VST getVersion");
	return static_cast<VstInt32>(dispatch(effGetVstVersion, 0, 0, 0, 0));
}

VstTimeInfo* SymbiosisComponent::getTimeInfo(VSTPlugIn& plugIn, int /*flags*/) {
	SY_ASSERT(&plugIn == vst);
	return &vstTimeInfo;
}

void SymbiosisComponent::beginEdit(VSTPlugIn& plugIn, int parameterIndex) {
	SY_ASSERT(&plugIn == vst);
	SY_ASSERT(parameterIndex >= 0 && parameterIndex < vst->getParameterCount());

	::AudioUnitEvent myEvent;
	memset(&myEvent, 0, sizeof (::AudioUnitEvent));
	myEvent.mArgument.mParameter.mAudioUnit = auComponentInstance;
	myEvent.mArgument.mParameter.mParameterID = parameterIndex;
	myEvent.mArgument.mParameter.mScope = kAudioUnitScope_Global;
	myEvent.mArgument.mParameter.mElement = 0;

#if (SY_INCLUDE_GUI_SUPPORT)
#if (!SY_USE_COCOA_GUI)
	if (viewEventListener != 0) {																						// Old style
		SY_TRACE2(SY_TRACE_MISC, "Sending mouse down notification for parameter %d to view event listener @0x%8.8x"
				, parameterIndex, reinterpret_cast<unsigned int>(viewEventListener));
		(*viewEventListener)(viewEventListenerUserData, viewComponentInstance, &myEvent.mArgument.mParameter
				, kAudioUnitCarbonViewEvent_MouseDownInControl, 0);
	} else
#endif
#endif
	 {																													// New style
		SY_TRACE1(SY_TRACE_MISC, "Notifying kAudioUnitEvent_BeginParameterChangeGesture on parameter %d"
				, parameterIndex);
		myEvent.mEventType = kAudioUnitEvent_BeginParameterChangeGesture;
		::AUEventListenerNotify(0, 0, &myEvent);
	}
}

void SymbiosisComponent::automate(VSTPlugIn& plugIn, int parameterIndex, float /*value*/) {
	SY_ASSERT(&plugIn == vst);
	SY_ASSERT(parameterIndex >= 0 && parameterIndex < vst->getParameterCount());

	::AudioUnitEvent myEvent;
	memset(&myEvent, 0, sizeof (::AudioUnitEvent));
	myEvent.mArgument.mParameter.mAudioUnit = auComponentInstance;
	myEvent.mArgument.mParameter.mParameterID = parameterIndex;
	myEvent.mArgument.mParameter.mScope = kAudioUnitScope_Global;
	myEvent.mArgument.mParameter.mElement = 0;

	// Old style
	SY_TRACE1(SY_TRACE_FREQUENT, "Calling AUParameterListenerNotify for parameter %d", parameterIndex);
	throwOnOSError(::AUParameterListenerNotify(0, 0, &myEvent.mArgument.mParameter));

	// New style
	SY_TRACE1(SY_TRACE_FREQUENT, "Notifying kAudioUnitEvent_ParameterValueChange on parameter %d", parameterIndex);
	myEvent.mEventType = kAudioUnitEvent_ParameterValueChange;
	::AUEventListenerNotify(0, 0, &myEvent);
}

void SymbiosisComponent::endEdit(VSTPlugIn& plugIn, int parameterIndex) {
	SY_ASSERT(&plugIn == vst);
	SY_ASSERT(parameterIndex >= 0 && parameterIndex < vst->getParameterCount());

	::AudioUnitEvent myEvent;
	memset(&myEvent, 0, sizeof (::AudioUnitEvent));
	myEvent.mArgument.mParameter.mAudioUnit = auComponentInstance;
	myEvent.mArgument.mParameter.mParameterID = parameterIndex;
	myEvent.mArgument.mParameter.mScope = kAudioUnitScope_Global;
	myEvent.mArgument.mParameter.mElement = 0;

#if (SY_INCLUDE_GUI_SUPPORT)
#if (!SY_USE_COCOA_GUI)
	if (viewEventListener != 0) {																						// Old style
		SY_TRACE2(SY_TRACE_MISC, "Sending mouse up notification for parameter %d to view event listener @0x%8.8x"
				, parameterIndex, reinterpret_cast<unsigned int>(viewEventListener));
		(*viewEventListener)(viewEventListenerUserData, viewComponentInstance, &myEvent.mArgument.mParameter
				, kAudioUnitCarbonViewEvent_MouseUpInControl, 0);
	} else
#endif
#endif
	 {																													// New style
		SY_TRACE1(SY_TRACE_MISC, "Notifying kAudioUnitEvent_EndParameterChangeGesture on parameter %d", parameterIndex);
		myEvent.mEventType = kAudioUnitEvent_EndParameterChangeGesture;
		::AUEventListenerNotify(0, 0, &myEvent);
	}
}

bool SymbiosisComponent::isIOPinConnected(VSTPlugIn& plugIn, bool checkOutputPin, int pinIndex) {
	SY_ASSERT(&plugIn == vst);
	SY_ASSERT(pinIndex < (checkOutputPin ? vst->getOutputCount() : vst->getInputCount()));
	// FIX : only works without multiple buses
	// return (pinIndex < static_cast<int>(checkOutputPin ? outputStreamFormat.mChannelsPerFrame : inputStreamFormat.mChannelsPerFrame));
	return true;
}

void SymbiosisComponent::updateDisplay(VSTPlugIn& plugIn) {
	SY_ASSERT(&plugIn == vst);
	if (updateCurrentAUPreset()) {
		propertyChanged(kAudioUnitProperty_CurrentPreset, kAudioUnitScope_Global, 0);
		propertyChanged(kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0);
	}
}

void SymbiosisComponent::resizeWindow(VSTPlugIn& plugIn, int width, int height) {
	SY_ASSERT(&plugIn == vst);
	SY_ASSERT(width > 0);
	SY_ASSERT(height > 0);
#if (SY_INCLUDE_GUI_SUPPORT)
#if (SY_USE_COCOA_GUI)
	SY_ASSERT(cocoaView != 0);
	[cocoaView setFrameSize:NSMakeSize(width, height)];
#elif (!SY_USE_COCOA_GUI)
	SY_ASSERT(viewControl != 0);
	::SizeControl(viewControl, width, height);
#endif
#endif
}

void SymbiosisComponent::idleTimerAction(::EventLoopTimerRef /*theTimer*/, void* theUserData) {
	SymbiosisComponent* Symbiosis = reinterpret_cast<SymbiosisComponent*>(theUserData);
	Symbiosis->vst->idle();
}

void SymbiosisComponent::propertyChanged(::AudioUnitPropertyID id, ::AudioUnitScope scope, ::AudioUnitElement element) {
	// Old style
	for (int i = 0; i < propertyListenersCount; ++i) {
		if (id == propertyListeners[i].fPropertyID) {
			(*propertyListeners[i].fListenerProc)(propertyListeners[i].fListenerRefCon, auComponentInstance, id, scope
					, element);
		}
	}
	
	// New style
	if (propertyListenersCount == 0) {
		::AudioUnitEvent myEvent;
		memset(&myEvent, 0, sizeof (::AudioUnitEvent));
		myEvent.mEventType = kAudioUnitEvent_PropertyChange;
		myEvent.mArgument.mProperty.mAudioUnit = auComponentInstance;
		myEvent.mArgument.mProperty.mPropertyID = id;
		myEvent.mArgument.mProperty.mScope = scope;
		myEvent.mArgument.mProperty.mElement = element;
		::AUEventListenerNotify(0, 0, &myEvent);
	}
}

void SymbiosisComponent::updateCurrentVSTProgramName(::CFStringRef presetName) {
	SY_ASSERT(presetName != 0);
	char buffer[2047 + 1];
	const char* stringPointer = cfStringToCString(presetName, kCFStringEncodingMacRoman, buffer, 2047);
	if (strlen(stringPointer) > 24) {
		strncpy(buffer, stringPointer, 24);
		buffer[24] = '\0';
		stringPointer = buffer;
	}
	vst->setCurrentProgramName(stringPointer);
	SY_TRACE1(SY_TRACE_MISC, "Updated current VST program name to %s", stringPointer);
}

bool SymbiosisComponent::updateCurrentAUPreset() {
	::CFStringRef newPresetName = 0;		
	try {
		char programName[24 + 1] = "";
		vst->getCurrentProgramName(programName);
		newPresetName = ::CFStringCreateWithCString(0, programName, kCFStringEncodingMacRoman);
		SY_ASSERT(newPresetName != 0);
		if (::CFStringCompare(currentAUPreset.presetName, newPresetName, 0) != kCFCompareEqualTo) {
			releaseCFRef((::CFTypeRef*)&currentAUPreset.presetName);
			currentAUPreset.presetNumber = -1;
			currentAUPreset.presetName = newPresetName;
			newPresetName = 0;
			SY_TRACE1(SY_TRACE_MISC, "Updated current preset to user preset named %s", programName);
			return true;
		} else {
			releaseCFRef((::CFTypeRef*)&newPresetName);
		}
	}
	catch (...) {
		releaseCFRef((::CFTypeRef*)&newPresetName);
		throw;
	}
	return false;
}

void SymbiosisComponent::getPropertyInfo(::AudioUnitPropertyID id, ::AudioUnitScope scope, ::AudioUnitElement element
		, bool* isReadable, bool* isWritable, int* minDataSize, int* normalDataSize) {
	switch (id) {
		case kAudioUnitProperty_ClassInfo:
			SY_TRACE2(SY_TRACE_FREQUENT, "AU GetPropertyInfo: kAudioUnitProperty_ClassInfo (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			if (scope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			(*isReadable) = true;
			(*isWritable) = true;
			(*minDataSize) = sizeof (::CFPropertyListRef);
			(*normalDataSize) = sizeof (::CFPropertyListRef);
			break;
		
		case kAudioUnitProperty_MakeConnection:
			SY_TRACE2(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_MakeConnection (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			if (scope != kAudioUnitScope_Input) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			if (static_cast<int>(element) < 0 || static_cast<int>(element) >= inputBusCount) {
				throw MacOSException(kAudioUnitErr_InvalidElement);
			}
			(*isReadable) = false;
			(*isWritable) = true;
			(*minDataSize) = sizeof (::AudioUnitConnection);
			(*normalDataSize) = sizeof (::AudioUnitConnection);
			break;

		case kAudioUnitProperty_SetRenderCallback:
			SY_TRACE2(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_SetRenderCallback (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			if (scope != kAudioUnitScope_Input) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			if (static_cast<int>(element) < 0 || static_cast<int>(element) >= inputBusCount) {
				throw MacOSException(kAudioUnitErr_InvalidElement);
			}
			(*isReadable) = false;
			(*isWritable) = true;
			(*minDataSize) = sizeof (::AURenderCallbackStruct);
			(*normalDataSize) = sizeof (::AURenderCallbackStruct);
			break;

		case kAudioUnitProperty_SampleRate:
		case kAudioUnitProperty_StreamFormat: {
			SY_TRACE3(SY_TRACE_AU, "AU GetPropertyInfo: %s (scope: %d, element: %d)"
					, (id == kAudioUnitProperty_SampleRate ? "kAudioUnitProperty_SampleRate"
					: "kAudioUnitProperty_StreamFormat"), static_cast<int>(scope), static_cast<int>(element));
			int busCount = 0;
			switch (scope) {
				case kAudioUnitScope_Input: busCount = inputBusCount; break;
				case kAudioUnitScope_Global:																			// There is a bug in MOTU DP which requires us to support the global scope here, cause it doesn't check the kAudioUnitErr_InvalidScope returned.
				case kAudioUnitScope_Output: busCount = outputBusCount; break;
				default: throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			if (static_cast<int>(element) < 0 || static_cast<int>(element) >= busCount) {
				throw MacOSException(kAudioUnitErr_InvalidElement);
			}
			(*isReadable) = true;
			(*isWritable) = (scope != kAudioUnitScope_Input || inputConnections[element].sourceAudioUnit == 0);
			(*minDataSize) = static_cast<int>(((id == kAudioUnitProperty_SampleRate)
					? sizeof (::Float64) : sizeof (::AudioStreamBasicDescription)));
			(*normalDataSize) = (*minDataSize);
			break;
		}
		
		case kAudioUnitProperty_ParameterList:
			SY_TRACE2(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_ParameterList (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			(*isReadable) = true;
			(*isWritable) = false;
			(*minDataSize) = 0;
			(*normalDataSize) = 0;
			if (scope == kAudioUnitScope_Global) {
				(*minDataSize) = static_cast<int>(sizeof (::AudioUnitParameterID) * parameterCount);
				(*normalDataSize) = static_cast<int>(sizeof (::AudioUnitParameterID) * parameterCount);
			}
			break;
		
		case kAudioUnitProperty_ParameterInfo:
			SY_TRACE2(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_ParameterInfo (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			if (scope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			if (static_cast<int>(element) < 0 || static_cast<int>(element) >= vst->getParameterCount()) {
				throw MacOSException(kAudioUnitErr_InvalidElement);
			}
			(*isReadable) = true;
			(*isWritable) = false;
			(*minDataSize) = sizeof (::AudioUnitParameterInfo);
			(*normalDataSize) = sizeof (::AudioUnitParameterInfo);
			break;
		
		case kAudioUnitProperty_ParameterValueStrings:
			SY_TRACE2(SY_TRACE_AU
					, "AU GetPropertyInfo: kAudioUnitProperty_ParameterValueStrings (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			if (scope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			if (static_cast<int>(element) < 0 || static_cast<int>(element) >= vst->getParameterCount()) {
				throw MacOSException(kAudioUnitErr_InvalidElement);
			}
			if (parameterValueStrings[element] == 0) {
				throw MacOSException(kAudioUnitErr_InvalidParameter);
			}
			(*isReadable) = true;
			(*isWritable) = false;
			(*minDataSize) = sizeof (::CFArrayRef);
			(*normalDataSize) = sizeof (::CFArrayRef);
			break;

		case kAudioUnitProperty_ElementCount:
			SY_TRACE2(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_ElementCount (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			(*isReadable) = true;
			(*isWritable) = false;
			(*minDataSize) = sizeof (::UInt32);
			(*normalDataSize) = sizeof (::UInt32);
			break;
		
		case kAudioUnitProperty_Latency:
			SY_TRACE2(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_Latency (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			if (scope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			(*isReadable) = true;
			(*isWritable) = false;
			(*minDataSize) = sizeof (::Float64);
			(*normalDataSize) = sizeof (::Float64);
			break;

		case kAudioUnitProperty_SupportedNumChannels:
			if (auChannelInfoCount == 0) {
				SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_SupportedNumChannels (not supported)");
				goto unsupported;
			} else {
				SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_SupportedNumChannels");
				if (scope != kAudioUnitScope_Global) {
					throw MacOSException(kAudioUnitErr_InvalidScope);
				}
				(*isReadable) = true;
				(*isWritable) = false;
				(*minDataSize) = static_cast<int>(auChannelInfoCount * sizeof (::AUChannelInfo));
				(*normalDataSize) = (*minDataSize);
			}
			break;
		
		case kAudioUnitProperty_MaximumFramesPerSlice:
			SY_TRACE2(SY_TRACE_AU
					, "AU GetPropertyInfo: kAudioUnitProperty_MaximumFramesPerSlice (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			if (scope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			(*isReadable) = true;
			(*isWritable) = true;
			(*minDataSize) = sizeof (::UInt32);
			(*normalDataSize) = sizeof (::UInt32);
			break;

		case kAudioUnitProperty_HostCallbacks:
			SY_TRACE2(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_HostCallbacks (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			if (scope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			(*isReadable) = true;
			(*isWritable) = true;
			(*minDataSize) = 0;																							// We support old obsolete formats with smaller struct sizes.
			(*normalDataSize) = sizeof (::HostCallbackInfo);
			break;
		
		case kAudioUnitProperty_LastRenderError:
			SY_TRACE2(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_LastRenderError (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			if (scope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			(*isReadable) = true;
			(*isWritable) = false;
			(*minDataSize) = sizeof (::OSStatus);
			(*normalDataSize) = sizeof (::OSStatus);
			break;

		case kAudioUnitProperty_FactoryPresets:
			SY_TRACE2(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_FactoryPresets (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			if (scope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			if (factoryPresetsArray == 0 || ::CFArrayGetCount(factoryPresetsArray) < 1) {
				throw MacOSException(kAudioUnitErr_InvalidProperty);													// Emperically it seems better to return an invalid property error if we have no factory presets
			}
			(*isReadable) = true;
			(*isWritable) = false;
			(*minDataSize) = sizeof (::CFArrayRef);
			(*normalDataSize) = sizeof (::CFArrayRef);
			break;

		case kAudioUnitProperty_ParameterStringFromValue:
			SY_TRACE2(SY_TRACE_FREQUENT
					, "AU GetPropertyInfo: kAudioUnitProperty_ParameterStringFromValue (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			if (scope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			if (static_cast<int>(element) < 0 || static_cast<int>(element) >= vst->getParameterCount()) {
				throw MacOSException(kAudioUnitErr_InvalidElement);
			}
			if (!vstGotSymbiosisExtensions) {							
				throw MacOSException(kAudioUnitErr_InvalidProperty);
			}
			(*isReadable) = true;
			(*isWritable) = false;
			(*minDataSize) = sizeof (::AudioUnitParameterStringFromValue);
			(*normalDataSize) = sizeof (::AudioUnitParameterStringFromValue);
			break;
		
		case kAudioUnitProperty_ParameterValueFromString:
			SY_TRACE2(SY_TRACE_AU
					, "AU GetPropertyInfo: kAudioUnitProperty_ParameterValueFromString (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			if (scope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			if (static_cast<int>(element) < 0 || static_cast<int>(element) >= vst->getParameterCount()) {
				throw MacOSException(kAudioUnitErr_InvalidElement);
			}
			if (!vstGotSymbiosisExtensions) {							
				throw MacOSException(kAudioUnitErr_InvalidProperty);
			}
			(*isReadable) = true;
			(*isWritable) = false;
			(*minDataSize) = sizeof (::AudioUnitParameterValueFromString);
			(*normalDataSize) = sizeof (::AudioUnitParameterValueFromString);
			break;
		
		case kAudioUnitProperty_CurrentPreset:																			// Even though kAudioUnitProperty_CurrentPreset is obsolete, some programs (like GarageBand v1.x) still uses it.
		case kAudioUnitProperty_PresentPreset:
			SY_TRACE3(SY_TRACE_AU, "AU GetPropertyInfo: %s (scope: %d, element: %d)"
					, ((id == kAudioUnitProperty_CurrentPreset) ? "kAudioUnitProperty_CurrentPreset"
					: "kAudioUnitProperty_PresentPreset"), static_cast<int>(scope), static_cast<int>(element));
			if (scope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			(*isReadable) = true;
			(*isWritable) = true;
			(*minDataSize) = sizeof (::SInt32);																			// Normal size is that of ::AUPreset, i.e. 8, but some programs (like Garage Band) only uses 4.
			(*normalDataSize) = sizeof (::AUPreset);
			break;

		case kAudioUnitProperty_ElementName:
			if (inputBusNames[0] == 0 && outputBusNames[0] == 0) {
				SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_ElementName (unsupported)");
				goto unsupported;
			} else {
				SY_TRACE2(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_ElementName (scope: %d, element: %d)"
						, static_cast<int>(scope), static_cast<int>(element));
				if (scope  != kAudioUnitScope_Input && scope != kAudioUnitScope_Output) {
					throw MacOSException(kAudioUnitErr_InvalidScope);
				}
				if (static_cast<int>(element) < 0
						|| static_cast<int>(element) >= (scope == kAudioUnitScope_Input
						? inputBusCount : outputBusCount)
						|| (scope == kAudioUnitScope_Input ? inputBusNames[element] : outputBusNames[element]) == 0) {
					throw MacOSException(kAudioUnitErr_InvalidElement);
				}
				(*isReadable) = true;
				(*isWritable) = false;
				(*minDataSize) = sizeof (::CFStringRef);
				(*normalDataSize) = sizeof (::CFStringRef);
			}
			break;

	#if (SY_USE_COCOA_GUI)
	
		case kAudioUnitProperty_CocoaUI:
			SY_TRACE2(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_CocoaUI (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			if (scope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
		#if (SY_INCLUDE_GUI_SUPPORT)
			if (!vst->hasEditor()) {
				SY_TRACE(SY_TRACE_AU, "VST has no editor");
				throw MacOSException(kAudioUnitErr_InvalidProperty);													// Emperically it seems better to return an invalid property error if we have no gui
			} else {
				(*isReadable) = true;
				(*isWritable) = false;
				(*minDataSize) = sizeof (::AudioUnitCocoaViewInfo);
				(*normalDataSize) = sizeof (::AudioUnitCocoaViewInfo);
			}
		#else
			throw MacOSException(kAudioUnitErr_InvalidProperty);														// Emperically it seems better to return an invalid property error if we have no gui
		#endif
			break;
			
	#elif (!SY_USE_COCOA_GUI)
	
		case kAudioUnitProperty_GetUIComponentList:
			SY_TRACE2(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_GetUIComponentList (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			if (scope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
		#if (SY_INCLUDE_GUI_SUPPORT)
			if (!vst->hasEditor()) {
				SY_TRACE(SY_TRACE_AU, "VST has no editor");
				throw MacOSException(kAudioUnitErr_InvalidProperty);													// Emperically it seems better to return an invalid property error if we have no gui
			} else {
				::ComponentDescription desc;
				throwOnOSError(::GetComponentInfo(reinterpret_cast< ::Component >(auComponentInstance), &desc, 0, 0
						, 0));
				desc.componentType = kAudioUnitCarbonViewComponentType;
				desc.componentFlags = 0;
				desc.componentFlagsMask = 0;						
				::Component uiComponent = ::FindNextComponent(0, &desc);
				if (uiComponent == 0) {
					SY_ASSERT0(0, "VST has editor, but the AU view component is missing!");
					throw MacOSException(kAudioUnitErr_InvalidProperty);
				}
				(*isReadable) = true;
				(*isWritable) = false;
				(*minDataSize) = sizeof (::ComponentDescription);
				(*normalDataSize) = sizeof (::ComponentDescription);
			}
		#else
			throw MacOSException(kAudioUnitErr_InvalidProperty);														// Emperically it seems better to return an invalid property error if we have no gui
		#endif
			break;
			
	#endif
		
		case kAudioUnitProperty_TailTime:
			SY_TRACE2(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_TailTime (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			if (scope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			if (!vstSupportsTail) {
				throw MacOSException(kAudioUnitErr_InvalidProperty); 
			} else {
				(*isReadable) = true;
				(*isWritable) = false;
				(*minDataSize) = sizeof (::Float64);
				(*normalDataSize) = sizeof (::Float64);
			}
			break;
		
		case kAudioUnitProperty_BypassEffect:
			SY_TRACE2(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_BypassEffect (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			if (scope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			if (!vstSupportsBypass) {
				throw MacOSException(kAudioUnitErr_InvalidProperty); 
			} else {
				(*isReadable) = true;
				(*isWritable) = true;
				(*minDataSize) = sizeof (::UInt32);
				(*normalDataSize) = sizeof (::UInt32);
			}
			break;

		case kMusicDeviceProperty_InstrumentCount:
			SY_TRACE2(SY_TRACE_AU, "AU GetPropertyInfo: kMusicDeviceProperty_InstrumentCount (scope: %d, element: %d)"
					, static_cast<int>(scope), static_cast<int>(element));
			if (scope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			(*isReadable) = true;
			(*isWritable) = false;
			(*minDataSize) = sizeof (::UInt32);
			(*normalDataSize) = sizeof (::UInt32);
			break;

		case kAudioUnitProperty_FastDispatch: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_FastDispatch (not supported)"); goto unsupported;
		case kAudioUnitProperty_CPULoad: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_CPULoad (not supported)"); goto unsupported;
		case kAudioUnitProperty_SRCAlgorithm: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_SRCAlgorithm (not supported)"); goto unsupported;
		case kAudioUnitProperty_ReverbRoomType: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_ReverbRoomType (not supported)"); goto unsupported;
		case kAudioUnitProperty_SetExternalBuffer: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_SetExternalBuffer (not supported)"); goto unsupported;
		case kAudioUnitProperty_MIDIControlMapping: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_MIDIControlMapping (not supported)"); goto unsupported;
		case kAudioUnitProperty_AudioChannelLayout: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_AudioChannelLayout (not supported)"); goto unsupported;
		case kAudioUnitProperty_ContextName: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_ContextName (not supported)"); goto unsupported;
		case kAudioUnitProperty_RenderQuality: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_RenderQuality (not supported)"); goto unsupported;
		case kAudioUnitProperty_SupportedChannelLayoutTags: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_SupportedChannelLayoutTags (not supported)"); goto unsupported;
		case kAudioUnitProperty_ParameterIDName: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_ParameterIDName (not supported)"); goto unsupported;
		case kAudioUnitProperty_ParameterClumpName: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_ParameterClumpName (not supported)"); goto unsupported;
		case kAudioUnitProperty_UsesInternalReverb: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_UsesInternalReverb (not supported)"); goto unsupported;
		case kAudioUnitProperty_OfflineRender: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_OfflineRender (not supported)"); goto unsupported;
		case kAudioUnitProperty_IconLocation: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_IconLocation (not supported)"); goto unsupported;
		case kAudioUnitProperty_PresentationLatency: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_PresentationLatency (not supported)"); goto unsupported;
		case kAudioUnitProperty_AllParameterMIDIMappings: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_AllParameterMIDIMappings (not supported)"); goto unsupported;
		case kAudioUnitProperty_AddParameterMIDIMapping: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_AddParameterMIDIMapping (not supported)"); goto unsupported;
		case kAudioUnitProperty_RemoveParameterMIDIMapping: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_RemoveParameterMIDIMapping (not supported)"); goto unsupported;
		case kAudioUnitProperty_HotMapParameterMIDIMapping: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_HotMapParameterMIDIMapping (not supported)"); goto unsupported;
		case /* kAudioUnitProperty_DependentParameters */ 45: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitProperty_DependentParameters (not supported)"); goto unsupported;
		case kMusicDeviceProperty_InstrumentName: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kMusicDeviceProperty_InstrumentName (not supported)"); goto unsupported;
		case kMusicDeviceProperty_GroupOutputBus: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kMusicDeviceProperty_GroupOutputBus (not supported)"); goto unsupported;
		case kMusicDeviceProperty_SoundBankFSSpec: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kMusicDeviceProperty_SoundBankFSSpec (not supported)"); goto unsupported;
		case kMusicDeviceProperty_InstrumentNumber: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kMusicDeviceProperty_InstrumentNumber (not supported)"); goto unsupported;
		case kMusicDeviceProperty_MIDIXMLNames: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kMusicDeviceProperty_MIDIXMLNames (not supported)"); goto unsupported;
		case kMusicDeviceProperty_BankName: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kMusicDeviceProperty_BankName (not supported)"); goto unsupported;
		case kMusicDeviceProperty_SoundBankData: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kMusicDeviceProperty_SoundBankData (not supported)"); goto unsupported;
		case kMusicDeviceProperty_PartGroup: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kMusicDeviceProperty_PartGroup (not supported)"); goto unsupported;
		case kMusicDeviceProperty_StreamFromDisk: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kMusicDeviceProperty_StreamFromDisk (not supported)"); goto unsupported;
		case kAudioUnitMigrateProperty_FromPlugin: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitMigrateProperty_FromPlugin (not supported)"); goto unsupported;
		case kAudioUnitMigrateProperty_OldAutomation: SY_TRACE(SY_TRACE_AU, "AU GetPropertyInfo: kAudioUnitMigrateProperty_OldAutomation (not supported)"); goto unsupported;
		default: SY_TRACE1(SY_TRACE_AU, "AU GetPropertyInfo: unknown property id: %d", static_cast<int>(id)); goto unsupported;
		unsupported: throw MacOSException(kAudioUnitErr_InvalidProperty);
	}
}

void SymbiosisComponent::updateVSTTimeInfo(const ::AudioTimeStamp* inTimeStamp) {
	vstTimeInfo.samplePos = inTimeStamp->mSampleTime;
	vstTimeInfo.sampleRate = streamFormat.mSampleRate;
	vstTimeInfo.flags = 0;
	if (hostCallbackInfo.beatAndTempoProc != 0) {
		::Float64 currentBeat = 0.0;
		::Float64 currentTempo = 120.0;
		::OSStatus status = (*hostCallbackInfo.beatAndTempoProc)(hostCallbackInfo.hostUserData, &currentBeat
				, &currentTempo);
		if (status == noErr) {
			vstTimeInfo.ppqPos = currentBeat;
			vstTimeInfo.tempo = currentTempo;
			vstTimeInfo.flags |= kVstPpqPosValid | kVstTempoValid;
		}
	}
	if (hostCallbackInfo.musicalTimeLocationProc != 0) {
		::UInt32 deltaSampleOffsetToNextBeat = 0;
		::Float32 timeSigNumerator = 4;
		::UInt32 timeSigDenominator = 4;
		::Float64 currentMeasureDownBeat = 0;
		::OSStatus status = (*hostCallbackInfo.musicalTimeLocationProc)(hostCallbackInfo.hostUserData
				, &deltaSampleOffsetToNextBeat, &timeSigNumerator, &timeSigDenominator, &currentMeasureDownBeat);
		if (status == noErr) {
			vstTimeInfo.timeSigNumerator = static_cast<int>(timeSigNumerator);
			vstTimeInfo.timeSigDenominator = timeSigDenominator;
			vstTimeInfo.barStartPos = currentMeasureDownBeat;
			vstTimeInfo.flags |= kVstBarsValid | kVstTimeSigValid;
		}
	}
	if (hostCallbackInfo.transportStateProc != 0) {
		::Boolean isPlaying;
		::Boolean transportStateChanged;
		::Float64 currentSampleInTimeLine;
		::Boolean isCycling;
		::Float64 cycleStartBeat;
		::Float64 cycleEndBeat;
		::OSStatus status = (*hostCallbackInfo.transportStateProc)(hostCallbackInfo.hostUserData, &isPlaying
				, &transportStateChanged, &currentSampleInTimeLine, &isCycling, &cycleStartBeat, &cycleEndBeat);
		if (status == noErr) {
			if (isPlaying) {
				vstTimeInfo.flags |= kVstTransportPlaying;
			}
			if (transportStateChanged) {
				vstTimeInfo.flags |= kVstTransportChanged;
			}
			vstTimeInfo.samplePos = currentSampleInTimeLine;															// Note: this one is closer to what a VST expects, i.e. the number of samples from song start, not the total number of samples processed so far.
			if (isCycling) {
				vstTimeInfo.flags |= kVstTransportCycleActive;
			}
			vstTimeInfo.cycleStartPos = cycleStartBeat;
			vstTimeInfo.cycleEndPos = cycleEndBeat;
			vstTimeInfo.flags |= kVstCyclePosValid;
		}
	}
}

bool SymbiosisComponent::collectInputAudio(int frameCount, float** inputPointers, const ::AudioTimeStamp* timeStamp) {
	bool inputIsSilent = true;
	 
	SymbiosisAudioBufferList bufferList;
	memset(&bufferList, 0, sizeof (bufferList));
	
	int ioChannelIndex = 0;
	for (int inputBusIndex = 0; inputBusIndex < inputBusCount; ++inputBusIndex) {
		int maxChannelCount = getMaxInputChannels(inputBusIndex);
		int activeChannelCount = getActiveInputChannels(inputBusIndex);
		bufferList.mNumberBuffers = activeChannelCount;
		for (int i = 0; i < activeChannelCount; ++i) {
			bufferList.mBuffers[i].mNumberChannels = 1;
			bufferList.mBuffers[i].mDataByteSize = frameCount * 4;
			bufferList.mBuffers[i].mData = ioBuffers[ioChannelIndex + i];
		}
		::AudioUnitRenderActionFlags inputFlags = 0;
		if (renderCallbacks[inputBusIndex].inputProc != 0) {
			throwOnOSError((*renderCallbacks[inputBusIndex].inputProc)(renderCallbacks[inputBusIndex].inputProcRefCon
					, &inputFlags, timeStamp, inputBusIndex, frameCount
					, reinterpret_cast< ::AudioBufferList* >(&bufferList)));
		} else if (inputConnections[inputBusIndex].sourceAudioUnit != 0) {			
			for (int i = 0; i < activeChannelCount; ++i) {
				bufferList.mBuffers[i].mData = 0;
			}
			throwOnOSError(::AudioUnitRender(inputConnections[inputBusIndex].sourceAudioUnit, &inputFlags, timeStamp
					, inputConnections[inputBusIndex].sourceOutputNumber, frameCount
					, reinterpret_cast< ::AudioBufferList* >(&bufferList)));
		} else {
			for (int i = 0; i < activeChannelCount; ++i) {
				memset(ioBuffers[ioChannelIndex + i], 0, sizeof (float) * frameCount);
			}
			inputFlags = kAudioUnitRenderAction_OutputIsSilence;
		}
		inputIsSilent = inputIsSilent && ((inputFlags & kAudioUnitRenderAction_OutputIsSilence) != 0);
		for (int i = 0; i < maxChannelCount; ++i) {
			inputPointers[ioChannelIndex + i]
					= reinterpret_cast<float*>(bufferList.mBuffers[i % activeChannelCount].mData);
		}
		ioChannelIndex += maxChannelCount;
	}
	SY_ASSERT(ioChannelIndex == vst->getInputCount());
	
#if (!defined(NDEBUG))
	if (inputIsSilent) {
		bool gotSignal = false;
		for (int i = 0; i < vst->getInputCount() && !gotSignal; ++i) {
			for (int j = 0; j < frameCount && !gotSignal; ++j) {
				gotSignal = (inputPointers[i][j] != 0.0);
			}
		}
		SY_ASSERT0(!gotSignal, "Input was flagged silent when signal was not (may be bug in signal source)");
	}
#endif
	
	return inputIsSilent;
}

void SymbiosisComponent::renderOutput(int frameCount, const float* const* inputPointers, float** outputPointers
		, bool inputIsSilent) {
	if (vstMidiEvents.numEvents > 0) {
		vst->processEvents(*reinterpret_cast<const VstEvents*>(&vstMidiEvents));
		vstMidiEvents.numEvents = 0;
	}
	if (vstGotSymbiosisExtensions) {
		vst->vendorSpecific('sI00', inputIsSilent ? 1 : 0, 0, 0);
	}
	vst->processReplacing(inputPointers, outputPointers, frameCount);
	if (vstGotSymbiosisExtensions) {
	#if (!defined(NDEBUG))
		bool reallyGotSignal = false;
		for (int i = 0; i < vst->getOutputCount() && !reallyGotSignal; ++i) {
			for (int j = 0; j < static_cast<int>(frameCount) && !reallyGotSignal; ++j) {
				reallyGotSignal = (outputPointers[i][j] != 0.0);
			}
		}
	#endif
		if (vst->vendorSpecific('sO00', 0, 0, 0)) {
			silentOutput = true;
			SY_ASSERT0(!reallyGotSignal
					, "SY vendor-specific callback 'sO00' returned true (output silent) when output was not silent");
		} else {
			silentOutput = false;
		#if (!defined(NDEBUG))
			if (!reallyGotSignal) {
				SY_TRACE(SY_TRACE_FREQUENT
						, "SY vendor-specific callback 'sO00' returned false (not silent) when output was silent");
			}
		#endif
		}
	} else {
		silentOutput = false;
	}
}

void SymbiosisComponent::render(::AudioUnitRenderActionFlags* ioActionFlags, const ::AudioTimeStamp* inTimeStamp
		, ::UInt32 inOutputBusNumber, ::UInt32 inNumberFrames, ::AudioBufferList* ioData) {
	SY_TRACE2(SY_TRACE_FREQUENT, "Rendering %u channels on bus %u", static_cast<unsigned int>(ioData->mNumberBuffers)
			, static_cast<unsigned int>(inOutputBusNumber));
	if (ioData == 0 || inTimeStamp == 0) {
		throw MacOSException(paramErr);
	}
	if (static_cast<int>(inOutputBusNumber) < 0 || static_cast<int>(inOutputBusNumber) >= outputBusCount) {
		SY_TRACE1(1, "AURender called for an invalid bus (%u)", static_cast<unsigned int>(inOutputBusNumber));
		throw MacOSException(paramErr);
	}
	if (inNumberFrames > static_cast< ::UInt32 >(maxFramesPerSlice)) {
		SY_TRACE2(1, "AURender called for an unexpected large number of frames (expected max %d, got %u)"
				, static_cast<int>(maxFramesPerSlice), static_cast<unsigned int>(inNumberFrames));
		throw MacOSException(paramErr);
	}
	SY_ASSERT2(static_cast<int>(ioData->mNumberBuffers) == getActiveOutputChannels(inOutputBusNumber)
			, "AURender called for an unexpected number of output channels (expected %d, got %u)"
			, static_cast<int>(getActiveOutputChannels(inOutputBusNumber))
			, static_cast<unsigned int>(ioData->mNumberBuffers));

	// --- Call pre-render notification callbacks

	::AudioUnitRenderActionFlags flags = 0;
	if (ioActionFlags != 0) {
		SY_ASSERT0(((*ioActionFlags) & (kAudioUnitRenderAction_PreRender | kAudioUnitRenderAction_PostRender)) == 0
				, "Invalid 'ioActionFlags' on call to AURender");
		flags = (*ioActionFlags);
	}
	flags |= kAudioUnitRenderAction_PreRender;
	for (int i = renderNotificationReceiversCount - 1; i >= 0; --i) {
		(*renderNotificationReceivers[i].inputProc)(renderNotificationReceivers[i].inputProcRefCon, &flags, inTimeStamp
				, inOutputBusNumber, inNumberFrames, ioData);
	}
	flags &= ~kAudioUnitRenderAction_PreRender;

	// --- Collect input (for effects) and render output.
	
	if (lastRenderSampleTime != inTimeStamp->mSampleTime) {																// If lastRenderSampleTime == inTimeStamp->mSampleTime, the host is (probably) requesting another output bus for the current "batch".
		lastRenderSampleTime = inTimeStamp->mSampleTime;
		updateVSTTimeInfo(inTimeStamp);
		float* inputPointers[kMaxChannels];
		float* outputPointers[kMaxChannels];
		bool inputIsSilent = collectInputAudio(inNumberFrames, inputPointers, inTimeStamp);
		int ioChannelIndex = 0;
		for (int outputBusIndex = 0; outputBusIndex < outputBusCount; ++outputBusIndex) {
			int maxChannelCount = getMaxOutputChannels(outputBusIndex);
			int activeChannelCount = getActiveOutputChannels(outputBusIndex);
			for (int i = 0; i < maxChannelCount; ++i) {
				outputPointers[ioChannelIndex + i] = ioBuffers[ioChannelIndex + i % activeChannelCount];
			}
			ioChannelIndex += maxChannelCount;
		}
		SY_ASSERT(ioChannelIndex == vst->getOutputCount());
		renderOutput(inNumberFrames, inputPointers, outputPointers, inputIsSilent);
	}

	if (silentOutput) {
		flags |= kAudioUnitRenderAction_OutputIsSilence;
	} else {
		flags &= ~kAudioUnitRenderAction_OutputIsSilence;
	}
	for (int i = 0; i < static_cast<int>(ioData->mNumberBuffers); ++i) {
		int ch = outputBusChannelNumbers[inOutputBusNumber] + i;
		SY_ASSERT(ioBuffers[ch] != 0);
		SY_ASSERT(ioData->mBuffers[i].mData == 0 || ioData->mBuffers[i].mDataByteSize == inNumberFrames * 4);
		if (ioData->mBuffers[i].mData == 0) {
			ioData->mBuffers[i].mData = ioBuffers[ch];
		} else {
			memcpy(ioData->mBuffers[i].mData, ioBuffers[ch], inNumberFrames * 4);
		}
	}

	// --- Call post-render notification callbacks

	flags |= kAudioUnitRenderAction_PostRender;
	for (int i = renderNotificationReceiversCount - 1; i >= 0; --i) {
		(*renderNotificationReceivers[i].inputProc)(renderNotificationReceivers[i].inputProcRefCon, &flags, inTimeStamp
				, inOutputBusNumber, inNumberFrames, ioData);
	}
	flags &= ~kAudioUnitRenderAction_PostRender;
	if (ioActionFlags != 0) {
		(*ioActionFlags) = flags;
	}
}

void SymbiosisComponent::getProperty(::UInt32* ioDataSize, void* outData, ::AudioUnitElement inElement
		, ::AudioUnitScope inScope, ::AudioUnitPropertyID inID) {					
	SY_ASSERT(ioDataSize != 0);
	int bufferSize = (*ioDataSize);
	bool isReadable = false;
	bool isWritable = false;
	int minDataSize = 0;
	int normalDataSize = 0;
	getPropertyInfo(inID, inScope, inElement, &isReadable, &isWritable, &minDataSize, &normalDataSize);
	if (!isReadable) {
		SY_TRACE1(SY_TRACE_MISC, "Cannot read property: %d", static_cast<int>(inID));
		throw MacOSException(kAudioUnitErr_InvalidProperty);
	}
	(*ioDataSize) = minDataSize;
	if (outData != 0) {
		if (bufferSize < minDataSize) {
			SY_TRACE2(SY_TRACE_MISC, "Trying to get a property with min size: %d with a buffer of size: %d", minDataSize
					, bufferSize);
			throw MacOSException(kAudioUnitErr_InvalidPropertyValue);
		}
	
		switch (inID) {
			default: SY_ASSERT(0); break;

			case kAudioUnitProperty_ClassInfo: {
				::CFMutableDictionaryRef& dictionaryRef = *reinterpret_cast< ::CFMutableDictionaryRef* >(outData);
				if (presetIsFXB) {
					dictionaryRef = createAUPresetOfCurrentBank(currentAUPreset.presetName);
				} else {
					dictionaryRef = createAUPresetOfCurrentProgram(currentAUPreset.presetName);
				}
				::SInt32 programNumber = vst->getCurrentProgram();
				addIntToDictionary(dictionaryRef, CFSTR("ProgramNumber"), programNumber);
				SY_ASSERT(::CFGetTypeID(dictionaryRef) == ::CFDictionaryGetTypeID());
				SY_ASSERT(::CFPropertyListIsValid(dictionaryRef, kCFPropertyListXMLFormat_v1_0));
				break;
			}

			case kAudioUnitProperty_SampleRate:
				SY_ASSERT(0 <= static_cast<int>(inElement)
						&& static_cast<int>(inElement) < ((inScope == kAudioUnitScope_Input)
						? inputBusCount : outputBusCount));
				*reinterpret_cast< ::Float64* >(outData) = streamFormat.mSampleRate;
				break;
			
			case kAudioUnitProperty_ParameterList:
				if (inScope == kAudioUnitScope_Global) {
					memcpy(outData, parameterList, sizeof (::AudioUnitParameterID) * parameterCount);
				}
				break;
			
			case kAudioUnitProperty_ParameterInfo:
				SY_ASSERT(0 <= static_cast<int>(inElement) && static_cast<int>(inElement) < vst->getParameterCount());
				*reinterpret_cast< ::AudioUnitParameterInfo* >(outData) = parameterInfos[inElement];
				break;

			case kAudioUnitProperty_ParameterValueStrings:
				SY_ASSERT(0 <= static_cast<int>(inElement) && static_cast<int>(inElement) < vst->getParameterCount());
				SY_ASSERT(parameterValueStrings[inElement] != 0);
				*reinterpret_cast< ::CFArrayRef* >(outData) = parameterValueStrings[inElement];
				::CFRetain(parameterValueStrings[inElement]);
				break;

			case kAudioUnitProperty_StreamFormat:
				SY_ASSERT(0 <= static_cast<int>(inElement)
						&& static_cast<int>(inElement) < ((inScope == kAudioUnitScope_Input)
						? inputBusCount : outputBusCount));
				streamFormat.mChannelsPerFrame = ((inScope == kAudioUnitScope_Input)
						? getActiveInputChannels(inElement) : getActiveOutputChannels(inElement));
				*reinterpret_cast< ::AudioStreamBasicDescription* >(outData) = streamFormat;
				break;
			
			case kAudioUnitProperty_ElementCount: {
				int busCount = 0;
				switch (inScope) {
					case kAudioUnitScope_Input: busCount = inputBusCount; break;
					case kAudioUnitScope_Output: busCount = outputBusCount; break;
					default: busCount = 0; break;
				}
				*reinterpret_cast< ::UInt32* >(outData) = busCount;
				break;
			}
			
			case kAudioUnitProperty_Latency:
				updateInitialDelayTime();
				*reinterpret_cast< ::Float64* >(outData) = initialDelayTime;
				break;
			
			case kAudioUnitProperty_SupportedNumChannels: {
				SY_ASSERT(auChannelInfoCount > 0);
				::AUChannelInfo* cp = reinterpret_cast< ::AUChannelInfo* >(outData);
				memcpy(cp, auChannelInfos, auChannelInfoCount * sizeof (::AUChannelInfo));
				break;
			}

			case kAudioUnitProperty_MaximumFramesPerSlice:
				*reinterpret_cast< ::UInt32* >(outData) = maxFramesPerSlice;
				break;

			case kAudioUnitProperty_HostCallbacks:
				(*ioDataSize) = static_cast<int>((bufferSize >= static_cast<int>(sizeof (hostCallbackInfo))
						? sizeof (hostCallbackInfo) : bufferSize));
				memcpy(outData, &hostCallbackInfo, (*ioDataSize));
				break;

			case kAudioUnitProperty_LastRenderError: *reinterpret_cast< ::OSStatus* >(outData) = noErr; break;

			case kAudioUnitProperty_FactoryPresets:
				SY_ASSERT(factoryPresetsArray != 0);
				::CFRetain(factoryPresetsArray);
				*reinterpret_cast< ::CFArrayRef* >(outData) = factoryPresetsArray;
				break;
		
		#if (SY_USE_COCOA_GUI)

			case kAudioUnitProperty_CocoaUI: {
			#if (SY_INCLUDE_GUI_SUPPORT)
				AudioUnitCocoaViewInfo cocoaInfo;
				// This is important. Since the class name will be the same for all Symbiosis wrapped plug-ins there
				// will be Objective-C name collisions. Instead of trying to avoid that, we accept it as long as we
				// are using the same binary version of the class implementation (hence the date in the class name).
				// However, we need to locate the bundle that has loaded the currently active class object instance
				// for Symbiosis20010220_CocoaViewFactory, i.e. the first loaded and opened Symbiosis bundle. Otherwise
				// there will be a failure when the host tries to retrieve the class from the new bundle (because of a
				// collision).
				
				// I don't know why, but using objc_getClass is required for this to work. Following line doesn't work.
				// Class factoryClass = [Symbiosis20010220_CocoaViewFactory class];
				Class factoryClass = objc_getClass("Symbiosis20010220_CocoaViewFactory");
				SY_ASSERT(factoryClass != nil);
				NSBundle* symbiosisBundle = [NSBundle bundleForClass:factoryClass];
				NSString* bundlePath = [symbiosisBundle bundlePath];
				cocoaInfo.mCocoaAUViewBundleLocation = (CFURLRef)[[NSURL fileURLWithPath:bundlePath] retain];
				SY_ASSERT(cocoaInfo.mCocoaAUViewBundleLocation != nil);
				cocoaInfo.mCocoaAUViewClass[0]
						= ::CFStringCreateWithCString(NULL, "Symbiosis20010220_CocoaViewFactory", kCFStringEncodingUTF8);
				*((AudioUnitCocoaViewInfo *)outData) = cocoaInfo;
			#else
				throw MacOSException(kAudioUnitErr_InvalidProperty);													// Emperically it seems better to return an invalid property error if we have no gui
			#endif
				break;
			}
			
		#elif (!SY_USE_COCOA_GUI)
		
			case kAudioUnitProperty_GetUIComponentList: {
			#if (SY_INCLUDE_GUI_SUPPORT)
				::ComponentDescription* cd = reinterpret_cast< ::ComponentDescription* >(outData);
				throwOnOSError(::GetComponentInfo(reinterpret_cast< ::Component >(auComponentInstance), cd, 0, 0, 0));
				cd->componentType = kAudioUnitCarbonViewComponentType;
				cd->componentFlags = 0;
				cd->componentFlagsMask = 0;
			#else
				throw MacOSException(kAudioUnitErr_InvalidProperty);													// Emperically it seems better to return an invalid property error if we have no gui
			#endif
				break;
			}
			
		#endif

			case kAudioUnitProperty_TailTime:
				updateTailTime();
				*reinterpret_cast< ::Float64* >(outData) = tailTime;
				break;

			case kAudioUnitProperty_BypassEffect:
				*reinterpret_cast< ::UInt32* >(outData) = (isBypassing ? 1 : 0);
				break;

			case kAudioUnitProperty_ParameterStringFromValue: {
				::AudioUnitParameterStringFromValue* sfv = reinterpret_cast< ::AudioUnitParameterStringFromValue* >
						(outData);
				if (static_cast<int>(sfv->inParamID) < 0 || static_cast<int>(sfv->inParamID)
						>= vst->getParameterCount()) {
					throw MacOSException(kAudioUnitErr_InvalidParameter);
				}
				sfv->outString = 0;
				
				char buffer[24 + 1] = "?";																				// The VST spec says 8 characters max, but many VSTs don't care about that, so I say 24. :-)
				if (sfv->inValue == 0) {
					vst->getParameterDisplay(sfv->inParamID, buffer);
				} else {
					SY_ASSERT(vstGotSymbiosisExtensions);
					*reinterpret_cast<float*>(buffer) = scaleFromAUParameter(sfv->inParamID, (*sfv->inValue));
					VstIntPtr vendorSpecificReturn = vst->vendorSpecific('sV2S', sfv->inParamID, buffer, 0);
					if (vendorSpecificReturn == 0) {
						SY_TRACE(1, "Warning! Symbiosis extension 'sV2S' (value to string conversion) returned 0");
						throw MacOSException(kAudioUnitErr_InvalidProperty);
					}
				}
				sfv->outString = ::CFStringCreateWithCString(0, eatSpace(buffer), kCFStringEncodingMacRoman);			// Many VSTs return spaces in front of the display value, we drop these, makes no sense on Mac
				SY_ASSERT(sfv->outString != 0);
				break;
			}
			
			case kAudioUnitProperty_ParameterValueFromString: {
				::AudioUnitParameterValueFromString* vfs = reinterpret_cast< ::AudioUnitParameterValueFromString* >
						(outData);
				if (static_cast<int>(vfs->inParamID) < 0 || static_cast<int>(vfs->inParamID)
						>= vst->getParameterCount()) {
					throw MacOSException(kAudioUnitErr_InvalidParameter);
				}
				vfs->outValue = 0.0f;
				
				SY_ASSERT(vstGotSymbiosisExtensions);
				char buffer[2047 + 1];
				::Boolean wasOK = ::CFStringGetCString(vfs->inString, buffer, 2048, kCFStringEncodingMacRoman);
				SY_ASSERT(wasOK);
				SY_TRACE2(SY_TRACE_MISC, "Trying to convert '%s' for parameter %d", buffer
						, static_cast<int>(vfs->inParamID));
				VstIntPtr vendorSpecificReturn = vst->vendorSpecific('sS2V', vfs->inParamID, buffer, 0);
				if (vendorSpecificReturn == 0) {
					SY_TRACE(1, "Warning! Symbiosis extension 'sS2V' (string to value conversion) returned 0");
					throw MacOSException(kAudioUnitErr_InvalidProperty);
				}
				vfs->outValue = scaleToAUParameter(vfs->inParamID, *reinterpret_cast<float*>(buffer));
				break;
			}

			case kAudioUnitProperty_CurrentPreset:
			case kAudioUnitProperty_PresentPreset: {
				updateCurrentAUPreset();
				if (bufferSize >= static_cast<int>(sizeof (::AUPreset))) {
					*reinterpret_cast< ::AUPreset* >(outData) = currentAUPreset;
					if (inID == kAudioUnitProperty_PresentPreset) {
						SY_ASSERT(currentAUPreset.presetName != 0);
						::CFRetain(currentAUPreset.presetName);
					}
					(*ioDataSize) = sizeof (::AUPreset);
				} else {
					SY_ASSERT(bufferSize == static_cast<int>(sizeof (::SInt32)));
					*reinterpret_cast< ::SInt32* >(outData) = currentAUPreset.presetNumber;
					(*ioDataSize) = sizeof (::SInt32);
				}
				break;
			}

			case kAudioUnitProperty_ElementName: {
				SY_ASSERT(inScope == kAudioUnitScope_Input || inScope == kAudioUnitScope_Output);
				SY_ASSERT(0 <= static_cast<int>(inElement)
						&& static_cast<int>(inElement) < (inScope == kAudioUnitScope_Input
						? inputBusCount : outputBusCount));
				::CFStringRef s = ((inScope == kAudioUnitScope_Input)
						? inputBusNames[inElement] : outputBusNames[inElement]);
				SY_ASSERT(s != 0);
				::CFRetain(s);
				*reinterpret_cast< ::CFStringRef* >(outData) = s;
				break;
			}

			case kMusicDeviceProperty_InstrumentCount: *reinterpret_cast< ::UInt32* >(outData) = 0; break;
		}
	}
}

bool SymbiosisComponent::updateInitialDelayTime() {
	int delaySamples = vst->getInitialDelay();
	double newInitialDelayTime = delaySamples / static_cast<double>(streamFormat.mSampleRate);
	if (initialDelayTime != newInitialDelayTime) {
		initialDelayTime = newInitialDelayTime;
		return true;
	} else {
		return false;
	}
}

bool SymbiosisComponent::updateTailTime() {
	if (vstSupportsTail) {
		int tailSamples = vst->getTailSize();
		double newTailTime = tailSamples / static_cast<double>(streamFormat.mSampleRate);
		if (tailTime != newTailTime) {
			tailTime = newTailTime;
			return true;
		}
	}
	return false;
}

void SymbiosisComponent::updateInitialDelayAndTailTimes() {
	if (updateInitialDelayTime()) {
		propertyChanged(kAudioUnitProperty_Latency, kAudioUnitScope_Global, 0);
	}
	if (updateTailTime()) {
		propertyChanged(kAudioUnitProperty_TailTime, kAudioUnitScope_Global, 0);
	}
}

bool SymbiosisComponent::updateSampleRate(::Float64 newSampleRate) {
	if (newSampleRate != streamFormat.mSampleRate) {
		streamFormat.mSampleRate = newSampleRate;
		vst->setSampleRate(static_cast<float>(streamFormat.mSampleRate));
		for (int i = 0; i < inputBusCount; ++i) {
			propertyChanged(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, i);
			propertyChanged(kAudioUnitProperty_SampleRate, kAudioUnitScope_Input, i);
		}
		for (int i = 0; i < outputBusCount; ++i) {
			propertyChanged(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, i);
			propertyChanged(kAudioUnitProperty_SampleRate, kAudioUnitScope_Output, i);
		}
		updateInitialDelayAndTailTimes();
		return true;
	} else {
		return false;
	}
}

void SymbiosisComponent::updateMaxFramesPerSlice(int newFramesPerSlice) {
	if (maxFramesPerSlice != newFramesPerSlice) {
		maxFramesPerSlice = newFramesPerSlice;
		reallocateIOBuffers();
		propertyChanged(kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0);
		vst->setBlockSize(maxFramesPerSlice);
	}
}

void SymbiosisComponent::updateFormat(::AudioUnitScope scope, int busNumber
		, const ::AudioStreamBasicDescription& format) {
	SY_TRACE3(SY_TRACE_MISC, "Trying to set %s format on bus %d to %u channels"
			, (scope == kAudioUnitScope_Input) ? "input" : "output", static_cast<int>(busNumber)
			, static_cast<unsigned int>(format.mChannelsPerFrame));
	int maxChannelCount = ((scope == kAudioUnitScope_Input)
			? getMaxInputChannels(busNumber) : getMaxOutputChannels(busNumber));
	if (format.mFormatID != kAudioFormatLinearPCM
			|| format.mFramesPerPacket != 1
			|| format.mBytesPerPacket != format.mBytesPerFrame
			|| (format.mFormatFlags & (kLinearPCMFormatFlagIsFloat | kBigEndianPCMFlag
					| kAudioFormatFlagIsNonInterleaved)) != (kLinearPCMFormatFlagIsFloat | kBigEndianPCMFlag
					| kAudioFormatFlagIsNonInterleaved)
			|| format.mBitsPerChannel != 32
			|| format.mBytesPerFrame != 4
			|| format.mChannelsPerFrame == 0) {
		throw MacOSException(kAudioUnitErr_FormatNotSupported);
	}
	if (static_cast<int>(format.mChannelsPerFrame) != maxChannelCount && !(format.mChannelsPerFrame == 1 &&
			maxChannelCount == 2 && canDoMonoIO)) {
		/*
			Logic 8 has a bug that tries to set the format of mono outputs to stereo when instantiating as a
			stereo-only instrument. We accept this (for now) and just swallow the error. Logic will not try to render
			on these outputs anyhow, so no other action seems necessary.
		*/
		if ((hostApplication == logic8_0 || hostApplication == olderGarageBand) && maxChannelCount == 1
				&& format.mChannelsPerFrame == 2) {
			SY_TRACE1(SY_TRACE_MISC
					, "%s is incorrectly trying to set the format on a mono bus to stereo (accepting this for now)."
					, ((hostApplication == logic8_0) ? "Logic 8" : "GarageBand"));
		} else {
			SY_TRACE1(SY_TRACE_MISC, "Expecting 1 to %d channels", maxChannelCount);
			throw MacOSException(kAudioUnitErr_FormatNotSupported);
		}
	}
	if (scope == kAudioUnitScope_Input) {
		inputBusChannelCounts[busNumber] = format.mChannelsPerFrame;
	} else {
		outputBusChannelCounts[busNumber] = format.mChannelsPerFrame;
	}
	updateSampleRate(format.mSampleRate);
}

void SymbiosisComponent::setProperty(::UInt32 inDataSize, const void* inData, ::AudioUnitElement inElement
		, ::AudioUnitScope inScope, ::AudioUnitPropertyID inID) {
	bool readable = false;
	bool writable = false;
	int minDataSize = 0;
	int normalDataSize = 0;
	getPropertyInfo(inID, inScope, inElement, &readable, &writable, &minDataSize, &normalDataSize);
	if (!writable) {
		SY_TRACE1(SY_TRACE_MISC, "Cannot write property: %d", static_cast<int>(inID));
		throw MacOSException(kAudioUnitErr_InvalidProperty);
	}
	if (static_cast<int>(inDataSize) < minDataSize) {
		SY_TRACE2(SY_TRACE_MISC, "Trying to set a property with min size: %d with a value of size: %d", minDataSize
				, static_cast<int>(inDataSize));
		throw MacOSException(kAudioUnitErr_InvalidPropertyValue);
	}
	
	switch (inID) {
		default: SY_ASSERT(0); break;

		case kAudioUnitProperty_ClassInfo: {
			try {
				::CFDictionaryRef dictionary = *reinterpret_cast< const ::CFDictionaryRef* >(inData);
				if (dictionary == 0 || ::CFGetTypeID(dictionary) != ::CFDictionaryGetTypeID()) {
					throw FormatException("Invalid AUPreset format");
				}
				
				::ComponentDescription desc;
				throwOnOSError(::GetComponentInfo(reinterpret_cast< ::Component >(auComponentInstance), &desc, 0, 0
						, 0));
				checkIntInDictionary(dictionary, CFSTR(kAUPresetVersionKey), 1);
				checkIntInDictionary(dictionary, CFSTR(kAUPresetTypeKey), desc.componentType);
				checkIntInDictionary(dictionary, CFSTR(kAUPresetSubtypeKey), desc.componentSubType);
				checkIntInDictionary(dictionary, CFSTR(kAUPresetManufacturerKey), desc.componentManufacturer);
				
				{
					::SInt32 useProgramNumber = 0;
					::CFNumberRef numberRef = reinterpret_cast< ::CFNumberRef >(::CFDictionaryGetValue(dictionary
							, CFSTR("ProgramNumber")));
					if (numberRef != 0) {
						if (::CFGetTypeID(numberRef) != ::CFNumberGetTypeID()) {
							throw FormatException("Value in dictionary is not of expected type");
						}
						::SInt32 programNumber;
						::CFNumberGetValue(numberRef, kCFNumberSInt32Type, &programNumber);
						SY_TRACE1(SY_TRACE_MISC, "Requested program number: %d", static_cast<int>(programNumber));
						if (0 <= programNumber && programNumber < vst->getProgramCount()) {
							useProgramNumber = programNumber;
						}
					}
					vst->setCurrentProgram(useProgramNumber);
				}
				::CFStringRef nameRef = reinterpret_cast< ::CFStringRef >(getValueOfKeyInDictionary(dictionary
						, CFSTR(kAUPresetNameKey), ::CFStringGetTypeID()));
				::CFDataRef dataRef = reinterpret_cast< ::CFDataRef >(getValueOfKeyInDictionary(dictionary
						, CFSTR(kAUPresetVSTDataKey), ::CFDataGetTypeID()));
				SY_ASSERT(dataRef != 0);
				SY_ASSERT(::CFGetTypeID(dataRef) == ::CFDataGetTypeID());
				bool loadedPerfectly = vst->loadFXPOrFXB(::CFDataGetLength(dataRef), ::CFDataGetBytePtr(dataRef));
				if (!loadedPerfectly) {
					SY_TRACE(SY_TRACE_MISC, "Warning, FXP / FXB may not have loaded perfectly");
				}
				
				if (updateNameOnLoad) {
					updateCurrentVSTProgramName(nameRef);
				}
				updateCurrentAUPreset();
				currentAUPreset.presetNumber = -1;
				propertyChanged(kAudioUnitProperty_CurrentPreset, kAudioUnitScope_Global, 0);
				propertyChanged(kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0);
			}
			catch (const EOFException& x) {
				SY_TRACE1(SY_TRACE_EXCEPTIONS, "Failed reading AUPreset, caught end of file exception: %s", x.what());
				throw MacOSException(kAudioUnitErr_InvalidPropertyValue);
			}
			catch (const FormatException& x) {
				SY_TRACE1(SY_TRACE_EXCEPTIONS, "Failed reading AUPreset, caught format exception: %s", x.what());
				throw MacOSException(kAudioUnitErr_InvalidPropertyValue);
			}
			break;
		}

		case kAudioUnitProperty_MakeConnection: {
			const ::AudioUnitConnection* connection = reinterpret_cast< const ::AudioUnitConnection* >(inData);
			if (connection->destInputNumber != inElement) {
				throw MacOSException(kAudioUnitErr_InvalidPropertyValue);
			}
			if (connection->sourceAudioUnit != 0) {
				::AudioStreamBasicDescription format;
				::UInt32 size = sizeof (::AudioStreamBasicDescription);
				throwOnOSError(::AudioUnitGetProperty(connection->sourceAudioUnit, kAudioUnitProperty_StreamFormat
						, kAudioUnitScope_Output, connection->sourceOutputNumber, &format, &size));
				updateFormat(kAudioUnitScope_Input, inElement, format);
			}
			bool changedConnection = false;
			bool changedRenderCallback = false;
			SY_ASSERT(0 <= static_cast<int>(inElement) && static_cast<int>(inElement) < inputBusCount);
			if (inputConnections[inElement].sourceAudioUnit != connection->sourceAudioUnit
					|| inputConnections[inElement].sourceOutputNumber != connection->sourceOutputNumber) {
				inputConnections[inElement] = *connection;
				changedConnection = true;
			}
			if (renderCallbacks[inElement].inputProc != 0) {
				renderCallbacks[inElement].inputProc = 0;
				renderCallbacks[inElement].inputProcRefCon = 0;
				changedRenderCallback = true;
			}
			if (changedConnection) {
				propertyChanged(kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, inElement);
			}
			if (changedRenderCallback) {
				propertyChanged(kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, inElement);
			}
			break;
		}
			
		case kAudioUnitProperty_SetRenderCallback: {
			const ::AURenderCallbackStruct* callback = reinterpret_cast< const ::AURenderCallbackStruct* >(inData);
			bool changedConnection = false;
			bool changedRenderCallback = false;
			SY_ASSERT(0 <= static_cast<int>(inElement) && static_cast<int>(inElement) < inputBusCount);
			if (renderCallbacks[inElement].inputProc != callback->inputProc
					|| renderCallbacks[inElement].inputProcRefCon != callback->inputProcRefCon) {
				renderCallbacks[inElement] = *callback;
				changedRenderCallback = true;
			}
			if (inputConnections[inElement].sourceAudioUnit != 0) {
				inputConnections[inElement].sourceAudioUnit = 0;
				inputConnections[inElement].sourceOutputNumber = 0;
				changedConnection = true;
			}
			if (changedConnection) {
				propertyChanged(kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, inElement);
			}
			if (changedRenderCallback) {
				propertyChanged(kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, inElement);
			}
			break;
		}

		case kAudioUnitProperty_StreamFormat:
			updateFormat(inScope, inElement, *reinterpret_cast< const ::AudioStreamBasicDescription* >(inData));
			break;
		
		case kAudioUnitProperty_SampleRate:
			updateSampleRate(*reinterpret_cast< const ::Float64* >(inData));
			break;

		case kAudioUnitProperty_MaximumFramesPerSlice:
			updateMaxFramesPerSlice(*reinterpret_cast< const ::SInt32* >(inData));
			break;

		case kAudioUnitProperty_HostCallbacks: {
			::HostCallbackInfo info;
			memset(&info, 0, sizeof (info));
			memcpy(&info, inData, (inDataSize > sizeof (info)) ? sizeof (info) : inDataSize);
			if (memcmp(&hostCallbackInfo, &info, sizeof (hostCallbackInfo)) != 0) {
				hostCallbackInfo = info;
				propertyChanged(kAudioUnitProperty_HostCallbacks, kAudioUnitScope_Global, 0);
			}
			break;
		}

		case kAudioUnitProperty_CurrentPreset:
		case kAudioUnitProperty_PresentPreset: {
			::AUPreset requestedPreset;
			memset(&requestedPreset, 0, sizeof (::AUPreset));
			if (inDataSize >= sizeof (::AUPreset)) {
				requestedPreset = *reinterpret_cast< const ::AUPreset* >(inData);
			} else {
				SY_ASSERT(inDataSize == sizeof (::SInt32));
				requestedPreset.presetNumber = *reinterpret_cast< const ::SInt32* >(inData);
			}
			if (requestedPreset.presetNumber < 0) {
				if (requestedPreset.presetName != 0) {
					updateCurrentVSTProgramName(requestedPreset.presetName);
				}
				if (updateCurrentAUPreset() || currentAUPreset.presetNumber != -1) {
					currentAUPreset.presetNumber = -1;
					propertyChanged(kAudioUnitProperty_CurrentPreset, kAudioUnitScope_Global, 0);
					propertyChanged(kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0);
				}
			} else {
				if (factoryPresetsArray == 0 || requestedPreset.presetNumber
						>= ::CFArrayGetCount(factoryPresetsArray)) {
					throw MacOSException(kAudioUnitErr_InvalidPropertyValue);
				} else {
					::CFDataRef dataRef = factoryPresetData[requestedPreset.presetNumber];
					SY_ASSERT(dataRef != 0);
					SY_ASSERT(::CFGetTypeID(dataRef) == ::CFDataGetTypeID());
					bool loadedPerfectly = vst->loadFXPOrFXB(::CFDataGetLength(dataRef), ::CFDataGetBytePtr(dataRef));
					if (!loadedPerfectly) {
						SY_TRACE(SY_TRACE_MISC, "Warning, FXP / FXB may not have loaded perfectly");
					}
					::CFRetain(factoryPresets[requestedPreset.presetNumber].presetName);
					releaseCFRef((::CFTypeRef*)&currentAUPreset.presetName);
					currentAUPreset = factoryPresets[requestedPreset.presetNumber];
					propertyChanged(kAudioUnitProperty_CurrentPreset, kAudioUnitScope_Global, 0);
					propertyChanged(kAudioUnitProperty_PresentPreset, kAudioUnitScope_Global, 0);
				}
			}
			break;
		}

		case kAudioUnitProperty_BypassEffect: {
			isBypassing = (*reinterpret_cast< const ::UInt32* >(inData) != 0);
			SY_TRACE1(SY_TRACE_AU, "AU Bypassing %s", (isBypassing ? "on" : "off"));
			bool success = vst->setBypass(isBypassing);
			SY_ASSERT0(success, "Could not set or reset VST bypass state");
			break;
		}
	}
}

void SymbiosisComponent::dispatch(::ComponentParameters* params) {
	switch (params->what) {
		case kAudioUnitInitializeSelect:
			SY_TRACE(SY_TRACE_AU, "AU kAudioUnitInitializeSelect");
			if (!vst->isResumed()) {
				vst->resume();
				updateInitialDelayAndTailTimes();
			}
			break;
		
		case kAudioUnitUninitializeSelect:
			SY_TRACE(SY_TRACE_AU, "AU kAudioUnitUninitializeSelect");
			if (vst->isResumed()) {
				vst->suspend();
			}
			break;
		
		case kAudioUnitGetPropertyInfoSelect: {
			SY_TRACE(SY_TRACE_FREQUENT, "AU kAudioUnitGetPropertyInfoSelect");

			PARAM(AudioUnitPropertyID, pinID, 0, 5);
			PARAM(AudioUnitScope, pinScope, 1, 5);
			PARAM(AudioUnitElement, pinElement, 2, 5);
			PARAM(UInt32 *, poutDataSize, 3, 5);
			PARAM(Boolean *, poutWritable, 4, 5);

			if (poutDataSize != 0) {
				(*poutDataSize) = 0;
			}
			if (poutWritable != 0) {
				(*poutWritable) = false;
			}
			bool readable = false;
			bool writable = false;
			int minDataSize = 0;
			int normalDataSize = 0;
			getPropertyInfo(pinID, pinScope, pinElement, &readable, &writable, &minDataSize, &normalDataSize);
			if (poutDataSize != 0) {
				(*poutDataSize) = normalDataSize;
			}
			if (poutWritable != 0) {
				(*poutWritable) = writable;
			}
			break;
		}
		
		case kAudioUnitGetPropertySelect: {
			SY_TRACE(SY_TRACE_FREQUENT, "AU kAudioUnitGetPropertySelect");

			PARAM(AudioUnitPropertyID, pinID, 0, 5);
			PARAM(AudioUnitScope, pinScope, 1, 5);
			PARAM(AudioUnitElement, pinElement, 2, 5);
			PARAM(void *, poutData, 3, 5);
			PARAM(UInt32 *, pioDataSize, 4, 5);

			getProperty(pioDataSize, poutData, pinElement, pinScope, pinID);
			break;
		}
		
		case kAudioUnitSetPropertySelect: {
			SY_TRACE(SY_TRACE_FREQUENT, "AU kAudioUnitSetPropertySelect");

			PARAM(AudioUnitPropertyID, pinID, 0, 5);
			PARAM(AudioUnitScope, pinScope, 1, 5);
			PARAM(AudioUnitElement, pinElement, 2, 5);
			PARAM(const void *, pinData, 3, 5);
			PARAM(UInt32, pinDataSize, 4, 5);

			setProperty(pinDataSize, pinData, pinElement, pinScope, pinID);
			break;
		}
		
		case kAudioUnitAddPropertyListenerSelect: {
			SY_TRACE(SY_TRACE_AU, "AU kAudioUnitAddPropertyListenerSelect");

			PARAM(AudioUnitPropertyID, pinID, 0, 3);
			PARAM(AudioUnitPropertyListenerProc, pinProc, 1, 3);
			PARAM(void *, pinProcRefCon, 2, 3);
		
			if (propertyListenersCount >= kMaxPropertyListeners) {
				throw MacOSException(memFullErr);
			}
			AUPropertyListener listener;
			memset(&listener, 0, sizeof (listener));
			listener.fPropertyID = pinID;
			listener.fListenerProc = pinProc;
			listener.fListenerRefCon = pinProcRefCon;
			propertyListeners[propertyListenersCount] = listener;
			++propertyListenersCount;
			SY_TRACE3(SY_TRACE_AU, "AU Added listener %p (refcon: %p) on property: %d", pinProc, pinProcRefCon
					, static_cast<int>(pinID));
			break;
		}
		
	#if (!__LP64__)
		case kAudioUnitRemovePropertyListenerSelect: {
			SY_TRACE(SY_TRACE_AU, "AU kAudioUnitRemovePropertyListenerSelect");

			PARAM(AudioUnitPropertyID, pinID, 0, 2);
			PARAM(AudioUnitPropertyListenerProc, pinProc, 1, 2);
		
			int i = 0;
			int j = 0;
			while (i < propertyListenersCount) {
				if (propertyListeners[i].fPropertyID != pinID || propertyListeners[i].fListenerProc != pinProc) {
					propertyListeners[j] = propertyListeners[i];
					++j;
				} else {
					SY_TRACE1(SY_TRACE_AU, "AU Removed listener on %d", static_cast<int>(pinID));
				}
				++i;
			}
			propertyListenersCount = j;
			break;
		}
	#endif

	#if (__MAC_OS_X_VERSION_MAX_ALLOWED >= 1050)
		case kAudioUnitRemovePropertyListenerWithUserDataSelect: {
			SY_TRACE(SY_TRACE_AU, "AU kAudioUnitRemovePropertyListenerWithUserDataSelect");

			PARAM(AudioUnitPropertyID, pinID, 0, 3);
			PARAM(AudioUnitPropertyListenerProc, pinProc, 1, 3);
			PARAM(void *, pinProcRefCon, 2, 3);
		
			int i = 0;
			int j = 0;
			while (i < propertyListenersCount) {
				if (propertyListeners[i].fPropertyID != pinID || propertyListeners[i].fListenerProc != pinProc
						|| propertyListeners[i].fListenerRefCon != pinProcRefCon) {
					propertyListeners[j] = propertyListeners[i];
					++j;
				} else {
					SY_TRACE1(SY_TRACE_AU, "AU Removed listener on %d", static_cast<int>(pinID));
				}
				++i;
			}
			propertyListenersCount = j;
			break;
		}
	#endif
		
		case kAudioUnitGetParameterSelect: {
			SY_TRACE(SY_TRACE_FREQUENT, "AU kAudioUnitGetParameterSelect");

			PARAM(AudioUnitParameterID, pinID, 0, 4);
			PARAM(AudioUnitScope, pinScope, 1, 4);
		//	PARAM(AudioUnitElement, pinElement, 2, 4);
			PARAM(Float32 *, poutValue, 3, 4);
		
			SY_TRACE2(SY_TRACE_FREQUENT, "AU Get parameter: %d, %d", static_cast<int>(pinID)
					, static_cast<int>(pinScope));
			SY_ASSERT(poutValue != 0);
			if (pinScope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			if (static_cast<int>(pinID) < 0 || static_cast<int>(pinID) >= vst->getParameterCount()) {
				throw MacOSException(kAudioUnitErr_InvalidParameter);
			}
			(*poutValue) = scaleToAUParameter(pinID, vst->getParameter(pinID));
			break;
		}
		
		case kAudioUnitSetParameterSelect: {
			SY_TRACE(SY_TRACE_FREQUENT, "AU kAudioUnitSetParameterSelect");

			PARAM(AudioUnitParameterID, pinID, 0, 5);
			PARAM(AudioUnitScope, pinScope, 1, 5);
		//	PARAM(AudioUnitElement, pinElement, 2, 5);
			PARAM(Float32, pinValue, 3, 5);
			PARAM(UInt32, pinBufferOffsetInFrames, 4, 5);
		
			SY_TRACE4(SY_TRACE_FREQUENT, "AU Set parameter: %d, %d, %f, %d", static_cast<int>(pinID)
					, static_cast<int>(pinScope), pinValue, static_cast<int>(pinBufferOffsetInFrames));
			if (pinScope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			if (static_cast<int>(pinID) < 0 || static_cast<int>(pinID) >= vst->getParameterCount()) {
				throw MacOSException(kAudioUnitErr_InvalidParameter);
			}
			vst->setParameter(pinID, scaleFromAUParameter(pinID, pinValue));
			break;
		}
		
		case kAudioUnitResetSelect: {
			SY_TRACE(SY_TRACE_AU, "AU kAudioUnitResetSelect");

			PARAM(AudioUnitScope, pinScope, 0, 2);
		//	PARAM(AudioUnitElement, pinElement, 1, 2);
		
			if (pinScope != kAudioUnitScope_Global) {
				throw MacOSException(kAudioUnitErr_InvalidScope);
			}
			if (vst->isResumed()) {
				vst->suspend();
				vst->resume();
				updateInitialDelayAndTailTimes();
			}
			lastRenderSampleTime = -12345678.0;
			break;
		}
		
		case kAudioUnitRenderSelect: {
			SY_TRACE(SY_TRACE_FREQUENT, "AU kAudioUnitRenderSelect");

			PARAM(AudioUnitRenderActionFlags *, pioActionFlags, 0, 5);
			PARAM(const AudioTimeStamp *, pinTimeStamp, 1, 5);
			PARAM(UInt32, pinOutputBusNumber, 2, 5);
			PARAM(UInt32, pinNumberFrames, 3, 5);
			PARAM(AudioBufferList *, pioData, 4, 5);
			
			render(pioActionFlags, pinTimeStamp, pinOutputBusNumber, pinNumberFrames, pioData);
			break;
		}
		
		case kAudioUnitAddRenderNotifySelect: {
			SY_TRACE(SY_TRACE_AU, "AU kAudioUnitAddRenderNotifySelect");

			PARAM(AURenderCallback, pinProc, 0, 2);
			PARAM(void *, pinProcRefCon, 1, 2);

			if (renderNotificationReceiversCount >= kMaxAURenderCallbacks) {
				throw MacOSException(memFullErr);
			}
			::AURenderCallbackStruct receiver;
			memset(&receiver, 0, sizeof (receiver));
			receiver.inputProc = pinProc;
			receiver.inputProcRefCon = pinProcRefCon;
			renderNotificationReceivers[propertyListenersCount] = receiver;
			++propertyListenersCount;
			break;
		}
		
		case kAudioUnitRemoveRenderNotifySelect: {
			SY_TRACE(SY_TRACE_AU, "AU kAudioUnitRemoveRenderNotifySelect");

			PARAM(AURenderCallback, pinProc, 0, 2);
			PARAM(void *, pinProcRefCon, 1, 2);
		
			int i = 0;
			int j = 0;
			while (i < renderNotificationReceiversCount) {
				if (renderNotificationReceivers[i].inputProc != pinProc
						|| renderNotificationReceivers[i].inputProcRefCon != pinProcRefCon) {
					renderNotificationReceivers[j] = renderNotificationReceivers[i];
					++j;
				}
				++i;
			}
			renderNotificationReceiversCount = j;
			break;
		}
		
		case kAudioUnitScheduleParametersSelect: {
			SY_TRACE(SY_TRACE_AU, "AU kAudioUnitScheduleParametersSelect");

			PARAM(AudioUnitParameterEvent *, pinParameterEvent, 0, 2);
			PARAM(UInt32, pinNumParamEvents, 1, 2);
		
			for (int i = 0; i < static_cast<int>(pinNumParamEvents); ++i) {
				const AudioUnitParameterEvent& theEvent = (pinParameterEvent)[i];
				if (theEvent.scope != kAudioUnitScope_Global) {
					throw MacOSException(kAudioUnitErr_InvalidScope);
				}
				if (static_cast<int>(theEvent.parameter) < 0 || static_cast<int>(theEvent.parameter)
						>= vst->getParameterCount()) {
					throw MacOSException(kAudioUnitErr_InvalidParameter);
				}
				if (theEvent.eventType == kParameterEvent_Immediate) {
					SY_ASSERT(0 <= static_cast<int>(theEvent.eventValues.immediate.bufferOffset)
							&& static_cast<int>(theEvent.eventValues.immediate.bufferOffset) < maxFramesPerSlice);
					vst->setParameter(theEvent.parameter, scaleFromAUParameter(theEvent.parameter
							, theEvent.eventValues.immediate.value));
				}
			}
			break;
		}
		
		case kMusicDeviceMIDIEventSelect: {
			SY_TRACE(SY_TRACE_FREQUENT, "AU kMusicDeviceMIDIEventSelect");

			PARAM(UInt32, pinStatus, 0, 4);
			PARAM(UInt32, pinData1, 1, 4);
			PARAM(UInt32, pinData2, 2, 4);
			PARAM(UInt32, pinOffsetSampleFrame, 3, 4);
		
			if (vst->wantsMidi()) {
				SY_ASSERT0(vstMidiEvents.numEvents < kMaxVSTMIDIEvents, "Too many MIDI events received");
				if (vstMidiEvents.numEvents >= kMaxVSTMIDIEvents) {
					throw MacOSException(memFullErr);
				}
				VstMidiEvent* e = reinterpret_cast<VstMidiEvent*>(vstMidiEvents.events[vstMidiEvents.numEvents]);
				e->deltaFrames = pinOffsetSampleFrame;
				e->midiData[0] = pinStatus;
				e->midiData[1] = pinData1;
				e->midiData[2] = pinData2;
				++vstMidiEvents.numEvents;
			}
			break;
		}
		
		default:
			SY_TRACE1(SY_TRACE_AU, "AU unknown selector: %d", params->what);
			throw MacOSException(badComponentSelector);
	}
}

#if (SY_INCLUDE_GUI_SUPPORT)

#if (SY_USE_COCOA_GUI)

NSView* SymbiosisComponent::createView() {
	SY_ASSERT(vst->hasEditor());

	int width, height;
	vst->getEditorDimensions(width, height);

	SY_ASSERT(cocoaView == 0);
	cocoaView = [[Symbiosis20010220_CocoaView alloc] initWithFrame:NSMakeRect(0, 0, width, height) symbiosis:this];
	SY_ASSERT(cocoaView != 0);

	SY_ASSERT(!vst->isEditorOpen());
	vst->openEditor(cocoaView);
	SY_ASSERT(vst->isEditorOpen());

	return [cocoaView autorelease];    
}

void SymbiosisComponent::dropView() {
	SY_ASSERT(vst->hasEditor());
	SY_ASSERT(vst->isEditorOpen());
	vst->closeEditor();
	SY_ASSERT(!vst->isEditorOpen());
	SY_ASSERT(cocoaView != 0);
	cocoaView = 0;
}

#elif (!SY_USE_COCOA_GUI)

void SymbiosisComponent::createView(::ControlRef* createdControl, const ::Float32Point& /*requestedSize*/
		, const ::Float32Point& requestedLocation, ::ControlRef inParentControl, ::WindowRef inWindow
		, ::AudioUnitCarbonView auViewComponentInstance) {
	if (viewComponentInstance != 0) {
		throw MacOSException(kAudioUnitErr_CannotDoInCurrentContext);
	}
		
	try {
		SY_ASSERT(vst->hasEditor());
		SY_ASSERT(viewComponentInstance == 0);
		viewComponentInstance = auViewComponentInstance;
		SY_ASSERT(viewWindowRef == 0);
		viewWindowRef = inWindow;

		::WindowAttributes attributes;
		throwOnOSError(::GetWindowAttributes(viewWindowRef, &attributes));
		bool isCompositing = (attributes & kWindowCompositingAttribute);
		SY_TRACE1(SY_TRACE_MISC, "Is composite window: %s", (isCompositing ? "true" : "false"));

	#if (SY_DO_TRACE)
		traceControlInfo("Embed in control", inParentControl);
	#endif

		int width, height;
		vst->getEditorDimensions(width, height);

		::Rect area;
		area.left = static_cast<short>(requestedLocation.x);
		area.top = static_cast<short>(requestedLocation.y);
		area.right = static_cast<short>(area.left + width);
		area.bottom = static_cast<short>(area.top + height);
		SY_ASSERT(viewControl == 0);
		throwOnOSError(::CreateUserPaneControl(viewWindowRef, &area, kControlSupportsEmbedding, &viewControl));

		::ControlRef contentControlRef = 0;
		if (isCompositing) {
			throwOnOSError(::HIViewAddSubview(inParentControl, viewControl));
			::ControlRef rootControlRef = ::HIViewGetRoot(viewWindowRef);
			throwOnOSError(::HIViewFindByID(rootControlRef, kHIViewWindowContentID, &contentControlRef));
		#if (SY_DO_TRACE)
			traceControlInfo("HI root", rootControlRef);
			traceControlInfo("HI content", contentControlRef);
		#endif
		} else {
			throwOnOSError(::EmbedControl(viewControl, inParentControl));
			throwOnOSError(::GetRootControl(viewWindowRef, &contentControlRef));
		#if (SY_DO_TRACE)
			traceControlInfo("Classic root / content", contentControlRef);
		#endif
		}
		SY_ASSERT(contentControlRef != 0);
		
		const int kMaxExistingControls = 1000;
		int existingControlCount = 0;
		::ControlRef existingControls[kMaxExistingControls];
		::UInt16 numChildren;
		throwOnOSError(::CountSubControls(contentControlRef, &numChildren));
		SY_TRACE1(SY_TRACE_MISC, "%d existing controls in AU window", numChildren);
		SY_ASSERT1(numChildren < kMaxExistingControls, "Too many controls in root (%d)", numChildren);
		for (int i = 0; i < numChildren; ++i) {
			throwOnOSError(::GetIndexedSubControl(contentControlRef, i + 1, &existingControls[i]));
			SY_ASSERT(existingControls[i] != 0);
		#if (SY_DO_TRACE)
			traceControlInfo("Existing control", existingControls[i]);
		#endif
		}
		existingControlCount = numChildren;

		vst->openEditor(viewWindowRef);
		
		const int kMaxNewControls = 1000;
		int newControlCount = 0;
		::ControlRef newControls[kMaxNewControls];
		throwOnOSError(::CountSubControls(contentControlRef, &numChildren));
		SY_TRACE1(SY_TRACE_MISC, "Now %d controls in AU window", numChildren);
		for (int i = 0; i < numChildren; ++i) {
			::ControlRef controlRef;
			throwOnOSError(::GetIndexedSubControl(contentControlRef, i + 1, &controlRef));
			SY_ASSERT(controlRef != 0);
			bool isNewControl = true;
			for (int j = 0; j < existingControlCount; ++j) {
				if (controlRef == existingControls[j]) {
					isNewControl = false;
					break;
				}
			}
			if (isNewControl) {
				newControls[newControlCount] = controlRef;
				++newControlCount;
				SY_ASSERT1(newControlCount <= kMaxNewControls, "Too many controls in root (%d)", numChildren);
			#if (SY_DO_TRACE)
				traceControlInfo("New control", controlRef);
			#endif
			}
		}

		SY_ASSERT(newControlCount > 0);

		for (int i = 0; i < newControlCount; ++i) {
			SY_TRACE1(SY_TRACE_MISC, "Moving new control @0x%8.8x into AU view"
					, reinterpret_cast<unsigned int>(newControls[i]));
			if (isCompositing) {
				throwOnOSError(::HIViewAddSubview(viewControl, newControls[i]));
			} else {
				throwOnOSError(::EmbedControl(newControls[i], viewControl));											// Note: non-composite window uses window-global coordinates for embedded controls, which means we must move everything.
				::MoveControl(newControls[i], area.left, area.top);
			}
		}
		SY_TRACE1(SY_TRACE_MISC, "Moved %d new controls into AU view", newControlCount);
	}
	catch (...) {
		if (viewControl != 0) {
			::DisposeControl(viewControl);
			viewControl = 0;
		}
		if (vst->isEditorOpen()) {
			vst->closeEditor();
		}
		viewComponentInstance = 0;
		viewWindowRef = 0;
		throw;
	}
	(*createdControl) = viewControl;
}

void SymbiosisComponent::dropView(::AudioUnitCarbonView auViewComponentInstance) {
	SY_TRACE3(SY_TRACE_MISC
			, "void SymbiosisComponent::dropView(::AudioUnitCarbonView auViewComponentInstance=@0x%8.8X)"
			" (auComponentInstance=@0x%8.8X, viewComponentInstance=@0x%8.8X)"
			, reinterpret_cast<unsigned int>(auViewComponentInstance)
			, reinterpret_cast<unsigned int>(auComponentInstance)
			, reinterpret_cast<unsigned int>(viewComponentInstance))
	SY_ASSERT(viewComponentInstance == auViewComponentInstance);
	SY_ASSERT(vst->isEditorOpen());
	vst->closeEditor();
	SY_ASSERT(viewComponentInstance != 0);
	viewComponentInstance = 0;
	SY_ASSERT(viewWindowRef != 0);
	viewWindowRef = 0;
	SY_ASSERT(viewControl != 0);
	viewControl = 0;
	viewEventListener = 0;
	viewEventListenerUserData = 0;
}

void SymbiosisComponent::setViewEventListener(::AudioUnitCarbonViewEventListener callback, void* userData) {
	SY_ASSERT(viewComponentInstance != 0);
	viewEventListener = callback;
	viewEventListenerUserData = userData;
}

#endif (!SY_USE_COCOA_GUI)

#endif (SY_INCLUDE_GUI_SUPPORT)

::EventLoopTimerUPP SymbiosisComponent::idleTimerUPP = ::NewEventLoopTimerUPP(idleTimerAction);

/* --- Component entry functions --- */

extern "C" __attribute__((visibility("default"))) ::ComponentResult SymbiosisEntry(::ComponentParameters* params
		, ::Handle userDataHandle);

extern "C" __attribute__((visibility("default"))) ::ComponentResult SymbiosisEntry(::ComponentParameters* params
		, ::Handle userDataHandle) {
	try {
		switch (params->what) {
			case kComponentCanDoSelect:
				SY_TRACE1(SY_TRACE_AU, "AU kComponentCanDoSelect: %ld", params->params[0]);
				switch (params->params[0]) {
					case kAudioUnitInitializeSelect: case kAudioUnitUninitializeSelect:
					case kAudioUnitGetPropertyInfoSelect: case kAudioUnitGetPropertySelect:
					case kAudioUnitSetPropertySelect: case kAudioUnitAddPropertyListenerSelect:
				#if (!__LP64__)
					case kAudioUnitRemovePropertyListenerSelect:
				#endif
				#if (__MAC_OS_X_VERSION_MAX_ALLOWED >= 1050)
					case kAudioUnitRemovePropertyListenerWithUserDataSelect:
				#endif
					case kAudioUnitGetParameterSelect: case kAudioUnitSetParameterSelect: case kAudioUnitResetSelect:

					case kAudioUnitAddRenderNotifySelect: case kAudioUnitRemoveRenderNotifySelect:
					case kAudioUnitScheduleParametersSelect: case kAudioUnitRenderSelect:

					case kMusicDeviceMIDIEventSelect:
						
					case kComponentOpenSelect: case kComponentCloseSelect: case kComponentVersionSelect:
					case kComponentCanDoSelect:
						return 1;
					
					default: return 0;
				}
				break;
				
			case kComponentOpenSelect: {
				SY_TRACE(SY_TRACE_AU, "AU kComponentOpenSelect");
				::AudioUnit auComponentInstance = reinterpret_cast< ::ComponentInstance >(params->params[0]);
				SymbiosisComponent* symbiosisComponent = new SymbiosisComponent(auComponentInstance);
				::SetComponentInstanceStorage(auComponentInstance, reinterpret_cast< ::Handle >(symbiosisComponent));
				break;
			}
			
			case kComponentCloseSelect: {
				SY_TRACE(SY_TRACE_AU, "AU kComponentCloseSelect");
				SymbiosisComponent* symbiosisComponent = reinterpret_cast<SymbiosisComponent*>(userDataHandle);
				if (symbiosisComponent != 0) {
					delete symbiosisComponent;
					symbiosisComponent = 0;
					::SetComponentInstanceStorage(reinterpret_cast< ::ComponentInstance >(params->params[0]), 0);
					SY_TRACE_STOP;
				}
				break;
			}

			case kComponentVersionSelect: {
				SY_TRACE(SY_TRACE_AU, "AU kComponentVersionSelect");
				::Handle theResource;
				throwOnOSError(::GetComponentResource(reinterpret_cast< ::Component >(params->params[0]), 'thng'
						, kSymbiosisThngResourceId, &theResource));
				::ComponentResult version
						= (**reinterpret_cast< ::ExtComponentResource** >(theResource)).componentVersion;
				::DisposeHandle(theResource);
				theResource = 0;
				return version;
			}

			default: {
				SymbiosisComponent* symbiosisComponent = reinterpret_cast<SymbiosisComponent*>(userDataHandle);
				if (symbiosisComponent != 0) {
					symbiosisComponent->dispatch(params);
				} else {
					SY_TRACE1(SY_TRACE_AU, "Symbiosis component pointer is null (cannot handle selector: %d)"
							, params->what);
					throw MacOSException(badComponentSelector);
				}
				break;
			}
		}
	}
	SY_COMPONENT_CATCH("SymbiosisEntry");
	return noErr;
}

#if (SY_INCLUDE_GUI_SUPPORT)

#if (SY_USE_COCOA_GUI)

@implementation Symbiosis20010220_CocoaView

- initWithFrame:(NSRect)frame symbiosis:(SymbiosisComponent*)symbiosisComponent {
	SY_ASSERT(symbiosisComponent != 0);
	if ((self = [super initWithFrame:frame]) != nil) symbiosis = symbiosisComponent;
	return self;
}

- (void)dealloc { SY_ASSERT(symbiosis != 0); symbiosis->dropView(); [super dealloc]; }

@end

@implementation Symbiosis20010220_CocoaViewFactory

- (unsigned int) interfaceVersion { return 0; }

- (NSString*) description { return @"Symbiosis Cocoa View"; }

- (NSView*)uiViewForAudioUnit:(AudioUnit)inAU withSize:(NSSize)inPreferredSize {
	SymbiosisComponent* symbiosisComponent = (SymbiosisComponent*)(::GetComponentInstanceStorage(inAU));
	SY_ASSERT(symbiosisComponent != 0);	
	return symbiosisComponent->createView();
}

@end

#elif (!SY_USE_COCOA_GUI)

extern "C" __attribute__((visibility("default"))) ::ComponentResult SymbiosisViewEntry(::ComponentParameters* params
		, ::Handle userDataHandle) {
	try {
		switch (params->what) {
			case kComponentCanDoSelect:
				SY_TRACE1(SY_TRACE_AU, "AUView kComponentCanDoSelect: %d", static_cast<int>(params->params[0]));
				switch (params->params[0]) {
					case kComponentOpenSelect:
					case kComponentCloseSelect:
					case kComponentVersionSelect:
					case kComponentCanDoSelect:
					case kAudioUnitCarbonViewCreateSelect:
					case kAudioUnitCarbonViewSetEventListenerSelect: return 1;
					default: return 0;
				}
				break;
				
			case kComponentOpenSelect: SY_TRACE(SY_TRACE_AU, "AUView kComponentOpenSelect"); break;
			
			case kComponentCloseSelect: {
				SY_TRACE(SY_TRACE_AU, "AUView kComponentCloseSelect");
				SymbiosisComponent* symbiosisComponent = reinterpret_cast<SymbiosisComponent*>(userDataHandle);
				if (symbiosisComponent != 0) {
				#if (SY_INCLUDE_GUI_SUPPORT)
					symbiosisComponent->dropView(reinterpret_cast< ::ComponentInstance >(params->params[0]));
				#endif
					::SetComponentInstanceStorage(reinterpret_cast< ::ComponentInstance >(params->params[0]), 0);
				}
				break;
			}

			case kComponentVersionSelect: {
				SY_TRACE(SY_TRACE_AU, "AUView kComponentVersionSelect");
				::Handle theResource;
				throwOnOSError(::GetComponentResource(reinterpret_cast< ::Component >(params->params[0]), 'thng'
						, kSymbiosisAUViewThngResourceId, &theResource));
				::ComponentResult version
						= (**reinterpret_cast< ::ExtComponentResource** >(theResource)).componentVersion;
				::DisposeHandle(theResource);
				theResource = 0;
				return version;
				break;
			}
			
			case kAudioUnitCarbonViewCreateSelect: {
				struct AudioUnitCarbonViewCreateGluePB {
					unsigned char componentFlags;
					unsigned char componentParamSize;
					short componentWhat;
					::ControlRef* outControl;
					const ::Float32Point* inSize;
					const ::Float32Point* inLocation;
					::ControlRef inParentControl;
					::WindowRef inWindow;
					::AudioUnit inAudioUnit;
					::AudioUnitCarbonView inView;
				};
				AudioUnitCarbonViewCreateGluePB* p = reinterpret_cast<AudioUnitCarbonViewCreateGluePB*>(params);
				SY_TRACE3(SY_TRACE_AU, "AUView kAudioUnitCarbonViewCreateSelect (inWindow=@0x%8.8x,"
						" inAudioUnit=@0x%8.8x, inView=@0x%8.8x)", reinterpret_cast<unsigned int>(p->inWindow)
						, reinterpret_cast<unsigned int>(p->inAudioUnit), reinterpret_cast<unsigned int>(p->inView));
				SymbiosisComponent* symbiosisComponent = reinterpret_cast<SymbiosisComponent*>
						(::GetComponentInstanceStorage(p->inAudioUnit));
				SY_ASSERT(symbiosisComponent != 0);
				::SetComponentInstanceStorage(p->inView, reinterpret_cast< ::Handle >(symbiosisComponent));
				symbiosisComponent->createView(p->outControl, *p->inSize, *p->inLocation, p->inParentControl
						, p->inWindow, p->inView);
				break;
			}

			case kAudioUnitCarbonViewSetEventListenerSelect: {
				SY_TRACE(SY_TRACE_AU, "AUView kAudioUnitCarbonViewSetEventListenerSelect");
				struct AudioUnitCarbonViewSetEventListenerGluePB {
					unsigned char componentFlags;
					unsigned char componentParamSize;
					short componentWhat;
					void* inUserData;
					::AudioUnitCarbonViewEventListener inCallback;
					::AudioUnitCarbonView inView;
				};
				AudioUnitCarbonViewSetEventListenerGluePB *pb
						= reinterpret_cast<AudioUnitCarbonViewSetEventListenerGluePB*>(params);
				SymbiosisComponent* symbiosisComponent = reinterpret_cast<SymbiosisComponent*>(userDataHandle);
				if (symbiosisComponent != 0) {
					symbiosisComponent->setViewEventListener(pb->inCallback, pb->inUserData);
				} else {
					throw MacOSException(kAudioUnitErr_CannotDoInCurrentContext);
				}
				break;
			}
			
			default:
				SY_TRACE1(SY_TRACE_AU, "AUView unknown selector: %d", params->what);
				throw MacOSException(badComponentSelector);
		}
	}
	SY_COMPONENT_CATCH("SymbiosisViewEntry");
	return noErr;
}

#endif (!SY_USE_COCOA_GUI)

#endif (SY_INCLUDE_GUI_SUPPORT)
