import UIKit.UIApplication

extension AppDelegate {
  static var container: Container {
    let delegate = UIApplication.shared.delegate as! AppDelegate
    return delegate.appContainer
  }
}
