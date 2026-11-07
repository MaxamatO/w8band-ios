//
//  BluetoothManager.swift
//  w8band-ios
//
//  Created by Maksymilian Pierchała on 27/09/2026.
//

import CoreBluetooth

final class BluetoothManager : NSObject {
    private var centralManager: CBCentralManager!
    private var peripheralDevice: CBPeripheral?
    private var deviceConnected: Bool = false
    private var calibrateStarted: Bool = false
    private var resultPublished = false

    private var controlCharacteristic: CBCharacteristic? // Write, indicate
    private var resultCharacteristic: CBCharacteristic? // Notify
    private var statusCharacteristic: CBCharacteristic? // Read, notify

    private var beginFrame: BeginFrame?
    private var timingFrame: TimingFrame?
    private var motionMetricFrame: MotionMetricFrame?
    private var powerFrame: PowerFrame?
    private var endFrame: EndDataFrame?
    private var trajectoryChunk: TrajectoryChunk?
    
    private var trajectoryPoints: [TrajectoryPoint] = []
    
    let SERVICE_UUID = CBUUID(string: "19B10000-E8F2-537E-4F6C-D104768A1214")
    let CONTROL_UUID
    = CBUUID(string: "19B10001-E8F2-537E-4F6C-D104768A1214") // Control point characteristic
    let RESULT_UUID
    = CBUUID(string: "19B10002-E8F2-537E-4F6C-D104768A1214") // ResultData characterisitc
    let STATUS_UUID
    = CBUUID(string: "19B10003-E8F2-537E-4F6C-D104768A1214") // Status characteristic
    
    
    var onConnectionStatusChanged: ((String) -> Void)?
    var onConnectionButtonChanged: ((String) -> Void)?
    var onStateMachineChanged: ((String) -> Void)?
    var onCommandResponse: ((String) -> Void)?
    var onResultReady: ((MeasurementResult) -> Void)?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func isConnected() -> Bool{
        return deviceConnected
    }
    
    func connectDevice(){
        if(deviceConnected) { return }
        guard centralManager.state == .poweredOn else {
            onConnectionStatusChanged?("Bluetooth not ready")
            return
        }

        guard !centralManager.isScanning else { return }

        centralManager.scanForPeripherals(
            withServices: [SERVICE_UUID]
        )
    }
    
    func disconnectDevice(){
        if(!deviceConnected) { return }
        if(peripheralDevice == nil) {return}
        self.centralManager.cancelPeripheralConnection(self.peripheralDevice!)
    }
    
    func sendReset(){
        if(!deviceConnected) { return }
        if(controlCharacteristic == nil) { return }
        if(calibrateStarted) { return }
        let command = Data([DeviceCommands.Reset.rawValue])
        resetResult()
        self.peripheralDevice?.writeValue(command, for: controlCharacteristic!, type: .withResponse)
    }
    
    func sendCalibrate(){
        print("Calibration status: ", calibrateStarted)
        if(!deviceConnected) { return }
        if(controlCharacteristic == nil) { return }
        if(calibrateStarted) { return }
        print("Calibrate sent")
        
        let commandRaw = DeviceCommands.Calibrate
        let command = Data([commandRaw.rawValue])
        resetResult()
        self.peripheralDevice?.writeValue(command, for: controlCharacteristic!, type: .withResponse)
    }
    
