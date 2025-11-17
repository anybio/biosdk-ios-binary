#if canImport(UIKit)
import SwiftUI
import UIKit

public struct UploadedImageView: View {
    public let image: UIImage
    public let title: String

    public init(image: UIImage, title: String) {
        self.image = image
        self.title = title
    }

    public var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .cornerRadius(12)
                .padding(.horizontal)
        }
        .padding(.vertical)
    }
}
#endif
