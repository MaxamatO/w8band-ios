import UIKit

final class ViewController: UIViewController {
    @IBOutlet private weak var connectButton: UIButton!
    @IBOutlet private weak var calibrateButton: UIButton!
    @IBOutlet private weak var setWeightButton: UIButton!
    @IBOutlet private weak var resetButton: UIButton!
    
    
    // Connection status and firmware state are separate. Both stay above the scroll view.
    @IBOutlet private weak var connectionStatusLabel: UILabel!
    @IBOutlet private weak var deviceStateLabel: UILabel!
    @IBOutlet private weak var deviceResponseLabel: UILabel!

    @IBOutlet private weak var powerLabel: UILabel!
    @IBOutlet private weak var repetitionTimeLabel: UILabel!
    @IBOutlet private weak var velocityLabel: UILabel!
    @IBOutlet private weak var rangeOfMotionLabel: UILabel!
    @IBOutlet private weak var trajectoryView: TrajectoryView!

    private var bluetooth: BluetoothManager = BluetoothManager()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        
        bluetooth.onConnectionStatusChanged = { [weak self] status in
            DispatchQueue.main.async {
                self?.connectionStatusLabel.text = status
            }
        }
        bluetooth.onConnectionButtonChanged = { [weak self] title in
            DispatchQueue.main.async {
                self?.connectButton.setTitle(title, for: .normal)
            }
        }
        
        bluetooth.onStateMachineChanged = { [weak self] status in
            DispatchQueue.main.async {
                self?.deviceStateLabel.text = status
            }
        }
        
        bluetooth.onCommandResponse = { [weak self] status in
            DispatchQueue.main.async{
                self?.deviceResponseLabel.text = status
            }
        }
        
        bluetooth.onResultReady = { [weak self] result in
            DispatchQueue.main.async{ [weak self] in
                guard let self = self else { return }
                
                self.powerLabel.text = String(format: "%.1f W", Double(result.power.meanConcentricPowerMilliwatts) / 1000.0)
                self.repetitionTimeLabel.text = String(format: "%.2f s", Double(result.timing.durationMs) / 1000.0)
                self.velocityLabel.text = String(format: "%.2f m/s", Double(result.motion.meanConcentricVelocityMmPerSec) / 1000.0)
                self.rangeOfMotionLabel.text = String(format: "%.1f cm", Double(result.motion.verticalRomMm) / 10.0)
                self.trajectoryView.points = result.trajectoryPoints
            }
        }
        
    }

    @IBAction private func connectTapped(_ sender: UIButton) {
        // TODO: Connect with CoreBluetooth and subscribe to the device state characteristic.
        if(bluetooth.isConnected()){
            bluetooth.disconnectDevice()
            return
        }
        bluetooth.connectDevice()
        
    }

    @IBAction private func calibrateTapped(_ sender: UIButton) {
        // Update deviceStateLabel only from actual notifications, not from this button.
        bluetooth.sendCalibrate()
    }
    
    @IBAction func setWeightTapped(_ sender: UIButton) {
        let alert = UIAlertController(title: "Total weight configuration",
                                      message: "Set barbell + plates weight in kg.",
                                      preferredStyle: .alert)
        alert.addTextField{textField in
            textField.placeholder = "Weight [kg]"
            textField.keyboardType = .decimalPad}
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Send", style: .default) { [weak self, weak alert] _ in
                guard
                    let self,
                    let text = alert?.textFields?.first?.text,
                    let weight = self.weightInHundredths(from: text)
                else {
                    return
                }
            let currentWeight = String(format: "%.2f", Double(weight) / 100.0)

            self.setWeightButton.setTitle(
                "Set weight\n\(currentWeight) kg",
                for: .normal
            )
            self.setWeightButton.titleLabel?.numberOfLines = 2
            self.setWeightButton.titleLabel?.textAlignment = .center
            self.setWeightButton.titleLabel?.lineBreakMode = .byWordWrapping

            print("sent weight: ", weight)
            self.bluetooth.sendWeightConfig(weight: weight)
            })

            present(alert, animated: true)
    }

    @IBAction func resetTapped(_ sender: UIButton) {
        bluetooth.sendReset()
    }
    
    private func weightInHundredths(from text: String) -> UInt16? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard let kilograms = Decimal(
            string: input,
            locale: Locale(identifier: "en_US_POSIX")
        ) else {
            return nil
        }

        let scaled = kilograms * 100
        var valueToRound = scaled
        var rounded = Decimal()

        NSDecimalRound(&rounded, &valueToRound, 0, .plain)

        guard rounded == scaled,
              rounded > 0,
              rounded <= Decimal(65_535) else {
            return nil
        }

        return NSDecimalNumber(decimal: rounded).uint16Value
    }
}
