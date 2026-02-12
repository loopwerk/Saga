import Saga

extension Reader {
  static func imageReader() -> Self {
    Reader(supportedExtensions: ["jpg", "jpeg", "png", "webp", "gif"], copySourceFiles: true) { absoluteSource in
      return (title: absoluteSource.lastComponentWithoutExtension, body: "", frontmatter: nil)
    }
  }
}
