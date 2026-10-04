import Foundation


/// A `multipart/form-data` body whose file part comes last: send `head`, then the file bytes, then `tail`.
nonisolated struct MultipartFormData {
  let boundary = "Boundary-\(UUID().uuidString)"
  private(set) var head = Data()

  var contentType: String {
    "multipart/form-data; boundary=\(boundary)"
  }

  var tail: Data {
    Data("\r\n--\(boundary)--\r\n".utf8)
  }

  mutating func appendField(_ name: String, value: String) {
    head.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
  }

  mutating func appendFileHeader(name: String, filename: String, contentType: String) {
    head.append(Data(
      "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8
    ))
  }
}