    func sendWeightConfig(weight: UInt16){
        if(!deviceConnected) {return}
        if(controlCharacteristic == nil) {return}
        if(calibrateStarted) {return}
        
        guard deviceConnected,
                  let peripheral = peripheralDevice,
                  let characteristic = controlCharacteristic else {
                return
            }
        
        let weightCommandStruct: SetWeightCommand = SetWeightCommand(
            totalWeight: weight
        )
        
        let data = Data([
            weightCommandStruct.setConfigCommand.rawValue,
            UInt8(truncatingIfNeeded: weightCommandStruct.totalWeight),
            UInt8(truncatingIfNeeded: weightCommandStruct.totalWeight >> 8)
        ])

        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
    
    func handleFrame(data:Data ){
        let dataFrame = Array(data)
        let messageType: ResultDataMessageType = ResultDataMessageType(rawValue: dataFrame[1]) ?? ResultDataMessageType.Unknown
        switch messageType{
        case .Begin:
            parseBeginFrame(dataFrame: dataFrame)
            print("messageType: \(messageType.mapToString())")
        case .Timing:
            parseTimingFrame(dataFrame: dataFrame)
            print("messageType: \(messageType.mapToString())")
            break
        case .Motion:
            parseMotionFrame(dataFrame: dataFrame)
            print("messageType: \(messageType.mapToString())")
            break
        case .Power:
            parsePowerFrame(dataFrame: dataFrame)
            print("messageType: \(messageType.mapToString())")
            break
        case .Trajectory:
            print("messageType: \(messageType.mapToString())")
            parseTrajectoryChunk(dataFrame: dataFrame)
            break
        case .End:
            print("messageType: \(messageType.mapToString())")
            parseEndFrame(dataFrame: dataFrame)
            calibrateStarted = false
            break
        case .Unknown:
            print("messageType: \(messageType.mapToString())")
        }
        publishResultIfComplete()
    }
    
    func parseTrajectoryChunk(dataFrame: Array<UInt8>){

        let HEADER_SIZE = 5
        let POINT_SIZE = 4
        
        let payloadSize = dataFrame.count - HEADER_SIZE
        let pointsCount = (dataFrame.count - 5) / 4
        
        print("Inside begin frame: \(ResultDataMessageType(rawValue: dataFrame[1])?.mapToString() ?? "Unknown begin frame")")
        let protocolVersion: UInt8 = dataFrame[0]
        let messageType: UInt8 = dataFrame[1]
        let resultId: UInt16 = UInt16(dataFrame[2]) | (UInt16(dataFrame[3]) << 8)
        let resultOffset: UInt16 = UInt16(dataFrame[4])
        var points: [TrajectoryPoint] = []
        points.reserveCapacity(payloadSize / POINT_SIZE)

        for offset in stride(
            from: HEADER_SIZE,
            to: dataFrame.count,
            by: POINT_SIZE
        ) {
            let horizontal = UInt16(dataFrame[offset])
                           | (UInt16(dataFrame[offset + 1]) << 8)

            let vertical = UInt16(dataFrame[offset + 2])
                         | (UInt16(dataFrame[offset + 3]) << 8)

            points.append(
                TrajectoryPoint(
                    horizontalMm: Int16(bitPattern: horizontal),
                    verticalMm: Int16(bitPattern: vertical)
                )
            )
        }
        self.trajectoryPoints.append(contentsOf: points)
        
    }
    
    func parseBeginFrame(dataFrame: Array<UInt8>){
        guard dataFrame.count == 14 else {
            print("Incorrect BeginFrame size: \(dataFrame.count)")
            return
        }
        print("Inside begin frame: \(ResultDataMessageType(rawValue: dataFrame[1])?.mapToString() ?? "Unknown begin frame")")
        let protocolVersion: UInt8 = dataFrame[0]
        let messageType: UInt8 = dataFrame[1]
        let resultId: UInt16 = UInt16(dataFrame[2]) | (UInt16(dataFrame[3]) << 8)
        let processingStatus: UInt8 = dataFrame[4]
        let flags: UInt8 = dataFrame[5] // powerValid, valid
        let trajectoryPointCound: UInt16 = UInt16(dataFrame[6]) | (UInt16(dataFrame[7]) << 8)
        let rawSampleCount: UInt16 = UInt16(dataFrame[8]) | (UInt16(dataFrame[9]) << 8)
        let turnaroundIndex: UInt16 = UInt16(dataFrame[10]) | (UInt16(dataFrame[11]) << 8)
        let turnaroundTrajectoryIndex: UInt16 = UInt16(dataFrame[12]) | (UInt16(dataFrame[13]) << 8)
        
        self.beginFrame = BeginFrame(protocolVersion: protocolVersion, messageType: messageType, resultId: resultId, processingStatus: processingStatus, flags: flags, trajectoryPointCount: trajectoryPointCound, rawSampleCount: rawSampleCount, turnaroundIndex: turnaroundIndex, turnaroundTrajectoryIndex: turnaroundTrajectoryIndex)
        print(self.beginFrame!)
    }
    
    func parseTimingFrame(dataFrame: Array<UInt8>){
        guard dataFrame.count == 16 else {
            print("Incorrect TimingFrame size: \(dataFrame.count)")
            return
        }
        print("Inside timing frame: \(ResultDataMessageType(rawValue: dataFrame[1])?.mapToString() ?? "Unknown timing frame")")
        let protocolVersion: UInt8 = dataFrame[0]
        let messageType: UInt8 = dataFrame[1]
        let resultId: UInt16 = UInt16(dataFrame[2]) | (UInt16(dataFrame[3]) << 8)
        let durationMs: UInt32 = UInt32(dataFrame[4])
                                | (UInt32(dataFrame[5]) << 8)
                                | (UInt32(dataFrame[6]) << 16)
                                | (UInt32(dataFrame[7]) << 24)
        let eccentricDurationMs: UInt32 = UInt32(dataFrame[8])
                                | (UInt32(dataFrame[9]) << 8)
                                | (UInt32(dataFrame[10]) << 16)
                                | (UInt32(dataFrame[11]) << 24)
        let concentricDurationMs: UInt32 = UInt32(dataFrame[12])
                                | (UInt32(dataFrame[13]) << 8)
                                | (UInt32(dataFrame[14]) << 16)
                                | (UInt32(dataFrame[15]) << 24)
        
        self.timingFrame = TimingFrame(protocolVersion: protocolVersion, messageType: messageType, resultId: resultId, durationMs: durationMs, eccentricDurationMs: eccentricDurationMs, concentricDurationMs: concentricDurationMs)
        print(self.timingFrame!)
    }
    
    func parsePowerFrame(dataFrame: Array<UInt8>){
        guard dataFrame.count == 12 else {
            print("Incorrect PowerFrame size: \(dataFrame.count)")
            return
        }
        print("Inside power frame: \(ResultDataMessageType(rawValue: dataFrame[1])?.mapToString() ?? "Unknown power frame")")
        let protocolVersion: UInt8 = dataFrame[0]
        let messageType: UInt8 = dataFrame[1]
        let resultId: UInt16 = UInt16(dataFrame[2]) | (UInt16(dataFrame[3]) << 8)
        let maxPowerMilliwatts: UInt32 =
            UInt32(dataFrame[4])
            | (UInt32(dataFrame[5]) << 8)
            | (UInt32(dataFrame[6]) << 16)
            | (UInt32(dataFrame[7]) << 24)
        let meanConcentricPowerMilliwatts =
            UInt32(dataFrame[8])
            | (UInt32(dataFrame[9]) << 8)
            | (UInt32(dataFrame[10]) << 16)
            | (UInt32(dataFrame[11]) << 24)
        
        self.powerFrame = PowerFrame(protocolVersion: protocolVersion, messageType: messageType, resultId: resultId, maxPowerMilliwatts: maxPowerMilliwatts, meanConcentricPowerMilliwatts: meanConcentricPowerMilliwatts)
        print(self.powerFrame!)
    }

    
    func parseMotionFrame(dataFrame: Array<UInt8>){
        guard dataFrame.count == 12 else {
            print("Incorrect MotionFrame size: \(dataFrame.count)")
            return
        }
        print("Inside motion frame: \(ResultDataMessageType(rawValue: dataFrame[1])?.mapToString() ?? "Unknown motion frame")")
        let protocolVersion: UInt8 = dataFrame[0]
        let messageType: UInt8 = dataFrame[1]
        let resultId: UInt16 = UInt16(dataFrame[2]) | (UInt16(dataFrame[3]) << 8)
        let verticalRomMm: UInt16 = UInt16(dataFrame[4]) | (UInt16(dataFrame[5]) << 8)
        let maxVelocityMmPerSec: UInt16 = UInt16(dataFrame[6]) | (UInt16(dataFrame[7]) << 8)
        let meanConcentricVelocityMmPerSec: UInt16 = UInt16(dataFrame[8]) | (UInt16(dataFrame[9]) << 8)
        let maxWorldGravityStdMg: UInt16 = UInt16(dataFrame[10]) | (UInt16(dataFrame[11]) << 8)
        
        self.motionMetricFrame = MotionMetricFrame(protocolVersion: protocolVersion, messageType: messageType, resultId: resultId, verticalRomMm: verticalRomMm, maxVelocityMmPerSec: maxVelocityMmPerSec, meanConcentricVelocityMmPerSec: meanConcentricVelocityMmPerSec, maxWorldGravityStdMg: maxWorldGravityStdMg)
        print(self.motionMetricFrame!)
    }
    
    func parseEndFrame(dataFrame: Array<UInt8>){
        guard dataFrame.count == 6 else {
            print("Incorrect EndFrame size: \(dataFrame.count)")
            return
        }
        print("Inside End frame: \(ResultDataMessageType(rawValue: dataFrame[1])?.mapToString() ?? "Unknown end frame")")
        let protocolVersion: UInt8 = dataFrame[0]
        let messageType: UInt8 = dataFrame[1]
        let resultId: UInt16 = UInt16(dataFrame[2]) | (UInt16(dataFrame[3]) << 8)
        let numberOfPoints: UInt16 = UInt16(dataFrame[4]) | (UInt16(dataFrame[5]) << 8)
        
        self.endFrame = EndDataFrame(protocolVersion: protocolVersion, messageType: messageType, resultId: resultId, numberOfPoints: numberOfPoints)
        print(self.endFrame!)
    }
    
    private func publishResultIfComplete(){
        guard !resultPublished,
              let begin = beginFrame,
              let power = powerFrame,
              let timing = timingFrame,
              let motion = motionMetricFrame,
              let end = endFrame else {
            return
        }
        
        let resultId = begin.resultId
        
        guard resultId == timing.resultId,
              resultId == motion.resultId,
              resultId == power.resultId,
              resultId == end.resultId else {
            return
        }
        
        resultPublished = true
        calibrateStarted = false
        print("Result ready - publisging")
        onResultReady?(
            MeasurementResult(resultId: resultId, timing: timing, motion: motion, power: power, trajectoryPoints: self.trajectoryPoints)
        )
    }
    
    private func resetResult() {
        beginFrame = nil
        timingFrame = nil
        motionMetricFrame = nil
        powerFrame = nil
        endFrame = nil
        trajectoryChunk = nil
        trajectoryPoints.removeAll()
        resultPublished = false
    }
}

extension BluetoothManager: CBCentralManagerDelegate
{
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
        } else {
            // Handle Bluetooth not available or powered off
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if let advertisementName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            print("Peripheral name: \(advertisementName)")
        }
        guard self.peripheralDevice == nil else { return }

