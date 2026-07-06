import Foundation

public enum SMCTemperatureDecoder {
  public static func decode(bytes: [UInt8], size: UInt32, dataType: String? = nil) -> Double? {
    if let dataType {
      switch dataType {
      case "sp78", "sp87":
        return decodeSP78(bytes)
      case "flt":
        let value = decodeFloat(bytes)
        return valid(value) ? value : nil
      case "fpe2":
        guard bytes.count >= 2 else { return nil }
        let value = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4.0
        return valid(value) ? value : nil
      default:
        break
      }
    }

    switch size {
    case 4:
      let value = decodeFloat(bytes)
      return valid(value) ? value : nil
    case 2:
      if let value = decodeSP78(bytes) { return value }
      guard bytes.count >= 2 else { return nil }
      let fpe2 = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4.0
      return valid(fpe2) ? fpe2 : nil
    default:
      let value = decodeFloat(bytes)
      return valid(value) ? value : nil
    }
  }

  private static func decodeSP78(_ bytes: [UInt8]) -> Double? {
    guard bytes.count >= 2 else { return nil }
    let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    let value = Double(Int16(bitPattern: raw)) / 256.0
    return valid(value) ? value : nil
  }

  private static func decodeFloat(_ bytes: [UInt8]) -> Double {
    guard bytes.count >= 4 else { return .nan }
    let value = bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
    return Double(value)
  }

  private static func valid(_ value: Double) -> Bool {
    value.isFinite && value > 0 && value < 150
  }
}
