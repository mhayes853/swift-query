import CryptoKit
import Foundation

// MARK: - FileSystemCachedLoader

extension ImageData {
  public final actor FileSystemCachedLoader {
    private let directoryURL: URL
    private let transport: any HTTPDataTransport
    private let fileManager = FileManager.default

    public init(directoryURL: URL, transport: any HTTPDataTransport) {
      self.directoryURL = directoryURL
      self.transport = transport
    }
  }
}

// MARK: - Shared

extension ImageData.FileSystemCachedLoader {
  public static let shared = ImageData.FileSystemCachedLoader(
    directoryURL: .cachesDirectory.appending(path: "images"),
    transport: URLSession.shared
  )
}

// MARK: - Image.Loader Conformance

extension ImageData.FileSystemCachedLoader: ImageData.Loader {
  public func localImage(for url: URL) async throws -> ImageData? {
    guard let data = try? Data(contentsOf: self.localURL(for: url)) else { return nil }
    return try ImageData(data: (data as NSData).decompressed(using: .lzfse) as Data)
  }

  public func remoteImage(for url: URL) async throws -> ImageData {
    let (data, _) = try await self.transport.data(for: URLRequest(url: url))
    let image = try ImageData(data: data)
    try self.saveLocalImage(for: url, image: image)
    return image
  }

  private func saveLocalImage(for url: URL, image: ImageData) throws {
    try self.ensureDirectory()
    try (image.data as NSData).compressed(using: .lzfse)
      .write(to: self.localURL(for: url), options: [.atomicWrite])
  }

  private func localURL(for remoteURL: URL) -> URL {
    let hash = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
    let filename = hash.compactMap { String(format: "%02x", $0) }.joined()
    return self.directoryURL.appending(path: "image-\(filename)")
  }

  private func ensureDirectory() throws {
    try FileManager.default.createDirectory(
      at: self.directoryURL,
      withIntermediateDirectories: true
    )
  }
}
