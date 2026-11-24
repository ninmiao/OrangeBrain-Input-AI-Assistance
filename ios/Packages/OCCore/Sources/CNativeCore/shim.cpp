// SPDX-License-Identifier: GPL-3.0-or-later
// Compiles the shared native core in place. Paths are relative to this file
// (ios/Packages/OCCore/Sources/CNativeCore -> repository root).
#include "CNativeCore.h"  // must agree with c_api.h or compilation fails
#include "../../../../../shared/native-core/src/core.cpp"
#include "../../../../../shared/native-core/src/c_api.cpp"
