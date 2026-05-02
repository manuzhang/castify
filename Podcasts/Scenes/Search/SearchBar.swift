import SwiftUI

struct SearchBar: View {
  @Binding var text: String

  var body: some View {
    ZStack {
      HStack {
        HStack {
          Image(systemName: "magnifyingglass")

          TextField("Search", text: $text)
            .foregroundColor(.primary)

          if !text.isEmpty {
            Button(action: {
              self.text = ""
            }) {
              Image(systemName: "xmark.circle.fill")
            }
          }
        }.padding([.leading, .trailing], 8)
          .frame(height: 32)
          .foregroundColor(.secondary)
          .background(Color(.secondarySystemBackground))
          .cornerRadius(8)
        if !text.isEmpty {
          Button(
            action: {
              self.text = ""
              UIApplication.shared.endEditing(true)
            },
            label: { Text("Cancel") }
          ).foregroundColor(.blue)
        }
      }.padding([.leading, .trailing], 16)
    }.frame(height: 64)
  }
}
