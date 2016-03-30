## What Is Symbiosis? ##

Symbiosis is a developer tool for adapting Mac OS X VST plug-ins to the Audio Unit (AU) standard. It essentially consists of a single C++ file that you can compile into your VST project to make the plug-in compatible with the Audio Unit protocol. Optionally, you may choose to use a pre-built "wrapper plug-in" for adapting your existing VST plug-in to the AU standard without even having to recompile any source code.

## How Does It Work? ##

Although the VST and Audio Unit SDKs differ greatly in implementation, the purpose and functions of the two standards are virtually identical. Both protocols provide means for querying plug-in info and capabilities, processing floating-point audio, reading and writing automation parameters, serializing the plug-in state for total recall and managing GUI interaction.

The close affinity of the two standards makes it possible to create a "wrapper" that works on "binary level", meaning that it translates messages to and from the AU host and VST plug-in in real-time. The translation works transparently for perhaps 90% of the Audio Unit functionality. Where the AU and VST standards differ greatly or where the former offers valuable features not found in the latter, Symbiosis offer configuration files and optional code extensions that allow you to create feature-complete Audio Units, true to the philosophies and principles of the architecture.

You can also configure Symbiosis to automatically convert preset files it discovers from the VST format (".fxb" and ".fxp" files) to the AU format (".aupreset" files).

## Who Is It For? ##

This is a tool for developers. It was not designed to be used by end-users. The idea is that Symbiosis is packaged into the final product, either compiled into the product on source-code level or as a "wrapper" that bridges to your VST.

Symbiosis will be of great interest to you if you already have a VST plug-in running under Mac OS X and you now wish to support the Audio Unit format. With Symbiosis, there is no need to master and implement the Audio Unit interface yourself. Although plenty of documentation and examples are available for learning the art of Audio Unit coding, it is far from trivial to understand all aspects and details of this fairly complex API. Add to this the continuous work of supporting and maintaining the source code for two different plug-in interfaces and the advantage of using Symbiosis should be obvious.

The availability of Symbiosis may also makes VST a good choice as a first plug-in format for the beginner Mac developer who one day plan to port his / her plug-in to the VST-dominant environment of Windows.

## Background ##

I (Magnus Lidström) developed Symbiosis partly because I needed such a tool for my own use, but also because I felt that all developers would benefit from a unified plug-in world with a single standard API. We will probably never be able to change the fact that certain hosts only work with certain plug-in formats, but at least, Symbiosis will make it feasible to support two of these formats with a minimal amount of overhead in code, work and continuous maintenance.

Symbiosis was first used in [MicroTonic 2.0](http://www.soniccharge.com/mtonic) in late 2005 and my plan was to release Symbiosis as open source shortly after that but other things kept me busy and it took over four years before it finally happened. Regardless, Symbiosis has been used in numerous other plug-ins already, including [Synplant](http://www.soniccharge.com/synplant), [Addictive Drums](http://www.xlnaudio.com) and [The Glue](http://www.cytomic.com/)

Notice that the coding style of Symbiosis is a bit "old-school" C++. When I began writing it back in 2004 I was still concerned about the performance of STL etc. Today I wouldn't have hesitated, but Symbiosis seems solid and very efficient as it is so I see no reason to change things now.

## Further Reading ##

The full documentation to Symbiosis can be found in text and html format in the svn repository.