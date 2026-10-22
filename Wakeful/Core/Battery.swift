import IOKit.ps

enum Battery {
    struct Status {
        var onBattery: Bool
        var percent: Int?
    }

    static func status() -> Status {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return Status(onBattery: false, percent: nil)
        }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let onBattery = providing == kIOPSBatteryPowerValue

        var percent: Int?
        if let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let description = IOPSGetPowerSourceDescription(info, source)?
                    .takeUnretainedValue() as? [String: Any],
                    let current = description[kIOPSCurrentCapacityKey] as? Int,
                    let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
                else { continue }
                percent = current * 100 / max
                break
            }
        }
        return Status(onBattery: onBattery, percent: percent)
    }
}
