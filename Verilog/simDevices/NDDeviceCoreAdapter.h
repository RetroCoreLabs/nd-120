/**************************************************************************
** NDDeviceCore -> ND-120 Verilator harness ADAPTER                       **
**                                                                       **
** THE BRIDGE. NDDeviceCore ($ND_REPOS/NDDeviceCore) holds the            **
** PORTABLE C99 device cores that also compile into the RP2350 NDModulE   **
** firmware. This adapter wraps ONE such core (an nd_device*) in the      **
** C++ NDDevice interface the ND-120 harness already drives, so the very  **
** same .c that runs on the controller card is exercised by the REAL      **
** ND-120 CPU + bus RTL inside Verilator.                                 **
**                                                                       **
** The mapping is 1:1 by design - nd_device_vt was modelled on NDDevice:  **
**                                                                       **
**   NDDevice::Reset()          -> vt->reset(dev)                         **
**   NDDevice::Tick()           -> vt->tick(dev)   (same interruptBits)   **
**   NDDevice::Read(addr)       -> vt->read(dev, addr)                    **
**   NDDevice::Write(addr,val)  -> vt->write(dev, addr, val)              **
**   NDDevice::IDENT(level)     -> vt->ident(dev, level)                  **
**   NDDevice::IsInAddress()    -> start/endAddress copied from the core  **
**                                                                       **
** COMPILED ONLY under -DND120_DEVICECORE (runSim: make DEVICECORE=1).    **
** The default harness build never sees this file.                        **
**                                                                       **
** NDDeviceCore's headers are extern "C"-guarded, so the C99 cores link   **
** into this C++ harness unchanged.                                        **
***************************************************************************/

#ifndef NDDEVICECOREADAPTER_H
#define NDDEVICECOREADAPTER_H

#include "NDDevices.h"

extern "C" {
#include "nd_device.h"
#include "nd_char.h"
#include "nd_dma.h"
#include "nd_storage.h"
}

/**
 * Wraps a portable nd_device core as a harness NDDevice.
 *
 * The core instance itself (nd_lineprinter, nd_terminal, ...) is owned by the
 * caller - typically a file-scope static in NDDeviceCoreAdapter.cpp - and is
 * only BORROWED here. chan may be null for a non-character device; when it is
 * non-null the shared character queue is pumped once per Tick(), which is what
 * lets an in-flight PUT/GET actually finish.
 */
class NDDeviceCoreAdapter : public NDDevice
{
public:
    NDDeviceCoreAdapter(nd_device *dev, nd_char_queue *chan,
                        nd_storage_queue *store = nullptr,
                        nd_dma_engine *dma = nullptr)
        : NDDevice(0), dev_(dev), chan_(chan), store_(store), dma_(dma)
    {
        // Expose the core's claimed IOX window to NDDevice::IsInAddress(),
        // which is what DeviceManager::Claims() consults. Claiming exactly
        // (and only) what the core owns is REQUIRED: the harness answers a
        // claimed read immediately, which would otherwise race and beat the
        // Verilog devices sharing the bus (see the Claims() note in NDBus.cpp).
        startAddress   = dev->start_address;
        endAddress     = dev->end_address;
        InterruptLevel = dev->int_level;
        IdentCode      = dev->ident_code;
    }

    void Reset() override
    {
        dev_->vt->reset(dev_);
    }

    uint16_t Read(uint32_t address) override
    {
        return dev_->vt->read(dev_, address);
    }

    void Write(uint32_t address, uint16_t value) override
    {
        dev_->vt->write(dev_, address, value);
    }

    uint16_t IDENT(uint16_t level) override
    {
        return dev_->vt->ident(dev_, level);
    }

    uint16_t Tick() override
    {
        // Pump the character seam BEFORE the device tick: a completion fired
        // here (ready-for-transfer + level 10) is then visible in the same
        // interruptBits the harness drives onto BINT10..13 this half-clock.
        if (chan_ != nullptr)
            nd_char_queue_tick(chan_);

        // Same reasoning for the BLOCK seams. Order matters: storage first,
        // because a storage completion is what submits the next DMA request,
        // so pumping them in this order advances a whole phase per half-clock
        // instead of one phase every two.
        if (store_ != nullptr)
            nd_storage_queue_tick(store_);

        if (dma_ != nullptr)
            nd_dma_engine_tick(dma_);

        return dev_->vt->tick(dev_);
    }

private:
    nd_device     *dev_;   ///< borrowed portable core
    nd_char_queue *chan_;  ///< borrowed char seam, or null for non-char devices
    nd_storage_queue *store_; ///< borrowed block seam, or null
    nd_dma_engine    *dma_;   ///< borrowed DMA engine, or null (autoload needs none)
};

/**
 * Instantiate the NDDeviceCore devices and register them with the harness
 * DeviceManager. Called from addDevices() in NDBus.cpp, guarded by
 * ND120_DEVICECORE.
 */
void addDevicesCore();

#endif // NDDEVICECOREADAPTER_H
