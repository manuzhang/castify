//
// Created by doriadong on 2020/2/16.
// Copyright (c) 2020 io.github.manuzhang. All rights reserved.
//

import Foundation
import UIKit

extension UIApplication {
  func endEditing(_ force: Bool) {
    self.windows
      .filter{$0.isKeyWindow}
      .first?
      .endEditing(force)
  }
}