        self.peripheralDevice = peripheral
        central.stopScan()

        onConnectionStatusChanged?("Connecting")
        central.connect(peripheral, options: nil)
        self.peripheralDevice = peripheral
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        deviceConnected = true
        onConnectionStatusChanged?("Connected")
        onConnectionButtonChanged?("Disconnect")
        
        peripheral.delegate = self
        peripheral.discoverServices([SERVICE_UUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        onConnectionStatusChanged?("Failed to connect")
        print(error.debugDescription)
        self.peripheralDevice = nil
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        deviceConnected = false
        onConnectionStatusChanged?("Disconnected")
        onConnectionButtonChanged?("Connect")
        self.peripheralDevice = nil
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error = error {
            print("Unable to discover services: \(error.localizedDescription)")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        peripheral.services?.forEach { service in
            peripheral.discoverCharacteristics([RESULT_UUID, STATUS_UUID, CONTROL_UUID], for: service)
          }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        if let error = error {
            print("Unable to discover characteristics: \(error.localizedDescription)")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        for characteristic in service.characteristics ?? []
        {
            switch characteristic.uuid
            {
            case RESULT_UUID:
                self.resultCharacteristic = characteristic
            case CONTROL_UUID:
                self.controlCharacteristic = characteristic
            case STATUS_UUID:
                self.statusCharacteristic = characteristic
            default:
                continue
            }
            
            let properties = characteristic.properties
            if(properties.contains(.notify) || properties.contains(.indicate))
            {
                print("Characterisitc: \(characteristic) is set notify")
                peripheral.setNotifyValue(true, for: characteristic)
            }
            else
            {
                print("Characteristic \(characteristic.uuid) does not support notify")
            }
                
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Perform any error handling if one occurred
        if let error = error {
        print("Characteristic value update failed: \(error.localizedDescription)")
        return
        }
        print("VALUE callback: \(characteristic.uuid)")
        // Retrieve the data from the characteristic
        guard let data = characteristic.value else { return }

        switch characteristic.uuid
        {
        case RESULT_UUID:
            handleFrame(data: data)
            print("Result incoming!!!")
            break
        case STATUS_UUID:
            guard data.count == 1, let rawStatus = data.first else {
                print("wrong status length: \(data.count)")
                return
            }
            let status = DeviceStatus(rawValue: rawStatus)
            let statusString = status?.mapToString() ?? "Unknown"
            if(status == DeviceStatus.Error){
                calibrateStarted = false
            }
            onStateMachineChanged?(statusString)
            break
        case CONTROL_UUID:
            guard data.count == 2, let commandType = data.first, let rawResponse = data.last else {
                print("Wrong control response length: \(data.count)")
                return
            }
            
            let sentCommand = DeviceCommands(rawValue: commandType) ?? DeviceCommands.Unknown
            let command = DeviceCommandsResponse(rawValue: rawResponse) ?? DeviceCommandsResponse.Unknown
            
            let commandResponseString = command.mapToString()
            print("Command response: \(commandResponseString)")
            print("command type: \(commandType)")
            
            // Set calibrate started only when command was calibrate and response was OK
            if(sentCommand == DeviceCommands.Calibrate && command == DeviceCommandsResponse.Ok)
            {
                calibrateStarted = true
            }
            // If we sent command Reset and recieved OK, we reset calibrateStarted
            // Because that means an error occurred, and want to go back to IdleState
            else if(sentCommand == DeviceCommands.Reset && command == DeviceCommandsResponse.Ok)
            {
                calibrateStarted = false
            }
            onCommandResponse?(commandResponseString)
            break
        default:
            break
        }
        
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                        didUpdateNotificationStateFor characteristic: CBCharacteristic,
                        error: Error?) {
        // Perform any error handling if one occurred.
        // It's not necessary to abandon the connection from this kind of error
        if let error = error {
        print("Characteristic update notification error: \(error.localizedDescription)")
        return
        }
        if characteristic.uuid == STATUS_UUID,
           characteristic.isNotifying,
           characteristic.properties.contains(.read) {
            peripheral.readValue(for: characteristic)
        }
        
        // Check if it is successfully set as notifying
        if characteristic.isNotifying {
        print("Characteristic notifications have begun.")
        } else {
        print("Characteristic notifications have stopped. Disconnecting.")
        centralManager.cancelPeripheralConnection(peripheral)
        }

        // Send any info to the peripheral from the central
    }
    
}
