/* ***** BEGIN LICENSE BLOCK *****
 * This file is part of Natron <https://natrongithub.github.io/>,
 * (C) 2018-2026 The Natron developers
 *
 * Natron is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * Natron is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Natron.  If not, see <http://www.gnu.org/licenses/gpl-2.0.html>
 * ***** END LICENSE BLOCK ***** */

#ifndef NATRON_GLOBAL_PROFILING_H
#define NATRON_GLOBAL_PROFILING_H

// Optional instrumentation for the Tracy profiler (https://github.com/wolfpld/tracy).
// Enabled by configuring CMake with -DNATRON_TRACY=ON, which defines NATRON_USE_TRACY.
// When disabled, all macros expand to nothing and have zero cost.

#ifdef NATRON_USE_TRACY

#include <tracy/Tracy.hpp>

// Time the enclosing scope under a static name (string literal).
#define NATRON_PROFILE_SCOPE(name) ZoneScopedN(name)
// Attach dynamic text (e.g. a node name) to the current zone.
#define NATRON_PROFILE_TEXT(str, size) ZoneText(str, size)
// Mark the end of a displayed frame (one viewer repaint).
#define NATRON_PROFILE_FRAME() FrameMark

#else

#define NATRON_PROFILE_SCOPE(name)
#define NATRON_PROFILE_TEXT(str, size)
#define NATRON_PROFILE_FRAME()

#endif

#endif // NATRON_GLOBAL_PROFILING_H
