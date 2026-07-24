import Darwin
import Foundation
import IOKit

public struct SystemLoadSample: Sendable {
  public let cpuUsagePercent: Double?
  public let gpuUsagePercent: Double?
}

public final class SystemLoadMonitor: @unchecked Sendable {
  private var previousCPU: CPUTickSnapshot?
  private let lock = NSLock()

  public init() {}

  public func sample() -> SystemLoadSample {
    SystemLoadSample(
      cpuUsagePercent: sampleCPU(),
      gpuUsagePercent: sampleGPU()
    )
  }

  private func sampleCPU() -> Double? {
    lock.lock()
    defer { lock.unlock() }
    guard let snapshot = readCPUTicks() else { return nil }
    guard let previous = previousCPU else {
      previousCPU = snapshot
      return nil
    }
    let userDelta = Double(snapshot.user) - Double(previous.user)
    let systemDelta = Double(snapshot.system) - Double(previous.system)
    let niceDelta = Double(snapshot.nice) - Double(previous.nice)
    let idleDelta = Double(snapshot.idle) - Double(previous.idle)
    let totalDelta = userDelta + systemDelta + niceDelta + idleDelta
    previousCPU = snapshot
    guard totalDelta > 0 else { return nil }
    let usage = 100.0 * (userDelta + systemDelta + niceDelta) / totalDelta
    return max(0.0, min(100.0, usage))
  }

  private func sampleGPU() -> Double? {
    readGPUUtilization()
  }
}

private struct CPUTickSnapshot {
  let user: UInt32
  let system: UInt32
  let idle: UInt32
  let nice: UInt32
}

private func readCPUTicks() -> CPUTickSnapshot? {
  let loadInfoCount = mach_msg_type_number_t(
    MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
  )
  var info = host_cpu_load_info()
  let host = mach_host_self()
  defer { mach_port_deallocate(mach_task_self_, host) }
  var count = loadInfoCount
  let result = withUnsafeMutablePointer(to: &info) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(loadInfoCount)) {
      host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
    }
  }
  guard result == KERN_SUCCESS else { return nil }
  return CPUTickSnapshot(
    user: info.cpu_ticks.0,
    system: info.cpu_ticks.1,
    idle: info.cpu_ticks.2,
    nice: info.cpu_ticks.3
  )
}

private func readGPUUtilization() -> Double? {
  guard let matching = IOServiceMatching("AGXAccelerator") else { return nil }
  var iterator: io_iterator_t = 0
  guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
  defer { IOObjectRelease(iterator) }
  while true {
    let service = IOIteratorNext(iterator)
    guard service != IO_OBJECT_NULL else { break }
    defer { IOObjectRelease(service) }
    var propertiesRef: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &propertiesRef, kCFAllocatorDefault, 0) == KERN_SUCCESS else { continue }
    guard let properties = propertiesRef?.takeRetainedValue() as? [String: Any] else { continue }
    guard let stats = properties["PerformanceStatistics"] as? [String: Any] else { continue }
    if let value = stats["Device Utilization %"] as? Double {
      return clampPercent(value)
    }
    if let value = stats["Device Utilization %"] as? Int {
      return clampPercent(Double(value))
    }
    if let value = stats["GPU Core Utilization"] as? Double {
      return clampPercent(value)
    }
    if let value = stats["GPU Core Utilization"] as? Int {
      return clampPercent(Double(value))
    }
  }
  return nil
}

private func clampPercent(_ value: Double) -> Double {
  max(0.0, min(100.0, value))
}
