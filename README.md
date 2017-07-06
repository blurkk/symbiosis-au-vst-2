# What Is Symbiosis?

From the [original documentation](documentation/Symbiosis%20Documentation.txt):
> Symbiosis is a developer tool for adapting Mac OS X VST plug-ins to the Audio Unit (AU) standard. It essentially
consists of a single C++ file that you can compile into your VST project to make the plug-in compatible with the
Audio Unit protocol. Optionally, you may choose to use a pre-built "wrapper plug-in" for adapting your existing VST
plug-in to the AU standard without even having to recompile any source code.

# History

*Symbiosis* was developed and open-sourced by Magnus Lidström of [Sonic Charge](http://soniccharge.com/) fame.
It was originally hosted on [Google Code](http://code.google.com/p/symbiosis-au-vst) but doesn't appear to have been
actively maintained for some time now (the last commit by Magnus was on April 22, 2013). With the closure of Google Code,
the question was asked on the [Symbiosis mailing list / group](https://groups.google.com/forum/#!forum/symbiosis-au-vst)
whether the official repository would move, but there was no response from Magnus. In the meantime, several people have
imported the [Symbiosis Google Code repository](https://code.google.com/p/symbiosis-au-vst) into GitHub.

This repository is also an import of the *Symbiosis* repository. It contains some updates that are useful for the
[NUsofting plugins](http://nusofting.liqihsynth.com/): the ones on the `develop` branch are those that seem to be more
generally applicable, the ones on the `NUsofting/develop` branch are increasingly large divergences from the original
*Symbiosis* where we no longer need the full flexibility that it originally provided. This is especially the case where
we can provide a more direct interface to our plugin framework, and don't want / need to be limited by the VST 2.4
interface.

This version of the project also contains updates to support the Audio Unit version 2 API.
