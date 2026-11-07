#include <DriverKit/IOLib.h>
#include <DriverKit/OSData.h>
#include "SymphonyPassiveUserClient.h"
#include "SymphonyPassiveDiagnostics.h"
#include "../Source/SymphonyThunderbridgeShared.h"
struct SymphonyPassiveUserClient_IVars { SymphonyPassiveDiagnostics *driver; };
bool SymphonyPassiveUserClient::init() {
    if (!super::init()) return false;
    ivars = IONewZero(SymphonyPassiveUserClient_IVars, 1); return ivars != nullptr;
}
void SymphonyPassiveUserClient::free() {
    if (ivars) { OSSafeReleaseNULL(ivars->driver); IODelete(ivars, SymphonyPassiveUserClient_IVars, 1); ivars = nullptr; }
    super::free();
}
void SymphonyPassiveUserClient::SetDriver(SymphonyPassiveDiagnostics *driver) {
    if (driver) driver->retain();
    OSSafeReleaseNULL(ivars->driver); ivars->driver = driver;
}
kern_return_t SymphonyPassiveUserClient::ExternalMethod(uint64_t selector, IOUserClientMethodArguments *arguments,
    const IOUserClientMethodDispatch *, OSObject *, void *) {
    if (selector != kSelectorReadDualPortDiagnostics) return kIOReturnUnsupported;
    static const IOUserClientMethodDispatch dispatch = {
        .function = nullptr, .checkCompletionExists = false,
        .checkScalarInputCount = 0, .checkStructureInputSize = 0,
        .checkScalarOutputCount = 0, .checkStructureOutputSize = sizeof(SymphonyDualPortDiagnosticsOutput)
    };
    auto result = super::ExternalMethod(selector, arguments, &dispatch, this, nullptr);
    if (result != kIOReturnSuccess && result != kIOReturnNoCompletion) return result;
    if (!ivars->driver) return kIOReturnNotReady;
    SymphonyDualPortDiagnosticsOutput out = {};
    out.status = uint32_t(ivars->driver->ReadSnapshot(reinterpret_cast<uint32_t *>(&out)));
    auto data = OSData::withBytes(&out, sizeof(out));
    if (!data) return kIOReturnNoMemory;
    arguments->structureOutput = data; return kIOReturnSuccess;
}
