// Separate passive IOService: no AudioDriverKit, IRQs, DMA, vendor requests,
// timers, firmware access or PCI/FPGA write calls. Never enable Memory Space.
#include <DriverKit/IOLib.h>
#include <DriverKit/IODispatchQueue.h>
#include <PCIDriverKit/IOPCIDevice.h>
#include "SymphonyPassiveDiagnostics.h"
#include "SymphonyPassiveUserClient.h"
#include "../Source/SymphonyPassiveDiagnostics.h"

struct SymphonyPassiveDiagnostics_IVars {
    IOPCIDevice *pci;
    IODispatchQueue *queue;
    uint8_t memoryIndex;
    uint64_t barSize;
    bool stopping, powerOff;
};
static bool Present(IOPCIDevice *pci) {
    uint32_t id = UINT32_MAX;
    uint16_t command = 0;
    pci->ConfigurationRead32(0, &id);
    pci->ConfigurationRead16(4, &command);
    return id == 0x220019C2u && (command & 2);
}
bool SymphonyPassiveDiagnostics::init() {
    if (!super::init()) return false;
    ivars = IONewZero(SymphonyPassiveDiagnostics_IVars, 1);
    return ivars != nullptr;
}
void SymphonyPassiveDiagnostics::free() {
    if (ivars) {
        OSSafeReleaseNULL(ivars->queue);
        OSSafeReleaseNULL(ivars->pci);
        IODelete(ivars, SymphonyPassiveDiagnostics_IVars, 1); ivars = nullptr;
    }
    super::free();
}
kern_return_t IMPL(SymphonyPassiveDiagnostics, Start) {
    auto result = Start(provider, SUPERDISPATCH);
    if (result != kIOReturnSuccess) return result;
    ivars->pci = OSDynamicCast(IOPCIDevice, provider);
    if (!ivars->pci) { Stop(provider, SUPERDISPATCH); return kIOReturnUnsupported; }
    ivars->pci->retain();
    result = ivars->pci->Open(this, 0);
    if (result != kIOReturnSuccess) {
        OSSafeReleaseNULL(ivars->pci); Stop(provider, SUPERDISPATCH); return result;
    }
    // Do not repair config or quiesce an active/dirty device. Refuse instead.
    if (!Present(ivars->pci)) { Stop(provider); return kIOReturnNotReady; }
    uint8_t type = 0;
    result = ivars->pci->GetBARInfo(0, &ivars->memoryIndex, &ivars->barSize, &type);
    if (result != kIOReturnSuccess || ivars->barSize < kRegGCSR2 + 4) {
        Stop(provider); return kIOReturnNotReady;
    }
    uint32_t gcsr = UINT32_MAX, gcsr2 = UINT32_MAX, mask = UINT32_MAX;
    ivars->pci->MemoryRead32(ivars->memoryIndex, kRegGCSR, &gcsr);
    ivars->pci->MemoryRead32(ivars->memoryIndex, kRegGCSR2, &gcsr2);
    ivars->pci->MemoryRead32(ivars->memoryIndex, kRegIntMask, &mask);
    if (gcsr == UINT32_MAX || gcsr2 == UINT32_MAX || mask != 0 ||
        (gcsr & kGCSR_DMAEnableMask) || (gcsr2 & kGCSR2_DMAEnableMask)) {
        Stop(provider); return kIOReturnBusy;
    }
    result = IODispatchQueue::Create("com.kiwimartin.symphony.passive", 0, 0, &ivars->queue);
    if (result != kIOReturnSuccess) { Stop(provider); return result; }
    RegisterService();
    return kIOReturnSuccess;
}
kern_return_t IMPL(SymphonyPassiveDiagnostics, Stop) {
    if (ivars) {
        __atomic_store_n(&ivars->stopping, true, __ATOMIC_RELEASE);
        if (ivars->queue) ivars->queue->DispatchSync(^{});
        if (ivars->pci) { ivars->pci->Close(this, 0); OSSafeReleaseNULL(ivars->pci); }
    }
    return Stop(provider, SUPERDISPATCH);
}
kern_return_t IMPL(SymphonyPassiveDiagnostics, SetPowerState) {
    if (ivars) {
        const bool off = !(powerFlags & kIOServicePowerCapabilityOn);
        __atomic_store_n(&ivars->powerOff, off, __ATOMIC_RELEASE);
        if (off && !__atomic_load_n(&ivars->stopping, __ATOMIC_ACQUIRE) && ivars->queue)
            ivars->queue->DispatchSync(^{});
    }
    return SetPowerState(powerFlags, SUPERDISPATCH);
}
kern_return_t IMPL(SymphonyPassiveDiagnostics, NewUserClient) {
    if (type != kSymphonyUserClientType || !userClient ||
        __atomic_load_n(&ivars->stopping, __ATOMIC_ACQUIRE)) return kIOReturnUnsupported;
    IOService *service = nullptr;
    auto result = Create(this, "IOUserClientProperties", &service);
    if (result != kIOReturnSuccess || !service) return result == kIOReturnSuccess ? kIOReturnNoMemory : result;
    auto client = OSDynamicCast(SymphonyPassiveUserClient, service);
    if (!client) { service->release(); return kIOReturnError; }
    client->SetDriver(this); *userClient = client;
    return kIOReturnSuccess;
}
kern_return_t SymphonyPassiveDiagnostics::ReadSnapshot(uint32_t *words) {
    if (!words || !ivars || !ivars->queue) return kIOReturnNotReady;
    __block SymphonyDualPortDiagnosticsOutput out = {};
    __block kern_return_t result = kIOReturnNotReady;
    ivars->queue->DispatchSync(^{
        if (__atomic_load_n(&ivars->stopping, __ATOMIC_ACQUIRE) ||
            __atomic_load_n(&ivars->powerOff, __ATOMIC_ACQUIRE) || !ivars->pci || !Present(ivars->pci)) return;
        out.schemaVersion = 1; out.wordCount = sizeof(out) / 4; out.pciIdentity = 0x220019C2;
        CapturePassiveRegisters(ivars->barSize, [&](uint64_t offset, uint32_t *value) {
            ivars->pci->MemoryRead32(ivars->memoryIndex, offset, value);
        }, out);
        // Reserved bit distinguishes absent counters from genuine zero counters.
        out.reserved = 1;
        result = kIOReturnSuccess;
    });
    out.status = uint32_t(result); memcpy(words, &out, sizeof(out));
    return result;
}
