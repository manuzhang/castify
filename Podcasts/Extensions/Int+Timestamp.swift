//
//  TimeInterval+MS.swift
//  Search
//
//  Created by Alberto on 11/06/2019.
//  Copyright © 2019 com.github.albertopeam. All rights reserved.
//

import Foundation

extension Int {

  var intervalFromMiliseconds: TimeInterval {
    return TimeInterval(self / 1000)
  }

}
