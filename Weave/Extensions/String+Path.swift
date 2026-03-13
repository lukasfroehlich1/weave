import Foundation

extension String {
    var expandingTilde: String {
        NSString(string: self).expandingTildeInPath
    }
}
