import Foundation

class Container {
  private let player: Player = Player()
}

extension Container {
  private static var instance: Container {
    return AppDelegate.container
  }
  static var player: Player {
    return Container.instance.player
  }
}
