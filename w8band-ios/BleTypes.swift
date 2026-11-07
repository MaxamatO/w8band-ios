//
//  BleTypes.swift
//  w8band-ios
//
//  Created by Maksymilian Pierchała on 27/09/2026.
//

var PROTOCOL_VERSION: UInt8 = 0x01

enum DeviceStatus: UInt8 {
    case Initializing = 0x00
    case Idle = 0x01
    case Calibrating = 0x02
    case Buffering = 0x03
    case Bufferring_WaitLiftOff = 0x13
    case Bufferring_WaitStillness = 0x23
    case Bufferring_WaitMotion = 0x33
    case Recording = 0x04
    case Processing = 0x05
    case Armed = 0x06
    case ResultReady = 0x07
    case Error = 0xFF
    
    func mapToString() -> String {
        switch self {
        case .Initializing:
            return "Initializing"
        case .Idle:
            return "Idle"
        case .Calibrating:
            return "Calibrating"
        case .Buffering:
            return "Buffering"
        case .Bufferring_WaitLiftOff:
            return "Buffering - Wait for lift off"
        case .Bufferring_WaitStillness:
            return "Buffering - Wait for stillness"
        case .Bufferring_WaitMotion:
            return "Buffering - Wait for motion"
        case .Recording:
            return "Recording"
        case .Processing:
            return "Porcessing"
        case .Armed:
            return "Armed"
        case .ResultReady:
            return "ResultReady"
        case .Error:
            return "Error - Reset to go Idle"
        }
    }
}

enum DeviceCommands: UInt8 {
    case Calibrate = 0x01
    case SetConfig = 0x02
    case Reset = 0x03
    case Unknown = 0x67
}

struct SetWeightCommand {
    let setConfigCommand: DeviceCommands = DeviceCommands.SetConfig
    let totalWeight: UInt16
}

enum DeviceCommandsResponse: UInt8 {
    case Ok = 0x00
    case InvalidCommand = 0x01
    case InvalidState = 0x02
    case Busy = 0x03
    case Unknown = 0x67
    func mapToString() -> String {
        switch self {
        case .Ok:
            return "Ok"
        case .InvalidCommand:
            return "InvalidCommand"
        case .InvalidState:
            return "InvalidState"
        case .Busy:
            return "Busy"
        case .Unknown:
            return "Unknown"
        }
    }
}

enum ResultDataMessageType: UInt8 {
    case Begin = 0x10
    case Timing = 0x11
    case Motion = 0x12
    case Power = 0x13
    case Trajectory = 0x14
    case End = 0x1F
    case Unknown = 0xFF
    
    func mapToString() -> String {
        switch self {
        case .Begin:
            return "Begin"
        case .Timing:
            return "Timing"
        case .Motion:
            return "Motion"
        case .Power:
            return "Power"
        case .Trajectory:
            return "Trajectory"
        case .End:
            return "End"
        case .Unknown:
            return "Unknown"
        }
    }
}

struct BeginFrame {
    let protocolVersion: UInt8
    let messageType: UInt8
    let resultId: UInt16
    let processingStatus: UInt8
    let flags: UInt8
    let trajectoryPointCount: UInt16
    let rawSampleCount: UInt16
    let turnaroundIndex: UInt16
    let turnaroundTrajectoryIndex: UInt16
}

struct TimingFrame {
    let protocolVersion: UInt8
    let messageType: UInt8
    let resultId: UInt16
    let durationMs: UInt32
    let eccentricDurationMs: UInt32
    let concentricDurationMs: UInt32
}

struct MotionMetricFrame {
    let protocolVersion: UInt8
    let messageType: UInt8
    let resultId: UInt16
    let verticalRomMm: UInt16
    let maxVelocityMmPerSec: UInt16
    let meanConcentricVelocityMmPerSec: UInt16
    let maxWorldGravityStdMg: UInt16
}

struct PowerFrame {
    let protocolVersion: UInt8
    let messageType: UInt8
    let resultId: UInt16
    let maxPowerMilliwatts: UInt32
    let meanConcentricPowerMilliwatts: UInt32
}

struct TrajectoryChunk {
    let protocolVersion: UInt8
    let messageType: UInt8
    let resultId: UInt16
    let resultOffset: UInt8
    let dataChunk: [UInt8]
}

struct EndDataFrame {
    let protocolVersion: UInt8
    let messageType: UInt8
    let resultId: UInt16
    let numberOfPoints: UInt16
}

struct MeasurementResult {
    let resultId: UInt16
    let timing: TimingFrame
    let motion: MotionMetricFrame
    let power: PowerFrame
    let trajectoryPoints: [TrajectoryPoint]
}

struct TrajectoryPoint {
    let horizontalMm: Int16
    let verticalMm: Int16
}
