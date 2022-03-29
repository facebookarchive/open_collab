import UIKit

class CreationLaunchScreenViewController: UIViewController {

  @IBOutlet weak var gradientView: GradientView!
  @IBOutlet weak var welcomeLabel: UILabel!
  @IBOutlet weak var creationStackView: UIStackView!
  @IBOutlet weak var createButtonText: UILabel!
  @IBOutlet weak var createButton: UIButton!

  // MARK: - UIViewController

  override func viewDidLoad() {
    super.viewDidLoad()
    self.navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gearshape.fill")?.withRenderingMode(.alwaysTemplate),
                                                             style: .plain,
                                                             target: self,
                                                             action: #selector(didTapSettings(_:)))
    self.navigationItem.rightBarButtonItem?.tintColor = .white
    setupGradient()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
  }

  fileprivate func setupGradient() {
    gradientView.gradientLayer.setupFullScreenCollabGradientLayer()
  }

  // MARK: - Tap

  @IBAction func didTapCreateFromScratch(_ sender: Any) {
    let initialRecordViewController = InitialRecordViewController()
    self.navigationController?.pushViewController(initialRecordViewController, animated: true)
    initialRecordViewController.navigationItem.hidesBackButton = false
  }

  @objc func didTapSettings(_ sender: Any) {
    let storyboard = UIStoryboard(name: "Main", bundle: nil)
    let settingsViewController = storyboard
      .instantiateViewController(withIdentifier: "SettingsViewController") as! SettingsViewController
    self.navigationController?.pushViewController(settingsViewController, animated: true)
  }
}
